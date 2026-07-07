import Foundation
import Testing
import LayoutCore
import LayoutEditor
import LayoutTech
import LayoutIO
@testable import CircuitStudioApp

/// C5 gate: the agent closes a `.subckt` intent through the editor's
/// goal-command surface alone — the same commands the human keymap
/// issues — and the outcome is auditable (goal log), reproducible
/// (replay determinism), and independently re-verifiable (the exported
/// GDS re-passes LVS from its labels after losing pins and nets).
@MainActor
@Suite("Goal-driven layout agent", .timeLimit(.minutes(3)))
struct GoalDrivenLayoutAgentTests {

    private static let chainIntent = """
    .subckt chain a mid out gnd
    M1 mid a gnd gnd nmos W=2u L=0.18u
    M2 out mid gnd gnd nmos W=2u L=0.18u
    .ends
    """

    @Test func chainIntentClosesThroughGoalCommandsAndSurvivesGDS() throws {
        let tech = LayoutTechDatabase.sampleProcess()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("goal-agent-\(UUID().uuidString)")
        defer { Self.removeTemporaryDirectory(directory) }

        let agent = GoalDrivenLayoutAgent(designName: "CHAIN", tech: tech)
        let evidence = try agent.close(intent: Self.chainIntent, exportDirectory: directory)

        #expect(evidence.closed)
        #expect(evidence.trustReport.drc == .clean)
        #expect(evidence.trustReport.connectivity == .clean)
        #expect(evidence.trustReport.lvs == .clean)
        #expect(evidence.replayDeterministic)
        #expect(evidence.script.contains(.bindIntentTerminals))
        #expect(!evidence.goalLog.isEmpty)
        let allCommandsSucceeded = evidence.goalLog.allSatisfy(\.succeeded)
        #expect(allCommandsSucceeded)

        // The artifact stands on its own: reimport drops pins and nets
        // by format contract, and label-driven extraction must still
        // match the same intent with no editing.
        let reimported = try GDSFormatConverter(tech: tech)
            .importDocument(from: evidence.gdsURL, format: .gds)
        let reopened = LayoutEditorViewModel(document: reimported, tech: tech)
        reopened.loadLVSReference(fromSubckt: Self.chainIntent)
        #expect(
            reopened.liveLVSPassed == true,
            "\(String(describing: reopened.lvsComparison))"
        )
    }

    @Test func unrealizableIntentFailsLoudly() {
        let tech = LayoutTechDatabase.sampleProcess()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("goal-agent-\(UUID().uuidString)")
        defer { Self.removeTemporaryDirectory(directory) }

        let agent = GoalDrivenLayoutAgent(designName: "EMPTY", tech: tech)
        #expect(throws: GoalDrivenLayoutAgent.AgentError.noIntentDevices) {
            _ = try agent.close(
                intent: """
                .subckt empty a
                .ends
                """,
                exportDirectory: directory
            )
        }
    }

    @Test func designNamePathSegmentsDoNotEscapeExportDirectory() throws {
        let tech = LayoutTechDatabase.sampleProcess()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("goal-agent-\(UUID().uuidString)")
        defer { Self.removeTemporaryDirectory(directory) }

        let agent = GoalDrivenLayoutAgent(designName: "../CHAIN/escaped", tech: tech)
        let evidence = try agent.close(intent: Self.chainIntent, exportDirectory: directory)

        let directoryPath = directory.standardizedFileURL.path(percentEncoded: false)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let gdsPath = evidence.gdsURL.standardizedFileURL.path(percentEncoded: false)
        #expect(gdsPath.hasPrefix("/" + directoryPath + "/"))
        #expect(evidence.gdsURL.lastPathComponent == ".._CHAIN_escaped.gds")
        #expect(FileManager.default.fileExists(atPath: gdsPath))
    }

    private static func removeTemporaryDirectory(_ url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Issue.record("Failed to remove temporary goal-agent directory at \(url.path): \(error)")
        }
    }
}
