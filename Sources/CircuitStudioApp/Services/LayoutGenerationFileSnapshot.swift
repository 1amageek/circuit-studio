import Foundation

struct LayoutGenerationFileSnapshot: Sendable, Codable, Equatable {
    let path: String?
    let exists: Bool

    var displayPath: String {
        path ?? "none"
    }

    var fileName: String? {
        path.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    static func capture(_ url: URL?) -> LayoutGenerationFileSnapshot {
        guard let url else {
            return LayoutGenerationFileSnapshot(path: nil, exists: false)
        }
        let path = url.path(percentEncoded: false)
        return LayoutGenerationFileSnapshot(
            path: path,
            exists: FileManager.default.fileExists(atPath: path)
        )
    }
}
