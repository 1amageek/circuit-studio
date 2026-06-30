import Foundation
import Testing
@testable import CircuitStudioApp

/// D1 (roadmap G4): the agent edit → signoff → iterate loop, driven by REAL
/// signoff. The "agent" here is a candidate provider; the loop runs real DRC+LVS
/// each round and converges when a candidate passes. Gated on the toolchain.
@Suite("Signoff iteration loop (G4, gated)")
struct SignoffIterationLoopTests {

    static let loop = SignoffIterationLoop.locate()

    private func fixture(_ name: String, _ ext: String, _ sub: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: sub))
    }

    private func makeDir(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SignoffLoop-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("The loop requests candidates lazily and stops after the first passing review")
    func candidateProviderIsLazy() async throws {
        let work = try makeDir("lazy")
        defer { removeCoreTestTemporaryDirectory(work) }

        let recorder = SignoffLoopRecorder()
        let loop = SignoffIterationLoop { _, topCell, _, artifactDirectory in
            let executionIndex = await recorder.recordExecution(topCell)
            #expect(artifactDirectory.lastPathComponent == "iter-\(executionIndex)")
            return passingReview(logPath: artifactDirectory.appending(path: "fake.log").path(percentEncoded: false))
        }

        var requestedIndices: [Int] = []
        let result = try await loop.run(maxIterations: 3, artifactDirectory: work) { index, lastReview in
            requestedIndices.append(index)
            #expect(lastReview == nil)
            if index > 0 {
                Issue.record("Candidate \(index) should not be requested after the first pass.")
            }
            return SignoffIterationLoop.Candidate(
                layoutGDS: URL(filePath: "/tmp/layout-\(index).gds"),
                topCell: "candidate-\(index)",
                schematicNetlist: URL(filePath: "/tmp/schematic-\(index).spice")
            )
        }

        #expect(result.converged)
        #expect(result.iterations.map(\.candidate.topCell) == ["candidate-0"])
        #expect(requestedIndices == [0])
        #expect(await recorder.executedCells() == ["candidate-0"])
    }

    @Test(
        "The loop iterates past a failing candidate and converges on a passing one",
        .enabled(if: SignoffIterationLoopTests.loop != nil),
        .timeLimit(.minutes(4))
    )
    func convergesAfterFix() async throws {
        let loop = try #require(Self.loop)
        let work = try makeDir("converge")
        defer { removeCoreTestTemporaryDirectory(work) }

        // The "agent" first proposes a DRC-violating layout, then (after seeing the
        // failing review) a clean one — modelling an edit that fixes the violation.
        let broken = SignoffIterationLoop.Candidate(
            layoutGDS: try fixture("met1_spacing_violation", "gds", "magic"),
            topCell: "drc_broken",
            schematicNetlist: try fixture("inv_schematic", "spice", "lvs")
        )
        let fixed = SignoffIterationLoop.Candidate(
            layoutGDS: try fixture("inv1", "gds", "lvs"),
            topCell: "sky130_fd_sc_hd__inv_1",
            schematicNetlist: try fixture("inv_schematic", "spice", "lvs")
        )

        let result = try await loop.run(maxIterations: 5, artifactDirectory: work) { index, lastReview in
            switch index {
            case 0:
                #expect(lastReview == nil)
                return broken
            case 1:
                #expect(lastReview?.passed == false, "the agent should iterate only after a failing review")
                return fixed
            default:
                return nil
            }
        }

        #expect(result.converged)
        #expect(result.iterations.count == 2)
        #expect(result.iterations[0].passed == false)
        #expect(result.iterations[1].passed == true)
    }

    @Test(
        "The loop reports non-convergence when the budget is exhausted, and rejects a zero budget",
        .enabled(if: SignoffIterationLoopTests.loop != nil),
        .timeLimit(.minutes(3))
    )
    func nonConvergenceAndBudgetGuard() async throws {
        let loop = try #require(Self.loop)
        let work = try makeDir("nonconverge")
        defer { removeCoreTestTemporaryDirectory(work) }

        let broken = SignoffIterationLoop.Candidate(
            layoutGDS: try fixture("met1_spacing_violation", "gds", "magic"),
            topCell: "drc_broken",
            schematicNetlist: try fixture("inv_schematic", "spice", "lvs")
        )

        // Always proposes the failing candidate → never converges within the budget.
        let result = try await loop.run(maxIterations: 2, artifactDirectory: work) { _, _ in broken }
        #expect(!result.converged)
        #expect(result.iterations.count == 2)
        #expect(result.iterations.allSatisfy { !$0.passed })

        await #expect(throws: SignoffIterationLoop.LoopError.nonPositiveIterationBudget) {
            _ = try await loop.run(maxIterations: 0, artifactDirectory: work) { _, _ in broken }
        }
    }

    private func passingReview(logPath: String) -> ExternalSignoffReview {
        ExternalSignoffReview(reports: [
            ExternalSignoffToolReport(
                kind: .drc,
                toolName: "fake-drc",
                success: true,
                completed: true,
                logPath: logPath
            ),
            ExternalSignoffToolReport(
                kind: .lvs,
                toolName: "fake-lvs",
                success: true,
                completed: true,
                logPath: logPath
            ),
        ])
    }
}

private actor SignoffLoopRecorder {
    private var cells: [String] = []

    func recordExecution(_ cell: String) -> Int {
        cells.append(cell)
        return cells.count - 1
    }

    func executedCells() -> [String] {
        cells
    }
}
