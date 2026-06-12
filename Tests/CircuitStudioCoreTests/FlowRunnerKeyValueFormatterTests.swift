import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("FlowRunnerKeyValueFormatter Tests")
struct FlowRunnerKeyValueFormatterTests {

    private func reviewSummary(
        approvalKind: ExternalSignoffReview.ApprovalKind?,
        approvedBy: String?
    ) -> RoundTripReviewSummary {
        RoundTripReviewSummary(
            runID: "run-1",
            title: "t",
            createdAt: Date(timeIntervalSince1970: 0),
            manifestPath: "/tmp/manifest.json",
            status: .passed,
            isRoundTripComplete: true,
            isReadyForPEX: true,
            stages: [],
            artifacts: [],
            externalSignoff: RoundTripReviewSignoffSummary(
                passed: true,
                approved: approvedBy != nil,
                readyForPEX: true,
                approvedBy: approvedBy,
                approvedAt: approvedBy != nil ? Date(timeIntervalSince1970: 1) : nil,
                approvalKind: approvalKind,
                waiverIDs: [],
                reports: []
            ),
            postLayoutComparison: nil,
            bottleneckSummary: nil,
            diagnostics: [],
            recommendations: []
        )
    }

    @Test("Round-trip review output carries the approval provenance")
    func reviewOutputCarriesApprovalProvenance() {
        let result = DesignFlowCommandResult(
            kind: .reviewRoundTrip,
            roundTripReview: reviewSummary(approvalKind: .automated, approvedBy: "design-flow-command")
        )

        let lines = FlowRunnerKeyValueFormatter.lines(for: result)

        #expect(lines.contains("signoff_approval_kind=automated"))
        #expect(lines.contains("signoff_approved_by=design-flow-command"))
    }

    @Test("Human approval provenance is distinguishable in review output")
    func humanApprovalProvenanceIsDistinguishable() {
        let result = DesignFlowCommandResult(
            kind: .reviewRoundTrip,
            roundTripReview: reviewSummary(approvalKind: .human, approvedBy: "layout-reviewer")
        )

        let lines = FlowRunnerKeyValueFormatter.lines(for: result)

        #expect(lines.contains("signoff_approval_kind=human"))
        #expect(lines.contains("signoff_approved_by=layout-reviewer"))
    }

    @Test("Unapproved review output reports empty provenance, not a default")
    func unapprovedReviewReportsEmptyProvenance() {
        let result = DesignFlowCommandResult(
            kind: .reviewRoundTrip,
            roundTripReview: reviewSummary(approvalKind: nil, approvedBy: nil)
        )

        let lines = FlowRunnerKeyValueFormatter.lines(for: result)

        #expect(lines.contains("signoff_approved=false"))
        #expect(lines.contains("signoff_approval_kind="))
        #expect(lines.contains("signoff_approved_by="))
    }

    @Test("Round-trip output marks flag-driven approval as automated")
    func roundTripFlagApprovalIsAutomated() {
        let result = DesignFlowCommandResult(kind: .runFixtureRoundTrip, fixtureName: "fixture")
        let context = FlowRunnerOutputContext(usesImportedSignoff: true, approveSignoff: true)

        let lines = FlowRunnerKeyValueFormatter.lines(for: result, context: context)

        #expect(lines.contains("signoff_approved=true"))
        #expect(lines.contains("signoff_approval_kind=automated"))
    }

    @Test("Round-trip output without the approval flag reports no approval kind")
    func roundTripWithoutFlagReportsNoApprovalKind() {
        let result = DesignFlowCommandResult(kind: .runFixtureRoundTrip, fixtureName: "fixture")
        let context = FlowRunnerOutputContext(usesImportedSignoff: true, approveSignoff: false)

        let lines = FlowRunnerKeyValueFormatter.lines(for: result, context: context)

        #expect(lines.contains("signoff_approved=false"))
        #expect(lines.contains("signoff_approval_kind="))
    }
}
