import Foundation
import Testing
@testable import CircuitStudioApp

/// The goal-driven layout agent is reachable through the SAME typed
/// command surface the flow-runner CLI exposes: a `.subckt` intent plus
/// a technology package close into an evidence JSON and a GDS artifact
/// under the run's ledger directory, with no in-process Swift required
/// from the caller.
@Suite("Design flow goal agent command", .timeLimit(.minutes(3)))
struct DesignFlowGoalAgentCommandTests {

    private static let chainIntent = """
    .subckt chain a mid out gnd
    M1 mid a gnd gnd nmos W=2u L=0.18u
    M2 out mid gnd gnd nmos W=2u L=0.18u
    .ends
    """

    @Test
    @MainActor
    func commandClosesSubcktIntentAndPersistsEvidence() async throws {
        let packageURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("goal-agent-command")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let subcktURL = root.appending(path: "chain.subckt")
        try Self.chainIntent.write(to: subcktURL, atomically: true, encoding: .utf8)

        let result = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .runGoalLayoutAgent,
            projectRootPath: root.path(percentEncoded: false),
            runID: "goal-agent-run",
            technologyPackagePath: packageURL.path(percentEncoded: false),
            intentSubcktPath: subcktURL.path(percentEncoded: false)
        ))

        #expect(result.goalAgentClosed == true)
        #expect(result.designName == "chain")
        #expect(result.message == "closed")

        let gdsPath = try #require(result.exportedLayoutPath)
        #expect(FileManager.default.fileExists(atPath: gdsPath))
        #expect(gdsPath.hasSuffix(".gds"))
        #expect(gdsPath.contains(".xcircuite/runs/goal-agent-run/goal-agent"))

        let evidencePath = try #require(result.goalAgentEvidencePath)
        let evidenceData = try Data(contentsOf: URL(filePath: evidencePath))
        let evidence = try #require(
            try JSONSerialization.jsonObject(with: evidenceData) as? [String: Any]
        )
        #expect(evidence["closed"] as? Bool == true)
        #expect(evidence["replayDeterministic"] as? Bool == true)
        #expect(evidence["designName"] as? String == "chain")
        let script = try #require(evidence["script"] as? [[String: Any]])
        #expect(!script.isEmpty)
        let trust = try #require(evidence["trust"] as? [String: Any])
        #expect(trust["drc"] as? String == "clean")
        #expect(trust["lvs"] as? String == "clean")
    }

    @Test
    @MainActor
    func commandRequiresIntentSubcktPath() async throws {
        let packageURL = try DesignFlowServiceTestSupport.rootFixtureURL("technology-package", extension: "json")
        await #expect(throws: DesignFlowCommandError.missingIntentSubcktPath) {
            _ = try await DesignFlowService().execute(DesignFlowCommand(
                kind: .runGoalLayoutAgent,
                runID: "goal-agent-run",
                technologyPackagePath: packageURL.path(percentEncoded: false)
            ))
        }
    }

    @Test
    func flowRunnerOptionsParseGoalLayoutAgentMode() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--run-goal-layout-agent",
            "--subckt", "/tmp/chain.subckt",
            "--design-name", "chain",
            "--technology-package", "/tmp/package.json",
            "--output", "/tmp/project",
            "--run-id", "goal-agent-run",
            "--json",
        ])
        let command = options.makeCommand()
        #expect(command.kind == .runGoalLayoutAgent)
        #expect(command.intentSubcktPath == "/tmp/chain.subckt")
        #expect(command.designName == "chain")
        #expect(command.technologyPackagePath == "/tmp/package.json")
        #expect(command.projectRootPath == "/tmp/project")
        #expect(command.runID == "goal-agent-run")
    }

    @Test
    func subcktNameParsesHeader() {
        #expect(DesignFlowService.subcktName(in: Self.chainIntent) == "chain")
        #expect(DesignFlowService.subcktName(in: "* comment only\n") == nil)
    }
}
