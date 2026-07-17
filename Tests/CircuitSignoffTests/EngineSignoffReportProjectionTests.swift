import CircuitSignoff
import DRCCore
import LVSCore
import Testing

@Suite("Engine signoff report projection")
struct EngineSignoffReportProjectionTests {
    @Test("DRC engine verdict and diagnostics are preserved")
    func drcProjection() {
        let result = DRCResult(
            backendID: "magic",
            toolName: "magic",
            success: true,
            completed: true,
            logPath: "/artifacts/drc.log",
            diagnostics: [
                DRCDiagnostic(
                    severity: .error,
                    message: "Spacing violation",
                    ruleID: "met1.2",
                    relatedNetIDs: ["data"],
                    rawLine: "VIOLATION rule=met1.2"
                ),
            ]
        )

        let report = ExternalSignoffToolReport(drcResult: result)

        #expect(report.kind == .drc)
        #expect(!report.passed)
        #expect(report.diagnostics.first?.ruleID == "met1.2")
        #expect(report.diagnostics.first?.netName == "data")
    }

    @Test("LVS mismatch cannot be projected as a passing report")
    func lvsProjection() {
        let result = LVSResult(
            backendID: "netgen",
            toolName: "netgen",
            executionStatus: .completed,
            verdict: .mismatch,
            readiness: .ready,
            logPath: "/artifacts/lvs.log"
        )

        let report = ExternalSignoffToolReport(lvsResult: result)

        #expect(report.kind == .lvs)
        #expect(report.completed)
        #expect(!report.success)
        #expect(!report.passed)
    }
}
