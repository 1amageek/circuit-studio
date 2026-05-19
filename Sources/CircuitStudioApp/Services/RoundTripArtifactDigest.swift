import CryptoKit
import Foundation

public enum RoundTripArtifactDigestError: Error, LocalizedError, Equatable {
    case closeFailedAfterReadFailure(path: String, readError: String, closeError: String)

    public var errorDescription: String? {
        switch self {
        case .closeFailedAfterReadFailure(let path, let readError, let closeError):
            return "Failed to close artifact after read failure at \(path): read failed with \(readError); close failed with \(closeError)"
        }
    }
}

public struct RoundTripArtifactDigest: Sendable, Hashable, Codable {
    private static let chunkSize = 1024 * 1024

    public let sha256: String
    public let byteCount: Int64

    public init(sha256: String, byteCount: Int64) {
        self.sha256 = sha256
        self.byteCount = byteCount
    }

    public static func compute(url: URL) throws -> RoundTripArtifactDigest {
        let handle = try FileHandle(forReadingFrom: url)
        var hasher = SHA256()
        var byteCount: Int64 = 0
        do {
            while true {
                guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                    break
                }
                hasher.update(data: chunk)
                byteCount += Int64(chunk.count)
            }
        } catch {
            do {
                try handle.close()
            } catch let closeError {
                throw RoundTripArtifactDigestError.closeFailedAfterReadFailure(
                    path: url.path(percentEncoded: false),
                    readError: error.localizedDescription,
                    closeError: closeError.localizedDescription
                )
            }
            throw error
        }
        try handle.close()

        let digest = hasher.finalize()
        return RoundTripArtifactDigest(
            sha256: digest.map { String(format: "%02x", $0) }.joined(),
            byteCount: byteCount
        )
    }
}
