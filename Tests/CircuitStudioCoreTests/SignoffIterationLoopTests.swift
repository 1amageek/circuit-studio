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

    @Test(
        "The loop iterates past a failing candidate and converges on a passing one",
        .enabled(if: SignoffIterationLoopTests.loop != nil),
        .timeLimit(.minutes(4))
    )
    func convergesAfterFix() async throws {
        let loop = try #require(Self.loop)
        let work = try makeDir("converge")
        defer { try? FileManager.default.removeItem(at: work) }

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
        defer { try? FileManager.default.removeItem(at: work) }

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
}
