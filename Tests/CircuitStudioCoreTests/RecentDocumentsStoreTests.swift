import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("RecentDocumentsStore Tests")
@MainActor
struct RecentDocumentsStoreTests {

    @Test func noteOpenedInsertsMostRecentFirstAndDedupes() throws {
        let context = try makeContext("dedupe")
        defer { context.tearDown() }

        let first = try context.makeFile("a.cir")
        let second = try context.makeFile("b.cir")

        try context.store.noteOpened(first, kind: .netlistFile)
        try context.store.noteOpened(second, kind: .netlistFile)
        #expect(context.store.documents.map(\.displayName) == ["b.cir", "a.cir"])

        try context.store.noteOpened(first, kind: .netlistFile)
        #expect(context.store.documents.map(\.displayName) == ["a.cir", "b.cir"])
        #expect(context.store.documents.count == 2)
    }

    @Test func noteOpenedTrimsToLimit() throws {
        let context = try makeContext("limit", limit: 3)
        defer { context.tearDown() }

        for index in 0..<5 {
            let url = try context.makeFile("file\(index).cir")
            try context.store.noteOpened(url, kind: .netlistFile)
        }

        #expect(context.store.documents.count == 3)
        #expect(context.store.documents.first?.displayName == "file4.cir")
        #expect(context.store.documents.last?.displayName == "file2.cir")
    }

    @Test func documentsPersistAcrossStoreInstances() throws {
        let context = try makeContext("persist")
        defer { context.tearDown() }

        let project = try context.makeDirectory("MyProject")
        try context.store.noteOpened(project, kind: .projectFolder)

        let reloaded = RecentDocumentsStore(defaults: context.defaults)
        #expect(reloaded.documents.count == 1)
        let document = try #require(reloaded.documents.first)
        #expect(document.displayName == "MyProject")
        #expect(document.kind == .projectFolder)
    }

    @Test func beginAccessResolvesToReadableURL() throws {
        let context = try makeContext("access")
        defer { context.tearDown() }

        let file = try context.makeFile("readable.cir", contents: "* netlist\n.end\n")
        try context.store.noteOpened(file, kind: .netlistFile)
        let document = try #require(context.store.documents.first)

        let url = try context.store.beginAccess(to: document)
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains(".end"))
    }

    @Test func removeAndClearUpdatePersistedList() throws {
        let context = try makeContext("remove")
        defer { context.tearDown() }

        let first = try context.makeFile("a.cir")
        let second = try context.makeFile("b.cir")
        try context.store.noteOpened(first, kind: .netlistFile)
        try context.store.noteOpened(second, kind: .netlistFile)

        let document = try #require(context.store.documents.last)
        try context.store.remove(document)
        #expect(context.store.documents.map(\.displayName) == ["b.cir"])

        try context.store.clear()
        #expect(context.store.documents.isEmpty)

        let reloaded = RecentDocumentsStore(defaults: context.defaults)
        #expect(reloaded.documents.isEmpty)
    }

    // MARK: - Test Context

    private struct Context {
        let store: RecentDocumentsStore
        let defaults: UserDefaults
        let suiteName: String
        let root: URL

        func makeFile(_ name: String, contents: String = "* test\n") throws -> URL {
            let url = root.appending(path: name)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        func makeDirectory(_ name: String) throws -> URL {
            let url = root.appending(path: name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove temporary directory: \(error)")
            }
        }
    }

    private func makeContext(_ name: String, limit: Int = 10) throws -> Context {
        let suiteName = "RecentDocumentsStoreTests-\(name)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appending(path: suiteName)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Context(
            store: RecentDocumentsStore(defaults: defaults, limit: limit),
            defaults: defaults,
            suiteName: suiteName,
            root: root
        )
    }
}
