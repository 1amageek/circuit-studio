import DesignFlowKernel

enum RunReviewArtifactPreviewKey {
    static func make(runID: String, artifact: FlowRunReviewArtifact) -> String {
        [
            runID,
            artifact.stageID ?? "",
            artifact.purpose.rawValue,
            artifact.binding.logicalID,
            artifact.binding.kind.rawValue,
            artifact.binding.format.rawValue,
            artifact.binding.circuitStudioPresentationPath,
        ].map(escape).joined(separator: "#")
    }

    static func make(runID: String, artifactPath: String) -> String {
        "\(runID)#\(artifactPath)"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "#", with: "%23")
    }
}
