import Foundation
import LayoutEditor

extension DesignFlowService {

    /// Runs `GoalDrivenLayoutAgent` headlessly: reads the `.subckt`
    /// intent, resolves the layout technology from the technology
    /// package, closes the intent through goal commands, and persists an
    /// evidence JSON next to the exported GDS under the run's artifact
    /// directory. A non-closable intent throws the agent's typed failing
    /// stage — the command never reports a half-closed artifact.
    @MainActor
    func runGoalLayoutAgent(_ command: DesignFlowCommand) throws -> DesignFlowCommandResult {
        guard let intentSubcktPath = command.intentSubcktPath else {
            throw DesignFlowCommandError.missingIntentSubcktPath
        }
        let subckt = try String(contentsOf: URL(filePath: intentSubcktPath), encoding: .utf8)
        guard let designName = command.designName ?? Self.subcktName(in: subckt) else {
            throw DesignFlowCommandError.missingIntentSubcktName
        }
        let package = try requiredTechnologyPackage(for: command)
        let tech = try layoutTech(for: package)
        let exportDirectory = try runArtifactDirectory(for: command, fallbackRootName: "goal-agent-runs")
            .appending(path: "goal-agent")

        let agent = GoalDrivenLayoutAgent(designName: designName, tech: tech)
        let evidence = try agent.close(intent: subckt, exportDirectory: exportDirectory)

        let evidenceURL = exportDirectory.appending(path: "goal-agent-evidence.json")
        let artifact = GoalAgentEvidenceArtifact(evidence: evidence, designName: designName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(artifact).write(to: evidenceURL, options: .atomic)

        return DesignFlowCommandResult(
            kind: command.kind,
            designName: designName,
            runID: command.runID,
            projectRootPath: command.projectRootPath,
            technologyPackageID: package.manifest.packageID,
            technologyPackagePath: package.manifestURL.path(percentEncoded: false),
            goalAgentClosed: evidence.closed,
            goalAgentEvidencePath: evidenceURL.path(percentEncoded: false),
            exportedLayoutPath: evidence.gdsURL.path(percentEncoded: false),
            message: evidence.closed ? "closed" : "not-closed"
        )
    }

    /// The name declared by the first `.subckt` header line, if any.
    static func subcktName(in subckt: String) -> String? {
        for line in subckt.split(whereSeparator: \.isNewline) {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count >= 2, tokens[0].lowercased() == ".subckt" else { continue }
            return String(tokens[1])
        }
        return nil
    }
}

/// The persisted, machine-readable projection of one goal-agent closure:
/// the replayable script, the per-command verdict log, the trust axes,
/// and the artifact identity. Everything a reviewer or a downstream
/// signoff loop needs without re-running the agent.
struct GoalAgentEvidenceArtifact: Encodable {
    struct GoalLogEntry: Encodable {
        let command: LayoutGoalCommand
        let succeeded: Bool
        let violationsBefore: Int
        let violationsAfter: Int
        let opensBefore: Int
        let opensAfter: Int
        let lvsMatchedBefore: Int
        let lvsMatchedAfter: Int
    }

    struct TrustAxes: Encodable {
        let drc: String
        let connectivity: String
        let constraints: String
        let lvs: String
        let electrical: String
        let verificationPending: Bool
    }

    let designName: String
    let closed: Bool
    let replayDeterministic: Bool
    let script: [LayoutGoalCommand]
    let goalLog: [GoalLogEntry]
    let trust: TrustAxes
    let gdsPath: String

    init(evidence: GoalDrivenLayoutAgent.Evidence, designName: String) {
        self.designName = designName
        self.closed = evidence.closed
        self.replayDeterministic = evidence.replayDeterministic
        self.script = evidence.script
        self.goalLog = evidence.goalLog.map { record in
            GoalLogEntry(
                command: record.command,
                succeeded: record.succeeded,
                violationsBefore: record.violationsBefore,
                violationsAfter: record.violationsAfter,
                opensBefore: record.opensBefore,
                opensAfter: record.opensAfter,
                lvsMatchedBefore: record.lvsMatchedBefore,
                lvsMatchedAfter: record.lvsMatchedAfter
            )
        }
        self.trust = TrustAxes(
            drc: Self.describe(evidence.trustReport.drc),
            connectivity: Self.describe(evidence.trustReport.connectivity),
            constraints: Self.describe(evidence.trustReport.constraints),
            lvs: Self.describe(evidence.trustReport.lvs),
            electrical: Self.describe(evidence.trustReport.electrical),
            verificationPending: evidence.trustReport.verificationPending
        )
        self.gdsPath = evidence.gdsURL.path(percentEncoded: false)
    }

    private static func describe(_ verdict: LayoutTrustReport.AxisVerdict) -> String {
        switch verdict {
        case .clean:
            return "clean"
        case .findings(let count):
            return "findings(\(count))"
        case .unavailable(let reason):
            return "unavailable(\(reason))"
        }
    }
}
