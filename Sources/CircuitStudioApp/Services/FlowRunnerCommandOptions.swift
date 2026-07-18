import Foundation
import CircuitStudioCore
import DesignFlowKernel

public struct FlowRunnerCommandOptions: Sendable {
    public enum OutputFormat: Sendable, Equatable {
        case keyValue
        case json
    }

    public enum Mode: Sendable, Equatable {
        case listFixtures
        case generateNetlist
        case simulate
        case runRoundTrip
        case summarizeBottlenecks
        case summarizeSignoffRepairCandidateCycles
        case assessSignoffRepairCandidateCycles
        case loadTechnologyPackage
        case runPEXExtraction
        case inspectTimingModelProfiles
        case buildTimingLibrary
        case applyDesignEdit
        case applyLayoutEdit
        case runLayoutTrust
        case runVerification
        case approveGate
        case reviewRoundTrip
        case selectFailureSuggestedAction
        case runSelectedSuggestedAction
        case applyWaiverEditProposal
        case runPostWaiverEditVerification
        case applyWaiverEditProposalAndRunPostVerification
        case formulateSignoffRepairPlanningProblem
        case runSignoffRepairCandidateCycle
        case runGoalLayoutAgent
        case scaffoldDesignSpec

        public func commandKind(usesDesignSpec: Bool) -> DesignFlowCommand.Kind {
            switch self {
            case .listFixtures:
                return .listFixtures
            case .generateNetlist:
                return usesDesignSpec ? .generateDesignNetlist : .generateFixtureNetlist
            case .simulate:
                return usesDesignSpec ? .runDesignSimulation : .runFixtureSimulation
            case .runRoundTrip:
                return usesDesignSpec ? .runDesignRoundTrip : .runFixtureRoundTrip
            case .summarizeBottlenecks:
                return .summarizeBottlenecks
            case .summarizeSignoffRepairCandidateCycles:
                return .summarizeSignoffRepairCandidateCycles
            case .assessSignoffRepairCandidateCycles:
                return .assessSignoffRepairCandidateCycles
            case .loadTechnologyPackage:
                return .loadTechnologyPackage
            case .runPEXExtraction:
                return .runPEXExtraction
            case .inspectTimingModelProfiles:
                return .inspectTimingModelProfiles
            case .buildTimingLibrary:
                return .buildTimingLibrary
            case .applyDesignEdit:
                return .applyDesignEdit
            case .applyLayoutEdit:
                return .applyLayoutEdit
            case .runLayoutTrust:
                return .runLayoutTrust
            case .runVerification:
                return .runVerification
            case .approveGate:
                return .approveGate
            case .reviewRoundTrip:
                return .reviewRoundTrip
            case .selectFailureSuggestedAction:
                return .selectFailureSuggestedAction
            case .runSelectedSuggestedAction:
                return .runSelectedSuggestedAction
            case .applyWaiverEditProposal:
                return .applyWaiverEditProposal
            case .runPostWaiverEditVerification:
                return .runPostWaiverEditVerification
            case .applyWaiverEditProposalAndRunPostVerification:
                return .applyWaiverEditProposalAndRunPostVerification
            case .formulateSignoffRepairPlanningProblem:
                return .formulateSignoffRepairPlanningProblem
            case .runSignoffRepairCandidateCycle:
                return .runSignoffRepairCandidateCycle
            case .runGoalLayoutAgent:
                return .runGoalLayoutAgent
            case .scaffoldDesignSpec:
                return .scaffoldDesignSpec
            }
        }
    }

    public enum ParseError: Error, LocalizedError, Equatable {
        case invalidArgument(String)
        case missingValue(String)
        case invalidNumericValue(String, String)
        case invalidDomainLimit(String)
        case invalidVariableLimit(String)
        case invalidOscillationLimit(String)
        case invalidApprovalStageID(String)
        case invalidApprovalVerdict(String)
        case invalidActorKind(String)
        case conflictingModes

