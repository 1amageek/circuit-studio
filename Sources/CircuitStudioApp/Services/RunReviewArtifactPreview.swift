import DesignFlowKernel
import Foundation

public struct RunReviewArtifactPreview: Sendable, Hashable {
    public let artifact: FlowRunReviewArtifact
    public let resolvedPath: String
    public let byteCount: Int64?
    public let previewByteCount: Int
    public let truncated: Bool
    public let isText: Bool
    public let text: String
    public let lineCount: Int
    public let structuredPreview: String?
    public let parseIssue: String?
    public let waveformPreview: RunReviewWaveformPreview?

    public init(
        artifact: FlowRunReviewArtifact,
        resolvedPath: String,
        byteCount: Int64?,
        previewByteCount: Int,
        truncated: Bool,
        isText: Bool,
        text: String,
        lineCount: Int,
        structuredPreview: String? = nil,
        parseIssue: String? = nil,
        waveformPreview: RunReviewWaveformPreview? = nil
    ) {
        self.artifact = artifact
        self.resolvedPath = resolvedPath
        self.byteCount = byteCount
        self.previewByteCount = previewByteCount
        self.truncated = truncated
        self.isText = isText
        self.text = text
        self.lineCount = lineCount
        self.structuredPreview = structuredPreview
        self.parseIssue = parseIssue
        self.waveformPreview = waveformPreview
    }
}
