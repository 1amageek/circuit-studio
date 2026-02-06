import Foundation

/// The kind of process library reference.
public enum ProcessLibraryKind: String, Sendable, Codable, Hashable {
    case include
    case library
}
