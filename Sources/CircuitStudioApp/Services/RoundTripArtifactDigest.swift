import CryptoKit
import Foundation

public struct RoundTripArtifactDigest: Sendable, Hashable, Codable {
    public let sha256: String
    public let byteCount: Int64

    public init(sha256: String, byteCount: Int64) {
        self.sha256 = sha256
        self.byteCount = byteCount
    }

    public static func compute(url: URL) throws -> RoundTripArtifactDigest {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return RoundTripArtifactDigest(
            sha256: digest.map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(data.count)
        )
    }
}
