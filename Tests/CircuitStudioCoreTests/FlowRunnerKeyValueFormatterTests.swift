import CircuitSignoff
import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("FlowRunnerKeyValueFormatter Tests")
struct FlowRunnerKeyValueFormatterTests {

    private func reviewSummary(
        approvalKind: ExternalSignoffReview.ApprovalKind?,
        approvedBy: String?,
        recommendations: [String] = []
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
            recommendations: recommendations
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

    @Test("Key-value output escapes unsafe scalar values")
    func keyValueOutputEscapesUnsafeScalarValues() {
        let result = DesignFlowCommandResult(
            kind: .reviewRoundTrip,
            roundTripReview: reviewSummary(
                approvalKind: .human,
                approvedBy: "layout-reviewer",
                recommendations: ["inspect DRC result\nrun_id=forged"]
            )
        )

        let lines = FlowRunnerKeyValueFormatter.lines(for: result)
        let physicalLines = lines.joined(separator: "\n").split(separator: "\n").map(String.init)

        #expect(lines.contains("recommendation=inspect DRC result\\nrun_id=forged"))
        #expect(!physicalLines.contains("run_id=forged"))
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

    @Test("Timing library output carries artifact and profile paths")
    func timingLibraryOutputCarriesArtifactAndProfilePaths() {
        let result = DesignFlowCommandResult(
            kind: .buildTimingLibrary,
            runID: "timing-run-1",
            projectRootPath: "/tmp/flow-output",
            timingArtifactManifestPath: "/tmp/flow-output/.xcircuite/runs/timing-run-1/timing/manifest.json",
            timingLibraryPath: "/tmp/flow-output/.xcircuite/runs/timing-run-1/timing/timing-library.json",
            timingModelProfileSelectionPath: "/tmp/flow-output/.xcircuite/runs/timing-run-1/timing/model-profile-selection.json",
            timingModelProfileID: "profile-1",
            timingModelProfilePath: "/tmp/timing-profile.json",
            timingModelProfileCatalogID: "catalog-1",
            timingModelProfileCatalogPath: "/tmp/timing-profile-catalog.json",
            timingModelCornerID: "tt"
        )

        let lines = FlowRunnerKeyValueFormatter.lines(for: result)

        #expect(lines.contains("timing_library=generated"))
        #expect(lines.contains("timing_manifest=/tmp/flow-output/.xcircuite/runs/timing-run-1/timing/manifest.json"))
        #expect(lines.contains("timing_library_artifact=/tmp/flow-output/.xcircuite/runs/timing-run-1/timing/timing-library.json"))
        #expect(lines.contains("timing_model_profile_selection=/tmp/flow-output/.xcircuite/runs/timing-run-1/timing/model-profile-selection.json"))
        #expect(lines.contains("timing_model_profile_id=profile-1"))
        #expect(lines.contains("timing_model_profile_path=/tmp/timing-profile.json"))
        #expect(lines.contains("timing_model_profile_catalog_id=catalog-1"))
        #expect(lines.contains("timing_model_profile_catalog_path=/tmp/timing-profile-catalog.json"))
        #expect(lines.contains("timing_model_corner_id=tt"))
    }

    @Test("Timing profile catalog inspection output carries readiness summary")
    func timingProfileCatalogInspectionOutputCarriesReadinessSummary() {
        let inspection = TimingModelProfileCatalogInspection(
            catalogID: "catalog-1",
            catalogPath: "/tmp/timing-profile-catalog.json",
            profiles: [
                TimingModelProfileCatalogInspection.Profile(
                    profileID: "profile-1",
                    displayName: "Profile 1",
                    sourceKind: .externalFile,
                    declaredCornerID: "tt",
                    profileResourceName: nil,
                    profilePath: "/tmp/profile-1.json",
                    defaultProfile: true,
                    status: .passed,
                    schemaVersion: 1,
                    processName: "unit-process",
                    cornerID: "tt",
                    deviceModelID: "unit-model",
                    supplyVoltage: 1.8,
                    deviceModelHash: String(repeating: "a", count: 64),
                    sha256: String(repeating: "b", count: 64),
                    diagnostics: []
                ),
            ]
        )
        let result = DesignFlowCommandResult(
            kind: .inspectTimingModelProfiles,
            timingModelProfileID: "profile-1",
            timingModelProfileCatalogID: "catalog-1",
            timingModelProfileCatalogPath: "/tmp/timing-profile-catalog.json",
            timingModelProfileCatalogInspection: inspection,
            timingModelCornerID: "tt"
        )

        let lines = FlowRunnerKeyValueFormatter.lines(for: result)

        #expect(lines.contains("timing_model_profile_catalog=inspected"))
        #expect(lines.contains("timing_model_profile_catalog_status=passed"))
        #expect(lines.contains("timing_model_profile_catalog_id=catalog-1"))
        #expect(lines.contains("timing_model_profile_catalog_path=/tmp/timing-profile-catalog.json"))
        #expect(lines.contains("timing_model_profile_selected_id=profile-1"))
        #expect(lines.contains("timing_model_corner_id=tt"))
        #expect(lines.contains("timing_model_profile_default_id=profile-1"))
        #expect(lines.contains("timing_model_profile_count=1"))
        #expect(lines.contains("timing_model_profile_passed_count=1"))
        #expect(lines.contains("timing_model_profile_failed_count=0"))
        #expect(lines.contains("timing_model_profile_ids=profile-1"))
    }
}
