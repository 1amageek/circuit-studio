import Foundation
import CircuitStudioCore

public struct FlowRunnerCommandOptions: Sendable {
    public enum Mode: Sendable, Equatable {
        case listFixtures
        case generateNetlist
        case simulate
        case runRoundTrip
        case summarizeBottlenecks
        case loadTechnologyPackage
        case runPEXExtraction
        case applyDesignEdit
        case applyLayoutEdit
        case runLayoutTrust
        case runVerification
        case approveGate
        case reviewRoundTrip

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
            case .loadTechnologyPackage:
                return .loadTechnologyPackage
            case .runPEXExtraction:
                return .runPEXExtraction
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
        case invalidGateID(String)
        case invalidApprovalDecision(String)
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
            case .invalidGateID(let value):
                return "Invalid approval gate ID: \(value)"
            case .invalidApprovalDecision(let value):
                return "Invalid approval decision: \(value)"
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
    public var editScriptURL: URL?
    public var outputDesignSpecURL: URL?
    public var layoutDocumentURL: URL?
    public var outputLayoutDocumentURL: URL?
    public var designUnitURL: URL?
    public var reviewManifestURL: URL?
    public var approvalGateID: FlowGateID?
    public var approvalTargetURL: URL?
    public var approvalReviewer: String?
    public var approvalDecision: GateApprovalDecision?
    public var approvalPolicy: String?
    public var approvalNote: String?
    public var waiverIDs: [String] = []
    public var pexCornerID = "tt_25c_1v0"
    public var signoffDRCLogURL: URL?
    public var signoffLVSLogURL: URL?
    public var maxAbsoluteDelta: Double?
    public var maxRelativeDelta: Double?
    public var relativeDeltaDenominatorFloor: Double?
    public var domainComparisonLimits: [PostLayoutSignalDomainComparisonLimit] = []
    public var variableComparisonLimits: [PostLayoutVariableComparisonLimit] = []
    public var oscillationMetricLimits: [PostLayoutOscillationMetricLimit] = []
    public var technologyPackageURL: URL?
    public var approveSignoff = false
    public var showHelp = false

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
            case "--load-technology-package":
                try selectMode(.loadTechnologyPackage)
            case "--run-pex-extraction":
                try selectMode(.runPEXExtraction)
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
            case "--approval-gate":
                approvalGateID = try Self.gateID(after: argument, in: arguments, index: &index)
            case "--approval-target":
                approvalTargetURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--reviewer":
                approvalReviewer = try Self.value(after: argument, in: arguments, index: &index)
            case "--approval-decision":
                approvalDecision = try Self.approvalDecision(after: argument, in: arguments, index: &index)
            case "--approval-policy":
                approvalPolicy = try Self.value(after: argument, in: arguments, index: &index)
            case "--approval-note":
                approvalNote = try Self.value(after: argument, in: arguments, index: &index)
            case "--waiver":
                waiverIDs.append(try Self.value(after: argument, in: arguments, index: &index))
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
        case .listFixtures, .generateNetlist, .simulate, .loadTechnologyPackage, .runPEXExtraction:
            return nil
        case .applyDesignEdit, .applyLayoutEdit, .runLayoutTrust, .runVerification, .approveGate, .reviewRoundTrip:
            return outputURL?.path(percentEncoded: false)
        case .runRoundTrip, .summarizeBottlenecks:
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
            editScriptPath: editScriptURL?.path(percentEncoded: false),
            outputDesignSpecPath: outputDesignSpecURL?.path(percentEncoded: false),
            layoutDocumentPath: layoutDocumentURL?.path(percentEncoded: false),
            outputLayoutDocumentPath: outputLayoutDocumentURL?.path(percentEncoded: false),
            designUnitPath: designUnitURL?.path(percentEncoded: false),
            roundTripManifestPath: reviewManifestURL?.path(percentEncoded: false),
            approvalGateID: approvalGateID,
            approvalTargetPath: approvalTargetURL?.path(percentEncoded: false),
            approvalReviewer: approvalReviewer,
            approvalDecision: approvalDecision,
            approvalPolicy: approvalPolicy,
            approvalNote: approvalNote,
            waiverIDs: waiverIDs
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
        index = valueIndex
        return arguments[valueIndex]
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

    private static func gateID(after option: String, in arguments: [String], index: inout Int) throws -> FlowGateID {
        let rawValue = try value(after: option, in: arguments, index: &index)
        guard let gateID = FlowGateID(rawValue: rawValue) else {
            throw ParseError.invalidGateID(rawValue)
        }
        return gateID
    }

    private static func approvalDecision(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> GateApprovalDecision {
        let rawValue = try value(after: option, in: arguments, index: &index)
        guard let decision = GateApprovalDecision(rawValue: rawValue) else {
            throw ParseError.invalidApprovalDecision(rawValue)
        }
        return decision
    }

    private static func variableLimit(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> PostLayoutVariableComparisonLimit {
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

        let limit = PostLayoutVariableComparisonLimit(
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
