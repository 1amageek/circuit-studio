import DesignFlowKernel

enum RunReviewArtifactPreviewKey {
    static func make(runID: String, artifact: FlowRunReviewArtifact) -> String {
        [
            runID,
            artifact.stageID ?? "",
            artifact.role,
            artifact.artifactID ?? "",
            artifact.kind.rawValue,
            artifact.format.rawValue,
            artifact.path,
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
