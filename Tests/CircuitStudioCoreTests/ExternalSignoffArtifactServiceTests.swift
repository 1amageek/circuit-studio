import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("ExternalSignoffArtifactService Tests")
struct ExternalSignoffArtifactServiceTests {

    @Test func loadGoldenSignoffLogsBuildsReview() throws {
        let drcURL = try fixtureURL("golden-calibre-drc-clean", extension: "log")
        let lvsURL = try fixtureURL("golden-calibre-lvs-clean", extension: "log")

        let review = try ExternalSignoffArtifactService().load(logs: [
            ExternalSignoffLogArtifact(
                kind: .drc,
                toolName: "calibre-drc",
                logURL: drcURL,
                success: true,
                parserStyle: .calibreLike
            ),
            ExternalSignoffLogArtifact(
                kind: .lvs,
                toolName: "calibre-lvs",
                logURL: lvsURL,
                success: true,
                parserStyle: .calibreLike
            ),
        ])

        #expect(review.reports.count == 2)
        #expect(review.passed)
        #expect(!review.isApproved)
        #expect(!review.isReadyForPEX)
        #expect(review.reports.flatMap(\.diagnostics).map(\.severity) == [.info, .info])
        #expect(review.reports.map(\.logPath).allSatisfy { $0.hasSuffix(".log") })
    }

    @Test func loadGoldenMismatchLogBlocksReview() throws {
        let lvsURL = try fixtureURL("golden-calibre-lvs-mismatch", extension: "log")

        let review = try ExternalSignoffArtifactService().load(logs: [
            ExternalSignoffLogArtifact(
                kind: .lvs,
                toolName: "calibre-lvs",
                logURL: lvsURL,
                success: true,
                parserStyle: .calibreLike
            ),
        ])

        #expect(!review.passed)
        #expect(!review.isReadyForPEX)
        #expect(review.reports[0].diagnostics.contains {
            $0 == ExternalSignoffDiagnostic(
                severity: .error,
                message: "layout net shorted against schematic",
                ruleID: "LVS_SHORT",
                componentName: "MN1",
                netName: "out",
                rawLine: "LVS MISMATCH rule=LVS_SHORT instance=MN1 net=out message=\"layout net shorted against schematic\""
            )
        })
        #expect(review.reports[0].diagnostics.contains {
            $0.ruleID == "CALIBRE_SIGNOFF_INCORRECT" && $0.severity == .error
        })
    }

    @Test func loadRejectsMissingLog() throws {
        let missingURL = URL(filePath: "/tmp/no-such-signoff-log-\(UUID().uuidString).log")

        do {
            _ = try ExternalSignoffArtifactService().load(logs: [
                ExternalSignoffLogArtifact(
                    kind: .drc,
                    toolName: "calibre-drc",
                    logURL: missingURL,
                    success: true
                ),
            ])
            Issue.record("Expected missing log error")
        } catch ExternalSignoffArtifactError.missingLog(let path) {
            #expect(path == missingURL.path(percentEncoded: false))
        } catch {
            Issue.record("Expected missing log error, got \(error)")
        }
    }

    private func fixtureURL(_ name: String, extension ext: String) throws -> URL {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "signoff"
        ) else {
            throw ExternalSignoffArtifactError.missingLog("Fixtures/signoff/\(name).\(ext)")
        }
        return url
    }
}
