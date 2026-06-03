import Foundation
import Testing

func removeCoreTestTemporaryDirectory(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return
    }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory: \(url.path(percentEncoded: false)): \(error)")
    }
}