        public var errorDescription: String? {
            switch self {
            case .invalidArgument(let argument):
                return "Invalid argument: \(argument)"
            case .missingValue(let option):
                return "Missing value for \(option)"
            case .invalidNumericValue(let option, let value):
                return "Invalid numeric value for \(option): \(value)"
            case .invalidDomainLimit(let value):
                return "Invalid domain comparison limit: \(value)"
            case .invalidVariableLimit(let value):
                return "Invalid variable comparison limit: \(value)"
            case .invalidOscillationLimit(let value):
                return "Invalid oscillation metric limit: \(value)"
            case .invalidApprovalStageID(let value):
                return "Invalid approval stage ID: \(value)"
            case .invalidApprovalVerdict(let value):
                return "Invalid approval verdict: \(value)"
            case .invalidActorKind(let value):
                return "Invalid actor kind: \(value)"
            case .conflictingModes:
                return "Only one runner mode can be selected."
            }
        }
    }

    public var mode = Mode.runRoundTrip
    public var fixtureName = DesignFlowFixtureLibrary.defaultFixtureName
    public var designSpecURL: URL?
    public var outputURL: URL?
    public var runID: String?
    public var pexManifestURL: URL?
    public var pexConfigURL: URL?
    public var pexExecutableURL: URL?
    public var timingModelProfileURL: URL?
    public var timingModelProfileCatalogURL: URL?
    public var timingModelProfileID: String?
    public var timingModelCornerID: String?
    public var editScriptURL: URL?
    public var outputDesignSpecURL: URL?
    public var layoutDocumentURL: URL?
    public var outputLayoutDocumentURL: URL?
    public var designUnitURL: URL?
    public var reviewManifestURL: URL?
    public var failureEnvelopeURL: URL?
    public var suggestedActionID: String?
    public var approvalStageID: String?
    public var approvalReviewer: String?
    public var approvalVerdict: FlowApprovalRecord.Verdict?
    public var approvalNote: String?
    public var waiverReviewID: String?
    public var waiverProposalID: String?
    public var actionActorKind: FlowRunActor.Kind?
    public var drcRepairHintPath: String?
    public var lvsRepairHintPath: String?
    public var planningFormulationID: String?
    public var planningIntentID: String?
    public var planningIntent: String?
    public var planningProblemID: String?
    public var candidateStrategy: String?
    public var candidateVerificationMode: String?
    public var signoffRepairHistoryAssessmentProfileURL: URL?
    public var signoffRepairHistoryMinimumRunCount: Int?
    public var signoffRepairHistoryMinimumCycleCount: Int?
    public var signoffRepairHistoryMinimumAcceptedCount: Int?
    public var signoffRepairHistoryMinimumFeedbackRankChangeCount: Int?
    public var signoffRepairHistoryMinimumFeedbackScoreDeltaCount: Int?
    public var signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain: Int?
    public var signoffRepairHistoryRequiredSelectedActionDomainIDs: [String] = []
    public var signoffRepairHistoryRequiredSelectedObjectiveDomainIDs: [String] = []
    public var pexCornerID = "tt_25c_1v0"
    public var signoffDRCLogURL: URL?
    public var signoffLVSLogURL: URL?
    public var maxAbsoluteDelta: Double?
    public var maxRelativeDelta: Double?
    public var relativeDeltaDenominatorFloor: Double?
    public var domainComparisonLimits: [PostLayoutSignalDomainComparisonLimit] = []
    public var variableComparisonLimits: [CircuitStudioCore.PostLayoutVariableComparisonLimit] = []
    public var oscillationMetricLimits: [PostLayoutOscillationMetricLimit] = []
    public var technologyPackageURL: URL?
    public var intentSubcktURL: URL?
    public var designName: String?
    public var approveSignoff = false
    public var showHelp = false
    public var outputFormat = OutputFormat.keyValue

    private var explicitMode: Mode?

