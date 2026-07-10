import Foundation
import CircuitStudioCore

/// A bounded project-file snapshot displayed by the center editor.
public struct ProjectFileDocument: Sendable, Equatable {
    public enum Storage: Sendable, Equatable {
        case text(current: String, saved: String)
        case binary
        case tooLarge(limit: Int)
    }

    public static let maximumEditableByteCount = 8 * 1_024 * 1_024

    public let url: URL
    public private(set) var storage: Storage
    public private(set) var byteCount: Int
    public private(set) var modificationDate: Date?

    public var text: String? {
        guard case .text(let current, _) = storage else { return nil }
        return current
    }

    public var savedText: String? {
        guard case .text(_, let saved) = storage else { return nil }
        return saved
    }

    public var isEditable: Bool {
        text != nil
    }

    public var isDirty: Bool {
        guard case .text(let current, let saved) = storage else { return false }
        return current != saved
    }

    public var lineCount: Int {
        guard let text else { return 0 }
        if text.isEmpty { return 0 }
        return text.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
    }

    public static func load(
        from url: URL,
        using fileSystemService: FileSystemService
    ) throws -> ProjectFileDocument {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        } catch {
            throw StudioError.fileReadError(error.localizedDescription)
        }

        let byteCount = values.fileSize ?? 0
        guard byteCount <= maximumEditableByteCount else {
            return ProjectFileDocument(
                url: url,
                storage: .tooLarge(limit: maximumEditableByteCount),
                byteCount: byteCount,
                modificationDate: values.contentModificationDate
            )
        }

        let data = try fileSystemService.readData(at: url)
        guard data.count <= maximumEditableByteCount else {
            return ProjectFileDocument(
                url: url,
                storage: .tooLarge(limit: maximumEditableByteCount),
                byteCount: data.count,
                modificationDate: values.contentModificationDate
            )
        }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            return ProjectFileDocument(
                url: url,
                storage: .binary,
                byteCount: data.count,
                modificationDate: values.contentModificationDate
            )
        }

        return ProjectFileDocument(
            url: url,
            storage: .text(current: text, saved: text),
            byteCount: data.count,
            modificationDate: values.contentModificationDate
        )
    }

    public mutating func updateText(_ text: String) {
        guard case .text(_, let saved) = storage else { return }
        storage = .text(current: text, saved: saved)
        byteCount = text.lengthOfBytes(using: .utf8)
    }

    public mutating func markSaved(at date: Date = Date()) {
        guard case .text(let current, _) = storage else { return }
        storage = .text(current: current, saved: current)
        byteCount = current.lengthOfBytes(using: .utf8)
        modificationDate = date
    }
}
