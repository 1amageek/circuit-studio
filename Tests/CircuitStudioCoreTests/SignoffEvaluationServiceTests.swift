import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Signoff evaluation (structured Explain)")
struct SignoffEvaluationServiceTests {

    @Test("DRC spacing + LVS mismatch become actionable findings")
    func structuresFindings() {
        let review = ExternalSignoffReview(reports: [
            ExternalSignoffToolReport(
                kind: .drc, toolName: "magic", success: true, logPath: "/tmp/drc.log",
                diagnostics: [
                    ExternalSignoffDiagnostic(
                        severity: .error,
                        message: "Metal1 spacing < 0.14um (met1.2)",
                        ruleID: "met1.2", netName: "out",
                        rawLine: "VIOLATION rule=met1.2"
                    ),
                ]
            ),
            ExternalSignoffToolReport(
                kind: .lvs, toolName: "netgen", success: true, logPath: "/tmp/lvs.log",
                diagnostics: [
                    ExternalSignoffDiagnostic(
                        severity: .error,
                        message: "Top level cell failed pin matching.",
                        ruleID: "LVS_MISMATCH",
                        rawLine: "MISMATCH rule=LVS_MISMATCH"
                    ),
                ]
            ),
        ])

        let evaluation = SignoffEvaluationService().evaluate(review)

        #expect(evaluation.passed == false)
        #expect(evaluation.findings.count == 2)
        #expect(evaluation.blockingFindings.count == 2)

        let drc = try? #require(evaluation.findings.first { $0.stage == "drc" })
        #expect(drc?.reason == "min_spacing_violation")
        #expect(drc?.ruleID == "met1.2")
        #expect(drc?.net == "out")
        #expect(drc?.suggestedActions.contains { $0.contains("met1") } == true)

        let lvs = try? #require(evaluation.findings.first { $0.stage == "lvs" })
        #expect(lvs?.reason == "layout_schematic_mismatch")
        #expect(lvs?.suggestedActions.isEmpty == false)
    }

    @Test("A clean review yields no findings and passes")
    func cleanReviewHasNoFindings() {
        let review = ExternalSignoffReview(reports: [
            ExternalSignoffToolReport(kind: .drc, toolName: "magic", success: true, logPath: "/tmp/drc.log"),
            ExternalSignoffToolReport(kind: .lvs, toolName: "netgen", success: true, logPath: "/tmp/lvs.log"),
        ])
        let evaluation = SignoffEvaluationService().evaluate(review)
        #expect(evaluation.passed)
        #expect(evaluation.findings.isEmpty)
    }
}
