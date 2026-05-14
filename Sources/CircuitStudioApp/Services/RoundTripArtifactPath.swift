import Foundation

public struct RoundTripArtifactPath: Sendable, Hashable, Codable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty else {
            throw RoundTripArtifactResolverError.invalidRelativePath(value, "Artifact path is empty.")
        }
        guard value != "." else {
            throw RoundTripArtifactResolverError.invalidRelativePath(value, "Artifact path points at the run directory.")
        }
        guard !Self.isAbsolutePath(value) else {
            throw RoundTripArtifactResolverError.invalidRelativePath(value, "Artifact path is absolute.")
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.contains("..") else {
            throw RoundTripArtifactResolverError.invalidRelativePath(value, "Artifact path escapes the run directory.")
        }
        guard !components.contains(".") else {
            throw RoundTripArtifactResolverError.invalidRelativePath(value, "Artifact path contains a current-directory component.")
        }
        guard !components.contains(where: { $0.isEmpty }) else {
            throw RoundTripArtifactResolverError.invalidRelativePath(value, "Artifact path contains an empty component.")
        }
        self.value = value
    }

    public static func isAbsolutePath(_ value: String) -> Bool {
        (value as NSString).isAbsolutePath
    }
}
