import Foundation

public struct RoundTripArtifactResolution: Sendable, Hashable {
    public let url: URL
    public let warnings: [String]

    public init(url: URL, warnings: [String] = []) {
        self.url = url
        self.warnings = warnings
    }
}
