import Foundation
import LayoutCore

public protocol LayoutTrustArtifactWriting: Sendable {
    func write(
        document: LayoutDocument,
        report: LayoutTrustReport,
        to directory: URL
    ) throws -> LayoutTrustArtifactWriter.WriteResult
}

extension LayoutTrustArtifactWriter: LayoutTrustArtifactWriting {}
