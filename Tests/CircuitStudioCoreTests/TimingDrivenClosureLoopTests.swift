import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
import STAEngine
import Testing
import TimingCore
@testable import CircuitStudioApp

@Suite("Timing-driven closure")
struct TimingDrivenClosureLoopTests {
    @Test("Canonical STA feedback drives cell sizing")
    func canonicalSTAFeedbackDrivesSizing() async throws {
        let engine = StubSTAEngine(results: [
            try result(slack: -20e-12, stageCell: "inv"),
            try result(slack: 5e-12, stageCell: "inv_x2"),
        ])
        let loop = TimingDrivenClosureLoop(
            engine: engine,
            requestBuilder: FixedSTARequestBuilder(request: try request())
        )
        let netlist = SequentialNetlist(
            name: "unit",
            combinational: [
                .init(
                    name: "g0",
                    cell: try .inverter(name: "inv"),
                    netMap: ["A": "a", "Y": "y"]
                ),
            ],
            dffs: [],
            inputs: ["a"],
            outputs: ["y"]
        )

        let outcome = try await loop.close(netlist, maxIterations: 2)

        #expect(outcome.converged)
        #expect(outcome.iterations.map(\.met) == [false, true])
        #expect(outcome.iterations.first?.upsizedInstance == "g0")
        #expect(outcome.netlist.combinational.first?.cell.name == "inv_x2")
        #expect(outcome.result.payload.worstSetupSlack == 5e-12)
    }

    @Test("A non-completed STA result is rejected")
    func incompleteResultIsRejected() async throws {
        let failed = try result(slack: nil, stageCell: nil, status: .failed)
        let loop = TimingDrivenClosureLoop(
            engine: StubSTAEngine(results: [failed]),
            requestBuilder: FixedSTARequestBuilder(request: try request())
        )
        let netlist = SequentialNetlist(
            name: "unit",
            combinational: [],
            dffs: [],
            inputs: [],
            outputs: []
        )

        await #expect(throws: TimingDrivenClosureLoop.ClosureError.self) {
            _ = try await loop.close(netlist, maxIterations: 1)
        }
    }

    @Test("The final resized netlist is analyzed after the edit budget is consumed")
    func finalResizedNetlistIsAnalyzed() async throws {
        let engine = StubSTAEngine(results: [
            try result(slack: -20e-12, stageCell: "inv"),
            try result(slack: 5e-12, stageCell: "inv_x2"),
        ])
        let loop = TimingDrivenClosureLoop(
            engine: engine,
            requestBuilder: FixedSTARequestBuilder(request: try request())
        )
        let netlist = SequentialNetlist(
            name: "unit",
            combinational: [
                .init(
                    name: "g0",
                    cell: try .inverter(name: "inv"),
                    netMap: ["A": "a", "Y": "y"]
                ),
            ],
            dffs: [],
            inputs: ["a"],
            outputs: ["y"]
        )

        let outcome = try await loop.close(netlist, maxIterations: 1)

        #expect(outcome.converged)
        #expect(outcome.iterations.count == 1)
        #expect(outcome.netlist.combinational.first?.cell.name == "inv_x2")
        #expect(outcome.result.payload.worstSetupSlack == 5e-12)
    }

    private func request() throws -> STARequest {
        let data = Data("{}".utf8)
        let reference = try ArtifactReference(
            digest: try SHA256ContentDigester().digest(data: data, using: .sha256),
            byteCount: UInt64(data.count),
            descriptor: ArtifactDescriptor(
                role: .input,
                kind: .netlist,
                format: .json
            )
        )
        let binding = try TimingArtifactBinding(
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(rawValue: TimingArtifactBinding.workspaceRootIdentifier),
                relativePath: ArtifactRelativePath(segments: ["fixture.json"])
            )
        )
        return try STARequest(
            runID: "unit",
            design: binding,
            topDesignName: "unit",
            libraries: [],
            constraints: binding,
            pdkManifest: binding,
            processID: "test",
            pdkVersion: "1"
        )
    }

    private func result(
        slack: Double?,
        stageCell: String?,
        status: TimingExecutionStatus = .completed
    ) throws -> STAExecutionResult {
        let paths: [STAPath]
        if let slack, let stageCell {
            paths = [
                STAPath(
                    modeID: "functional",
                    cornerID: "tt",
                    startpoint: "a",
                    endpoint: "y",
                    arrival: 100e-12,
                    required: 100e-12 + slack,
                    slack: slack,
                    stages: [
                        STAPathStage(
                            instance: "g0",
                            cell: stageCell,
                            inputPin: "A",
                            inputNet: "a",
                            outputNet: "y",
                            inputEdge: .rise,
                            outputEdge: .fall,
                            delay: 100e-12,
                            outputSlew: 40e-12,
                            load: 1e-15
                        ),
                    ]
                ),
            ]
        } else {
            paths = []
        }
        let timestamp = Date(timeIntervalSince1970: 1)
        return try STAExecutionResult(
            runID: "unit",
            status: status,
            payload: STAPayload(
                worstSetupSlack: slack,
                worstHoldSlack: slack,
                analyzedCorners: ["tt"],
                criticalPaths: paths
            ),
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(kind: .engine, identifier: "timing.sta", version: "1"),
                startedAt: timestamp,
                completedAt: timestamp
            )
        )
    }
}

private struct FixedSTARequestBuilder: STARequestBuilding {
    let request: STARequest

    func makeRequest(for netlist: SequentialNetlist, iteration: Int) async throws -> STARequest {
        request
    }
}

private actor StubSTAEngine: STAExecuting {
    private let results: [STAExecutionResult]
    private var index = 0

    init(results: [STAExecutionResult]) {
        self.results = results
    }

    func execute(_ request: STARequest) async throws -> STAExecutionResult {
        let result = results[min(index, results.count - 1)]
        index += 1
        return result
    }
}
