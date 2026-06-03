import Foundation
import LayoutCore
import Testing
@testable import CircuitStudioApp

@Suite("circuit-studio-flow-runner CLI", .serialized)
struct FlowRunnerCLITests {
    @Test("run-layout-trust emits layout trust status without PEX readiness", .timeLimit(.minutes(5)))
    func runLayoutTrustOutputKeysSeparateTrustFromPEXReadiness() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioFlowRunnerCLITests-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary directory \(root.path(percentEncoded: false)): \(error)")
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let layoutURL = root.appending(path: "layout.json")
        try writeTrustedLayout(to: layoutURL)
        let outputRoot = root.appending(path: "out")
        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runLayoutTrust,
            projectRootPath: outputRoot.path(percentEncoded: false),
            runID: "layout-trust-cli",
            layoutDocumentPath: layoutURL.path(percentEncoded: false)
        ))
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)
        #expect(keys["layout_trust"] == "passed")
        #expect(keys["layout_trust_passed"] == "true")
        #expect(keys["layout_trust_report"]?.hasSuffix(".xcircuite/runs/layout-trust-cli/layout/layout-trust-report.json") == true)
        #expect(keys["ready_for_pex"] == nil)
    }

    @Test("run-verification emits both PEX readiness and layout trust status", .timeLimit(.minutes(1)))
    func runVerificationOutputKeysSeparatePEXReadinessFromLayoutTrust() {
        let result = DesignFlowCommandResult(
            kind: .runVerification,
            fixtureName: "unit",
            readyForPEX: false,
            layoutTrustPassed: true,
            layoutTrustReportPath: "/tmp/layout-trust-report.json",
            verificationReportPath: "/tmp/verification-report.json"
        )
        let output = FlowRunnerKeyValueFormatter.lines(for: result).joined(separator: "\n")
        let keys = keyValueOutput(output)

        #expect(keys["ready_for_pex"] == "false")
        #expect(keys["layout_trust_passed"] == "true")
        #expect(keys["verification_report"] == "/tmp/verification-report.json")
        #expect(keys["layout_trust_report"] == "/tmp/layout-trust-report.json")
    }

    @Test("run-verification arguments construct the verification command", .timeLimit(.minutes(1)))
    func runVerificationArgumentsConstructCommand() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--run-verification",
            "--fixture", "acc4",
            "--output", "/tmp/flow-output",
            "--run-id", "verify-1",
            "--layout-document", "/tmp/layout.json",
            "--design-unit", "/tmp/design-unit.json",
            "--approve-signoff",
        ])
        let command = options.makeCommand()

        #expect(options.mode == .runVerification)
        #expect(command.kind == .runVerification)
        #expect(command.fixtureName == "acc4")
        #expect(command.projectRootPath == "/tmp/flow-output")
        #expect(command.runID == "verify-1")
        #expect(command.layoutDocumentPath == "/tmp/layout.json")
        #expect(command.designUnitPath == "/tmp/design-unit.json")
        #expect(command.approveSignoff == true)
    }

    @Test("conflicting runner modes are rejected by the shared parser", .timeLimit(.minutes(1)))
    func conflictingRunnerModesAreRejected() {
        #expect(throws: FlowRunnerCommandOptions.ParseError.conflictingModes) {
            _ = try FlowRunnerCommandOptions(arguments: ["--run-layout-trust", "--run-verification"])
        }
    }

    private func writeTrustedLayout(to url: URL) throws {
        let cellID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let netID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let shapeID = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
        let layout = LayoutDocument(
            name: "TrustedLayout",
            cells: [
                LayoutCell(
                    id: cellID,
                    name: "TOP",
                    shapes: [
                        LayoutShape(
                            id: shapeID,
                            layer: LayoutLayerID(name: "M1", purpose: "drawing"),
                            netID: netID,
                            geometry: .rect(LayoutRect(
                                origin: LayoutPoint(x: 0, y: 0),
                                size: LayoutSize(width: 2, height: 1)
                            ))
                        ),
                    ],
                    nets: [LayoutNet(id: netID, name: "out")]
                ),
            ],
            topCellID: cellID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: url, options: .atomic)
    }

    private func keyValueOutput(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            result[key] = value
        }
        return result
    }
}
