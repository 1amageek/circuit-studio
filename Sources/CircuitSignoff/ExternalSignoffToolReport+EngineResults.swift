import DRCCore
import LVSCore

extension ExternalSignoffToolReport {
    public init(drcResult result: DRCResult) {
        self.init(
            kind: .drc,
            toolName: result.toolName,
            success: result.success,
            completed: result.completed,
            parserStyle: .magicDRC,
            logPath: result.logPath,
            diagnostics: result.diagnostics.map { diagnostic in
                ExternalSignoffDiagnostic(
                    severity: ExternalSignoffDiagnostic.Severity(rawValue: diagnostic.severity.rawValue) ?? .error,
                    message: diagnostic.message,
                    ruleID: diagnostic.ruleID,
                    componentName: nil,
                    netName: diagnostic.relatedNetIDs.first,
                    rawLine: diagnostic.rawLine
                )
            }
        )
    }

    public init(lvsResult result: LVSResult) {
        self.init(
            kind: .lvs,
            toolName: result.toolName,
            success: result.passed,
            completed: result.executionStatus == .completed,
            parserStyle: .netgenLVS,
            logPath: result.logPath,
            diagnostics: result.diagnostics.map { diagnostic in
                ExternalSignoffDiagnostic(
                    severity: ExternalSignoffDiagnostic.Severity(rawValue: diagnostic.severity.rawValue) ?? .error,
                    message: diagnostic.message,
                    ruleID: diagnostic.ruleID,
                    componentName: diagnostic.layoutComponentName ?? diagnostic.schematicComponentName,
                    netName: nil,
                    rawLine: diagnostic.rawLine
                )
            }
        )
    }
}
