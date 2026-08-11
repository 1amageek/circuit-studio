import Foundation
import CircuitPhysicalDesign

public struct DesignFlowVerificationReport: Sendable, Hashable, Codable {
    public let status: String
    public let readyForPEX: Bool
    public let layoutTrust: LayoutTrustReport?
    public let drc: DesignFlowDRCVerificationSummary
    public let lvs: DesignFlowLVSVerificationSummary
    public let externalSignoff: RoundTripReviewSignoffSummary?

    public init(
        report: PhysicalVerificationReport,
        layoutTrust: LayoutTrustReport?
    ) {
        self.readyForPEX = report.isReadyForPEX && layoutTrust?.passed == true
        self.status = self.readyForPEX ? "passed" : "failed"
        self.layoutTrust = layoutTrust
        self.drc = DesignFlowDRCVerificationSummary(report: report.drc)
        self.lvs = DesignFlowLVSVerificationSummary(report: report.lvs)
        self.externalSignoff = report.externalSignoff.map {
            RoundTripReviewSignoffSummary(
                passed: $0.passed,
                approved: $0.isApproved,
                readyForPEX: $0.isReadyForPEX,
                approvedBy: $0.approvedBy,
                approvedAt: $0.approvedAt,
                approvalKind: $0.approvalKind,
                waiverIDs: $0.waiverIDs,
                reports: $0.reports.map { toolReport in
                    RoundTripReviewSignoffReportSummary(
                        kind: toolReport.kind,
                        toolName: toolReport.toolName,
                        passed: toolReport.passed,
                        logPath: toolReport.logPath,
                        diagnosticCount: toolReport.diagnostics.count,
                        errorCount: toolReport.diagnostics.filter { $0.severity == .error }.count,
                        warningCount: toolReport.diagnostics.filter { $0.severity == .warning }.count
                    )
                }
            )
        }
    }
}

public struct DesignFlowDRCVerificationSummary: Sendable, Hashable, Codable {
    public let passed: Bool
    public let violationCount: Int
    public let violationsByKind: [String: Int]

    public init(report: DRCVerificationReport) {
        self.passed = report.passed
        self.violationCount = report.violationCount
        self.violationsByKind = report.violationsByKind
    }
}

public struct DesignFlowLVSVerificationSummary: Sendable, Hashable, Codable {
    public let passed: Bool
    public let schematicHashMatches: Bool
    public let missingLayoutInstances: [String]
    public let extraLayoutInstances: [String]
    public let missingLayoutNets: [String]
    public let extraLayoutNets: [String]
    public let danglingMappedInstanceIDs: [UUID]
    public let danglingMappedNetIDs: [UUID]
    public let physicalShorts: [DesignFlowLVSPhysicalShortSummary]
    public let physicalOpens: [DesignFlowLVSPhysicalOpenSummary]
    public let unconnectedLayoutPins: [DesignFlowLVSTerminalSummary]
    public let terminalMismatches: [DesignFlowLVSTerminalMismatchSummary]
    public let missingExternalLayoutPorts: [String]
    public let invalidLayoutTerminals: [DesignFlowLVSTerminalSummary]
    public let duplicateLayoutTerminals: [DesignFlowLVSTerminalSummary]
    public let deviceParameterMismatches: [DesignFlowLVSDeviceParameterMismatchSummary]
    public let duplicateLayoutDevices: [String]
    public let layoutTopologyErrors: [String]
    public let connectivityExtractionSkipped: Bool
    public let skippedComponents: [String]

    public init(report: LVSVerificationReport) {
        self.passed = report.passed
        self.schematicHashMatches = report.schematicHashMatches
        self.missingLayoutInstances = report.missingLayoutInstances
        self.extraLayoutInstances = report.extraLayoutInstances
        self.missingLayoutNets = report.missingLayoutNets
        self.extraLayoutNets = report.extraLayoutNets
        self.danglingMappedInstanceIDs = report.danglingMappedInstanceIDs
        self.danglingMappedNetIDs = report.danglingMappedNetIDs
        self.physicalShorts = report.physicalShorts.map(DesignFlowLVSPhysicalShortSummary.init)
        self.physicalOpens = report.physicalOpens.map(DesignFlowLVSPhysicalOpenSummary.init)
        self.unconnectedLayoutPins = report.unconnectedLayoutPins.map(DesignFlowLVSTerminalSummary.init)
        self.terminalMismatches = report.terminalMismatches.map(DesignFlowLVSTerminalMismatchSummary.init)
        self.missingExternalLayoutPorts = report.missingExternalLayoutPorts
        self.invalidLayoutTerminals = report.invalidLayoutTerminals.map(DesignFlowLVSTerminalSummary.init)
        self.duplicateLayoutTerminals = report.duplicateLayoutTerminals.map(DesignFlowLVSTerminalSummary.init)
        self.deviceParameterMismatches = report.deviceParameterMismatches.map(
            DesignFlowLVSDeviceParameterMismatchSummary.init
        )
        self.duplicateLayoutDevices = report.duplicateLayoutDevices
        self.layoutTopologyErrors = report.layoutTopologyErrors
        self.connectivityExtractionSkipped = report.connectivityExtractionSkipped
        self.skippedComponents = report.skippedComponents
    }
}

public struct DesignFlowLVSTerminalSummary: Sendable, Hashable, Codable {
    public let componentName: String
    public let pinName: String

    public init(terminal: LVSVerificationReport.Terminal) {
        self.componentName = terminal.componentName
        self.pinName = terminal.pinName
    }
}

public struct DesignFlowLVSPhysicalShortSummary: Sendable, Hashable, Codable {
    public let netNames: [String]
    public let terminals: [DesignFlowLVSTerminalSummary]

    public init(short: LVSVerificationReport.PhysicalShort) {
        self.netNames = short.netNames
        self.terminals = short.terminals.map(DesignFlowLVSTerminalSummary.init)
    }
}

public struct DesignFlowLVSPhysicalOpenSummary: Sendable, Hashable, Codable {
    public let netName: String
    public let terminals: [DesignFlowLVSTerminalSummary]
    public let physicalNetCount: Int

    public init(open: LVSVerificationReport.PhysicalOpen) {
        self.netName = open.netName
        self.terminals = open.terminals.map(DesignFlowLVSTerminalSummary.init)
        self.physicalNetCount = open.physicalNetCount
    }
}

public struct DesignFlowLVSTerminalMismatchSummary: Sendable, Hashable, Codable {
    public let terminal: DesignFlowLVSTerminalSummary
    public let expectedNetName: String
    public let actualNetNames: [String]

    public init(mismatch: LVSVerificationReport.TerminalMismatch) {
        self.terminal = DesignFlowLVSTerminalSummary(terminal: mismatch.terminal)
        self.expectedNetName = mismatch.expectedNetName
        self.actualNetNames = mismatch.actualNetNames
    }
}

public struct DesignFlowLVSDeviceParameterMismatchSummary: Sendable, Hashable, Codable {
    public let componentName: String
    public let parameterName: String
    public let expectedValue: Double
    public let actualValue: Double
    public let tolerance: Double

    public init(mismatch: LVSVerificationReport.DeviceParameterMismatch) {
        self.componentName = mismatch.componentName
        self.parameterName = mismatch.parameterName
        self.expectedValue = mismatch.expectedValue
        self.actualValue = mismatch.actualValue
        self.tolerance = mismatch.tolerance
    }
}
