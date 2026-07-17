import DesignFlowKernel

public struct RunReviewToolchainProjection: Sendable, Hashable {
    public let summary: FlowRunToolchainSummary?
    public let artifacts: [FlowRunReviewArtifact]

    public init(bundle: FlowRunReviewBundle) {
        summary = bundle.summary.toolchain
        artifacts = bundle.artifacts.filter {
            $0.purpose == .toolchain || $0.purpose == .toolchainProfile
        }
    }

    public var hasContent: Bool {
        summary != nil || !artifacts.isEmpty
    }

    public var selectedToolIDs: [String] {
        summary?.selectedToolIDs ?? []
    }

    public var rejectedEvaluationCount: Int {
        summary?.rejectedEvaluationCount ?? 0
    }

    public var missingSelectionStageIDs: [String] {
        summary?.missingSelectionStageIDs ?? []
    }

    public var hasUnverifiedArtifacts: Bool {
        artifacts.contains { $0.integrity?.status != .verified }
    }
}
