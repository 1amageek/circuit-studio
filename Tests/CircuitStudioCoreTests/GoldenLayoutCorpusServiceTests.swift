import Foundation
import Testing
@testable import CircuitStudioApp
@testable import CircuitStudioCore

@Suite("GoldenLayoutCorpusService Tests")
struct GoldenLayoutCorpusServiceTests {
    @Test func loadGoldenLayoutCorpusValidatesLayoutAndSignoffLogs() throws {
        let manifestURL = try fixtureURL(
            "manifest",
            extension: "json",
            subdirectory: "layout/golden-corpus"
        )

        let corpus = try GoldenLayoutCorpusService().load(manifestURL: manifestURL)
        let entry = try #require(corpus.layouts.first)

        #expect(corpus.id == "golden-layout-signoff")
        #expect(entry.id == "voltage-divider-oasis-clean")
        #expect(entry.format == "oas")
        #expect(entry.topCell == "TOP")
        #expect(entry.layoutURL.lastPathComponent == "golden-voltage-divider.oas")
        #expect(entry.technologyFiles.map(\.kind) == ["lef", "def"])
        #expect(entry.technologyFiles.map { $0.fileURL.lastPathComponent } == ["virtual45.lef", "voltage-divider.def"])
        #expect(entry.signoffLogs.map(\.kind) == [.drc, .lvs])
        #expect(entry.signoffReview.passed)
        #expect(!entry.signoffReview.isReadyForPEX)
        #expect(entry.signoffReview.reports.allSatisfy { $0.success })
        #expect(entry.pexManifests.count == 1)
        #expect(entry.pexManifests[0].defaultCornerID == "tt_25c_1v0")
        #expect(entry.pexManifests[0].artifacts.corners.map(\.cornerID).contains("tt_25c_1v0"))
        #expect(entry.requiresApproval)
    }

    private func fixtureURL(_ name: String, extension ext: String, subdirectory: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: ext,
            subdirectory: subdirectory
        ) else {
            throw StudioError.projectLoadFailed("Missing fixture: Fixtures/\(subdirectory)/\(name).\(ext)")
        }
        return url
    }
}
