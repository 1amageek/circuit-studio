enum RunReviewArtifactPreviewKey {
    static func make(runID: String, artifactPath: String) -> String {
        "\(runID)#\(artifactPath)"
    }
}
