import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("Project File Document Tests")
@MainActor
struct ProjectFileDocumentTests {
    @Test func textFileTracksDirtyStateAndSavesAtomically() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "project-file-\(UUID().uuidString).json")
        try "{\"value\":1}\n".write(to: url, atomically: true, encoding: .utf8)
        defer { removeCoreTestTemporaryDirectory(url) }

        let fileSystem = FileSystemService()
        let appState = AppState()
        appState.requestOpenProjectItem(at: url, using: fileSystem)
        appState.updateProjectFileText("{\"value\":2}\n")

        #expect(appState.isProjectFileDirty)
        try appState.saveProjectFile(using: fileSystem)
        #expect(!appState.isProjectFileDirty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"value\":2}\n")
    }

    @Test func invalidJSONCannotReplaceCanonicalProjectFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "project-file-invalid-\(UUID().uuidString).json")
        try "{}\n".write(to: url, atomically: true, encoding: .utf8)
        defer { removeCoreTestTemporaryDirectory(url) }

        let fileSystem = FileSystemService()
        let appState = AppState()
        appState.requestOpenProjectItem(at: url, using: fileSystem)
        appState.updateProjectFileText("{")

        var didThrow = false
        do {
            try appState.saveProjectFile(using: fileSystem)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{}\n")
        #expect(appState.isProjectFileDirty)
    }

    @Test func binaryFilesAreRepresentedWithoutLossyDecoding() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "project-file-binary-\(UUID().uuidString).gds")
        try Data([0, 255, 1, 2]).write(to: url)
        defer { removeCoreTestTemporaryDirectory(url) }

        let document = try ProjectFileDocument.load(from: url, using: FileSystemService())

        #expect(document.storage == .binary)
        #expect(!document.isEditable)
        #expect(!document.isDirty)
    }

    @Test func saveRejectsAnExternalFileChange() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "project-file-conflict-\(UUID().uuidString).json")
        try "{}\n".write(to: url, atomically: true, encoding: .utf8)
        defer { removeCoreTestTemporaryDirectory(url) }

        let fileSystem = FileSystemService()
        let appState = AppState()
        appState.requestOpenProjectItem(at: url, using: fileSystem)
        appState.updateProjectFileText("{\"local\":true}\n")
        try "{\"agent\":true}\n".write(to: url, atomically: true, encoding: .utf8)

        var didThrow = false
        do {
            try appState.saveProjectFile(using: fileSystem)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"agent\":true}\n")
        #expect(appState.isProjectFileDirty)
    }
}
