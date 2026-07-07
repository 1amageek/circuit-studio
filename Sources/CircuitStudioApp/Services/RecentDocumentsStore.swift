import Foundation
import Observation

/// Maintains the File > Open Recent list.
///
/// Entries persist in UserDefaults as security-scoped bookmarks because the
/// app runs sandboxed: a bare path stops being readable after relaunch, while
/// a bookmark carries the user's open-panel grant across launches.
@MainActor
@Observable
public final class RecentDocumentsStore {
    public struct LoadWarning: Equatable, Sendable {
        public let message: String
    }

    private struct LoadResult {
        let documents: [RecentDocument]
        let warning: LoadWarning?
    }

    public enum StoreError: Error, LocalizedError {
        /// The system denied security-scoped access to the resolved URL.
        case accessDenied(path: String)

        public var errorDescription: String? {
            switch self {
            case .accessDenied(let path):
                return "Access to \(path) was denied by the sandbox."
            }
        }
    }

    /// Most recently opened first.
    public private(set) var documents: [RecentDocument] = []
    public private(set) var loadWarning: LoadWarning?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let limit: Int

    /// URLs whose security-scoped access has been started. Access is held for
    /// the app's lifetime so a reopened document stays readable; the count is
    /// bounded by the number of recents opened in one session.
    @ObservationIgnored private var accessedURLs: [URL] = []

    private static let defaultsKey = "recentDocuments.v1"

    public init(defaults: UserDefaults = .standard, limit: Int = 10) {
        self.defaults = defaults
        self.limit = limit
        let loadResult = Self.load(from: defaults)
        self.documents = loadResult.documents
        self.loadWarning = loadResult.warning
    }

    /// Records a successful open, moving the document to the front and
    /// refreshing its bookmark.
    public func noteOpened(_ url: URL, kind: RecentDocument.Kind) throws {
        let standardized = url.standardizedFileURL
        let bookmark = try standardized.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let document = RecentDocument(
            path: standardized.path(percentEncoded: false),
            kind: kind,
            bookmark: bookmark
        )
        documents.removeAll { $0.path == document.path }
        documents.insert(document, at: 0)
        if documents.count > limit {
            documents.removeLast(documents.count - limit)
        }
        try persist()
    }

    /// Resolves the bookmark and starts security-scoped access, returning the
    /// live URL. Access is intentionally not stopped: the document is about to
    /// become the open project/netlist and must stay readable.
    public func beginAccess(to document: RecentDocument) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: document.bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard url.startAccessingSecurityScopedResource() else {
            throw StoreError.accessDenied(path: document.path)
        }
        accessedURLs.append(url)
        if isStale {
            try noteOpened(url, kind: document.kind)
        }
        return url
    }

    public func remove(_ document: RecentDocument) throws {
        documents.removeAll { $0.id == document.id }
        try persist()
    }

    public func clear() throws {
        documents = []
        try persist()
    }

    // MARK: - Persistence

    private func persist() throws {
        let data = try JSONEncoder().encode(documents)
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> LoadResult {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return LoadResult(documents: [], warning: nil)
        }
        do {
            return LoadResult(documents: try JSONDecoder().decode([RecentDocument].self, from: data), warning: nil)
        } catch {
            // A corrupt or incompatible list is not worth blocking startup
            // over, but losing it must be visible.
            return LoadResult(
                documents: [],
                warning: LoadWarning(message: "Discarding unreadable recent-documents list: \(error)")
            )
        }
    }
}