    public init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--list-fixtures":
                try selectMode(.listFixtures)
            case "--generate-netlist":
                try selectMode(.generateNetlist)
            case "--simulate":
                try selectMode(.simulate)
            case "--summarize-bottlenecks":
                try selectMode(.summarizeBottlenecks)
            case "--summarize-signoff-repair-cycles":
                try selectMode(.summarizeSignoffRepairCandidateCycles)
            case "--assess-signoff-repair-cycles":
                try selectMode(.assessSignoffRepairCandidateCycles)
            case "--load-technology-package":
                try selectMode(.loadTechnologyPackage)
            case "--run-pex-extraction":
                try selectMode(.runPEXExtraction)
            case "--inspect-timing-model-profiles":
                try selectMode(.inspectTimingModelProfiles)
            case "--build-timing-library":
                try selectMode(.buildTimingLibrary)
            case "--apply-design-edit":
                try selectMode(.applyDesignEdit)
            case "--apply-layout-edit":
                try selectMode(.applyLayoutEdit)
            case "--run-layout-trust":
                try selectMode(.runLayoutTrust)
            case "--run-verification":
                try selectMode(.runVerification)
            case "--approve-gate":
                try selectMode(.approveGate)
            case "--review-round-trip":
                try selectMode(.reviewRoundTrip)
            case "--select-failure-action":
                try selectMode(.selectFailureSuggestedAction)
            case "--run-selected-suggested-action":
                try selectMode(.runSelectedSuggestedAction)
            case "--apply-waiver-edit":
                try selectMode(.applyWaiverEditProposal)
            case "--apply-waiver-edit-and-verify":
                try selectMode(.applyWaiverEditProposalAndRunPostVerification)
            case "--run-post-waiver-edit-verification":
                try selectMode(.runPostWaiverEditVerification)
            case "--verify-waiver-edit":
                try selectMode(.runPostWaiverEditVerification)
            case "--formulate-signoff-repair-planning":
                try selectMode(.formulateSignoffRepairPlanningProblem)
            case "--run-signoff-repair-candidate-cycle":
                try selectMode(.runSignoffRepairCandidateCycle)
            case "--run-goal-layout-agent":
                try selectMode(.runGoalLayoutAgent)
            case "--scaffold-design-spec":
                try selectMode(.scaffoldDesignSpec)
            case "--subckt":
                intentSubcktURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--design-name":
                designName = try Self.value(after: argument, in: arguments, index: &index)
            case "--fixture":
                fixtureName = try Self.value(after: argument, in: arguments, index: &index)
            case "--design-spec":
                designSpecURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--technology-package":
                technologyPackageURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--output":
                outputURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--run-id":
                runID = try Self.value(after: argument, in: arguments, index: &index)
            case "--pex-manifest":
                pexManifestURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--pex-config":
                pexConfigURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--pex-executable":
                pexExecutableURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--timing-model-profile":
                timingModelProfileURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--timing-model-profile-catalog":
                timingModelProfileCatalogURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--timing-model-profile-id":
                timingModelProfileID = try Self.value(after: argument, in: arguments, index: &index)
            case "--timing-model-corner":
                timingModelCornerID = try Self.value(after: argument, in: arguments, index: &index)
            case "--edit-script":
                editScriptURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--output-design-spec":
                outputDesignSpecURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--layout-document":
                layoutDocumentURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--output-layout-document":
                outputLayoutDocumentURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--design-unit":
                designUnitURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--manifest":
                reviewManifestURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--failure-envelope":
                failureEnvelopeURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--action-id":
                suggestedActionID = try Self.value(after: argument, in: arguments, index: &index)
            case "--approval-stage":
                approvalStageID = try Self.approvalStageID(after: argument, in: arguments, index: &index)
            case "--reviewer":
                approvalReviewer = try Self.value(after: argument, in: arguments, index: &index)
            case "--approval-verdict":
                approvalVerdict = try Self.approvalVerdict(after: argument, in: arguments, index: &index)
            case "--approval-note":
                approvalNote = try Self.value(after: argument, in: arguments, index: &index)
            case "--waiver-review":
                waiverReviewID = try Self.value(after: argument, in: arguments, index: &index)
            case "--waiver-proposal":
                waiverProposalID = try Self.value(after: argument, in: arguments, index: &index)
            case "--actor-kind":
                actionActorKind = try Self.actorKind(after: argument, in: arguments, index: &index)
            case "--drc-repair-hints":
                drcRepairHintPath = try Self.value(after: argument, in: arguments, index: &index)
            case "--lvs-repair-hints":
                lvsRepairHintPath = try Self.value(after: argument, in: arguments, index: &index)
            case "--formulation-id":
                planningFormulationID = try Self.value(after: argument, in: arguments, index: &index)
            case "--intent-id":
                planningIntentID = try Self.value(after: argument, in: arguments, index: &index)
            case "--intent":
                planningIntent = try Self.value(after: argument, in: arguments, index: &index)
            case "--problem-id":
                planningProblemID = try Self.value(after: argument, in: arguments, index: &index)
            case "--candidate-strategy":
                candidateStrategy = try Self.value(after: argument, in: arguments, index: &index)
            case "--candidate-verification-mode":
                candidateVerificationMode = try Self.value(after: argument, in: arguments, index: &index)
            case "--history-assessment-profile":
                signoffRepairHistoryAssessmentProfileURL = URL(
                    filePath: try Self.value(after: argument, in: arguments, index: &index)
                )
            case "--min-history-runs":
                signoffRepairHistoryMinimumRunCount = try Self.intValue(
                    after: argument,
                    in: arguments,
                    index: &index
                )
            case "--min-history-cycles":
                signoffRepairHistoryMinimumCycleCount = try Self.intValue(
                    after: argument,
                    in: arguments,
                    index: &index
                )
            case "--min-history-accepted":
                signoffRepairHistoryMinimumAcceptedCount = try Self.intValue(
                    after: argument,
                    in: arguments,
                    index: &index
                )
            case "--min-history-feedback-rank-changes":
                signoffRepairHistoryMinimumFeedbackRankChangeCount = try Self.intValue(
                    after: argument,
                    in: arguments,
                    index: &index
                )
            case "--min-history-feedback-score-deltas":
                signoffRepairHistoryMinimumFeedbackScoreDeltaCount = try Self.intValue(
                    after: argument,
                    in: arguments,
                    index: &index
                )
            case "--min-history-accepted-per-selected-objective-domain":
                signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain = try Self.intValue(
                    after: argument,
                    in: arguments,
                    index: &index
                )
            case "--require-history-selected-action-domain":
                signoffRepairHistoryRequiredSelectedActionDomainIDs.append(
                    try Self.value(after: argument, in: arguments, index: &index)
                )
            case "--require-history-selected-objective-domain":
                signoffRepairHistoryRequiredSelectedObjectiveDomainIDs.append(
                    try Self.value(after: argument, in: arguments, index: &index)
                )
            case "--pex-corner":
                pexCornerID = try Self.value(after: argument, in: arguments, index: &index)
            case "--signoff-drc-log":
                signoffDRCLogURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--signoff-lvs-log":
                signoffLVSLogURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--max-abs-delta":
                maxAbsoluteDelta = try Self.doubleValue(after: argument, in: arguments, index: &index)
            case "--max-rel-delta":
                maxRelativeDelta = try Self.doubleValue(after: argument, in: arguments, index: &index)
            case "--relative-delta-floor":
                relativeDeltaDenominatorFloor = try Self.doubleValue(after: argument, in: arguments, index: &index)
            case "--domain-limit":
                domainComparisonLimits.append(
                    try Self.domainLimit(after: argument, in: arguments, index: &index)
                )
            case "--variable-limit":
                variableComparisonLimits.append(
                    try Self.variableLimit(after: argument, in: arguments, index: &index)
                )
            case "--oscillation-limit":
                oscillationMetricLimits.append(
                    try Self.oscillationLimit(after: argument, in: arguments, index: &index)
                )
            case "--approve-signoff":
                approveSignoff = true
            case "--json":
                outputFormat = .json
            case "--help", "-h":
                showHelp = true
            default:
                throw ParseError.invalidArgument(argument)
            }
            index += 1
        }
    }

    public var usesImportedSignoff: Bool {
        signoffDRCLogURL != nil || signoffLVSLogURL != nil
    }

    public var usesComparisonLimits: Bool {
        maxAbsoluteDelta != nil
            || maxRelativeDelta != nil
            || relativeDeltaDenominatorFloor != nil
            || !domainComparisonLimits.isEmpty
            || !variableComparisonLimits.isEmpty
            || !oscillationMetricLimits.isEmpty
    }

    public var commandKind: DesignFlowCommand.Kind {
        mode.commandKind(usesDesignSpec: designSpecURL != nil)
    }

    public var projectRootPath: String? {
        switch mode {
        case .listFixtures, .generateNetlist, .simulate, .loadTechnologyPackage, .runPEXExtraction,
             .inspectTimingModelProfiles, .scaffoldDesignSpec:
            return nil
        case .buildTimingLibrary:
            return (outputURL ?? defaultTimingOutputURL).path(percentEncoded: false)
        case .applyDesignEdit, .applyLayoutEdit, .runLayoutTrust, .runVerification, .approveGate, .reviewRoundTrip,
             .selectFailureSuggestedAction, .applyWaiverEditProposal, .runPostWaiverEditVerification,
             .applyWaiverEditProposalAndRunPostVerification, .runSelectedSuggestedAction,
             .formulateSignoffRepairPlanningProblem, .runSignoffRepairCandidateCycle, .runGoalLayoutAgent:
            return outputURL?.path(percentEncoded: false)
        case .runRoundTrip, .summarizeBottlenecks, .summarizeSignoffRepairCandidateCycles,
             .assessSignoffRepairCandidateCycles:
            return (outputURL ?? defaultOutputURL).path(percentEncoded: false)
        }
    }

    public func makeCommand() -> DesignFlowCommand {
        DesignFlowCommand(
            kind: commandKind,
            fixtureName: fixtureName,
            designSpecPath: designSpecURL?.path(percentEncoded: false),
            projectRootPath: projectRootPath,
            runID: runID,
            approveSignoff: approveSignoff,
            pexManifestPath: pexManifestURL?.path(percentEncoded: false),
            pexCornerID: pexCornerID,
            signoffDRCLogPath: signoffDRCLogURL?.path(percentEncoded: false),
            signoffLVSLogPath: signoffLVSLogURL?.path(percentEncoded: false),
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            relativeDeltaDenominatorFloor: relativeDeltaDenominatorFloor,
            domainComparisonLimits: domainComparisonLimits,
            variableComparisonLimits: variableComparisonLimits,
            oscillationMetricLimits: oscillationMetricLimits,
            technologyPackagePath: technologyPackageURL?.path(percentEncoded: false),
            pexConfigPath: pexConfigURL?.path(percentEncoded: false),
            pexExecutablePath: pexExecutableURL?.path(percentEncoded: false),
            timingModelProfilePath: timingModelProfileURL?.path(percentEncoded: false),
            timingModelProfileCatalogPath: timingModelProfileCatalogURL?.path(percentEncoded: false),
            timingModelProfileID: timingModelProfileID,
            timingModelCornerID: timingModelCornerID,
            editScriptPath: editScriptURL?.path(percentEncoded: false),
            outputDesignSpecPath: outputDesignSpecURL?.path(percentEncoded: false),
            layoutDocumentPath: layoutDocumentURL?.path(percentEncoded: false),
            outputLayoutDocumentPath: outputLayoutDocumentURL?.path(percentEncoded: false),
            designUnitPath: designUnitURL?.path(percentEncoded: false),
            roundTripManifestPath: reviewManifestURL?.path(percentEncoded: false),
            failureEnvelopePath: failureEnvelopeURL?.path(percentEncoded: false),
            suggestedActionID: suggestedActionID,
            approvalStageID: approvalStageID,
            approvalReviewer: approvalReviewer,
            approvalVerdict: approvalVerdict,
            approvalNote: approvalNote,
            waiverReviewID: waiverReviewID,
            waiverProposalID: waiverProposalID,
            actionActorKind: actionActorKind,
            drcRepairHintPath: drcRepairHintPath,
            lvsRepairHintPath: lvsRepairHintPath,
            planningFormulationID: planningFormulationID,
            planningIntentID: planningIntentID,
            planningIntent: planningIntent,
            planningProblemID: planningProblemID,
            candidateStrategy: candidateStrategy,
            candidateVerificationMode: candidateVerificationMode,
            signoffRepairHistoryAssessmentProfilePath:
                signoffRepairHistoryAssessmentProfileURL?.path(percentEncoded: false),
            signoffRepairHistoryMinimumRunCount: signoffRepairHistoryMinimumRunCount,
            signoffRepairHistoryMinimumCycleCount: signoffRepairHistoryMinimumCycleCount,
            signoffRepairHistoryMinimumAcceptedCount: signoffRepairHistoryMinimumAcceptedCount,
            signoffRepairHistoryMinimumFeedbackRankChangeCount:
                signoffRepairHistoryMinimumFeedbackRankChangeCount,
            signoffRepairHistoryMinimumFeedbackScoreDeltaCount:
                signoffRepairHistoryMinimumFeedbackScoreDeltaCount,
            signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain:
                signoffRepairHistoryMinimumAcceptedCountPerSelectedObjectiveDomain,
            signoffRepairHistoryRequiredSelectedActionDomainIDs:
                signoffRepairHistoryRequiredSelectedActionDomainIDs.isEmpty
                    ? nil
                    : signoffRepairHistoryRequiredSelectedActionDomainIDs,
            signoffRepairHistoryRequiredSelectedObjectiveDomainIDs:
                signoffRepairHistoryRequiredSelectedObjectiveDomainIDs.isEmpty
                    ? nil
                    : signoffRepairHistoryRequiredSelectedObjectiveDomainIDs,
            intentSubcktPath: intentSubcktURL?.path(percentEncoded: false),
            designName: designName
        )
    }

    private var defaultOutputURL: URL {
        let directoryName = designSpecURL?
            .deletingPathExtension()
            .lastPathComponent ?? fixtureName
        return URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: "round-trip-runs")
            .appending(path: directoryName)
    }

    private var defaultTimingOutputURL: URL {
        URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: "round-trip-runs")
            .appending(path: "timing-library")
    }

    private mutating func selectMode(_ mode: Mode) throws {
        if let explicitMode, explicitMode != mode {
            throw ParseError.conflictingModes
        }
        explicitMode = mode
        self.mode = mode
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw ParseError.missingValue(option)
        }
        let value = arguments[valueIndex]
        guard !isOptionToken(value) else {
            throw ParseError.missingValue(option)
        }
        index = valueIndex
        return value
    }

    private static func isOptionToken(_ value: String) -> Bool {
        value.hasPrefix("--") || value == "-h"
    }

    private static func doubleValue(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let rawValue = try value(after: option, in: arguments, index: &index)
        guard let value = Double(rawValue),
              value.isFinite,
              value >= 0 else {
            throw ParseError.invalidNumericValue(option, rawValue)
        }
        return value
    }

    private static func intValue(after option: String, in arguments: [String], index: inout Int) throws -> Int {
        let rawValue = try value(after: option, in: arguments, index: &index)
        guard let value = Int(rawValue),
              value >= 0 else {
            throw ParseError.invalidNumericValue(option, rawValue)
        }
        return value
    }

    private static func approvalStageID(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> String {
        let rawValue = try value(after: option, in: arguments, index: &index)
        let stageID = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stageID.isEmpty else {
            throw ParseError.invalidApprovalStageID(rawValue)
        }
        return stageID
    }

    private static func approvalVerdict(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> FlowApprovalRecord.Verdict {
        let rawValue = try value(after: option, in: arguments, index: &index)
        guard let decision = FlowApprovalRecord.Verdict(rawValue: rawValue) else {
            throw ParseError.invalidApprovalVerdict(rawValue)
        }
        return decision
    }

    private static func actorKind(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> FlowRunActor.Kind {
        let rawValue = try value(after: option, in: arguments, index: &index)
        guard let actorKind = FlowRunActor.Kind(rawValue: rawValue) else {
            throw ParseError.invalidActorKind(rawValue)
        }
        return actorKind
    }

    private static func variableLimit(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> CircuitStudioCore.PostLayoutVariableComparisonLimit {
        let rawValue = try value(after: option, in: arguments, index: &index)
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.invalidVariableLimit(rawValue)
        }

        var maxAbsoluteDelta: Double?
        var maxRelativeDelta: Double?
        var relativeDeltaDenominatorFloor: Double?
        for assignment in parts[1].split(separator: ",").map(String.init) {
            let assignmentParts = assignment.split(separator: "=", maxSplits: 1).map(String.init)
            guard assignmentParts.count == 2 else {
                throw ParseError.invalidVariableLimit(rawValue)
            }
            let key = assignmentParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = assignmentParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(valueText), value.isFinite, value >= 0 else {
                throw ParseError.invalidVariableLimit(rawValue)
            }
            switch key {
            case "abs":
                maxAbsoluteDelta = value
            case "rel":
                maxRelativeDelta = value
            case "floor":
                relativeDeltaDenominatorFloor = value
            default:
                throw ParseError.invalidVariableLimit(rawValue)
            }
        }

        let limit = CircuitStudioCore.PostLayoutVariableComparisonLimit(
            variableName: parts[0],
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            relativeDeltaDenominatorFloor: relativeDeltaDenominatorFloor
        )
        guard limit.validationDiagnostics().isEmpty else {
            throw ParseError.invalidVariableLimit(rawValue)
        }
        return limit
    }

    private static func domainLimit(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> PostLayoutSignalDomainComparisonLimit {
        let rawValue = try value(after: option, in: arguments, index: &index)
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let domain = PostLayoutSignalDomain(rawValue: parts[0].trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ParseError.invalidDomainLimit(rawValue)
        }

        var maxAbsoluteDelta: Double?
        var maxRelativeDelta: Double?
        var relativeDeltaDenominatorFloor: Double?
        for assignment in parts[1].split(separator: ",").map(String.init) {
            let assignmentParts = assignment.split(separator: "=", maxSplits: 1).map(String.init)
            guard assignmentParts.count == 2 else {
                throw ParseError.invalidDomainLimit(rawValue)
            }
            let key = assignmentParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = assignmentParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(valueText), value.isFinite, value >= 0 else {
                throw ParseError.invalidDomainLimit(rawValue)
            }
            switch key {
            case "abs":
                maxAbsoluteDelta = value
            case "rel":
                maxRelativeDelta = value
            case "floor":
                relativeDeltaDenominatorFloor = value
            default:
                throw ParseError.invalidDomainLimit(rawValue)
            }
        }

        let limit = PostLayoutSignalDomainComparisonLimit(
            domain: domain,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            relativeDeltaDenominatorFloor: relativeDeltaDenominatorFloor
        )
        guard limit.validationDiagnostics().isEmpty else {
            throw ParseError.invalidDomainLimit(rawValue)
        }
        return limit
    }

    private static func oscillationLimit(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> PostLayoutOscillationMetricLimit {
        let rawValue = try value(after: option, in: arguments, index: &index)
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.invalidOscillationLimit(rawValue)
        }

        var threshold: Double?
        var minTransitionCount: Int?
        var minAmplitude: Double?
        var maxFrequencyRelativeDelta: Double?
        var maxPeriodRelativeDelta: Double?
        var maxDutyCycleDelta: Double?

        for assignment in parts[1].split(separator: ",").map(String.init) {
            let assignmentParts = assignment.split(separator: "=", maxSplits: 1).map(String.init)
            guard assignmentParts.count == 2 else {
                throw ParseError.invalidOscillationLimit(rawValue)
            }
            let key = assignmentParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = assignmentParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "threshold":
                threshold = try finiteDouble(valueText, rawValue: rawValue)
            case "minTransitions":
                guard let value = Int(valueText), value >= 0 else {
                    throw ParseError.invalidOscillationLimit(rawValue)
                }
                minTransitionCount = value
            case "minAmplitude":
                minAmplitude = try nonNegativeDouble(valueText, rawValue: rawValue)
            case "freqRel":
                maxFrequencyRelativeDelta = try nonNegativeDouble(valueText, rawValue: rawValue)
            case "periodRel":
                maxPeriodRelativeDelta = try nonNegativeDouble(valueText, rawValue: rawValue)
            case "duty":
                maxDutyCycleDelta = try nonNegativeDouble(valueText, rawValue: rawValue)
            default:
                throw ParseError.invalidOscillationLimit(rawValue)
            }
        }

        let limit = PostLayoutOscillationMetricLimit(
            variableName: parts[0],
            threshold: threshold,
            minTransitionCount: minTransitionCount,
            minAmplitude: minAmplitude,
            maxFrequencyRelativeDelta: maxFrequencyRelativeDelta,
            maxPeriodRelativeDelta: maxPeriodRelativeDelta,
            maxDutyCycleDelta: maxDutyCycleDelta
        )
        guard limit.validationDiagnostics().isEmpty else {
            throw ParseError.invalidOscillationLimit(rawValue)
        }
        return limit
    }

    private static func finiteDouble(_ text: String, rawValue: String) throws -> Double {
        guard let value = Double(text), value.isFinite else {
            throw ParseError.invalidOscillationLimit(rawValue)
        }
        return value
    }

    private static func nonNegativeDouble(_ text: String, rawValue: String) throws -> Double {
        let value = try finiteDouble(text, rawValue: rawValue)
        guard value >= 0 else {
            throw ParseError.invalidOscillationLimit(rawValue)
        }
        return value
    }
}
