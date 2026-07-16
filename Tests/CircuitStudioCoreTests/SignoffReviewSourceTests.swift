import CircuitSignoff
import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Signoff review sources")
struct SignoffReviewSourceTests {
    @Test func commandServiceRunsExternalCommands() async throws {
        let root = try makeTemporaryRoot("command")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-drc",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=DRC_CLEAN message="clean"\\n'
            printf 'SIGNOFF_RESULT status=pass\\n'
            exit 0
            """
        )
        let runner: any SignoffCommandRunning = ExternalSignoffCommandService()

        let review = try await runner.run(
            commands: [
                ExternalSignoffCommand(
                    kind: .drc,
                    toolName: "mock-drc",
                    executablePath: executable.path(percentEncoded: false)
                ),
            ],
            artifactDirectory: root.appending(path: "artifacts")
        )

        #expect(review.reports.count == 1)
        #expect(review.passed)
        #expect(review.reports[0].diagnostics.first?.ruleID == "DRC_CLEAN")
    }

    @Test func artifactServiceLoadsGoldenLogs() async throws {
        let root = try makeTemporaryRoot("replay")
        defer { removeTemporaryRoot(root) }
        let logURL = root.appending(path: "calibre-lvs.log")
        try """
        Calibre nmLVS summary
        LVS MISMATCH rule=LVS_SHORT instance=MN1 net=out message="layout net shorted against schematic"
        """.write(to: logURL, atomically: true, encoding: .utf8)
        let parser = try SignoffReportParserCatalog().parser(for: "calibre-like")
        let loader: any SignoffReviewLoading = ExternalSignoffArtifactService(parser: parser)

        let review = try loader.load(logs: [
                ExternalSignoffLogArtifact(
                    kind: .lvs,
                    toolName: "calibre-lvs",
                    logURL: logURL,
                    success: true
                ),
            ])

        #expect(!review.passed)
        #expect(review.reports[0].diagnostics == [
            ExternalSignoffDiagnostic(
                severity: .error,
                message: "layout net shorted against schematic",
                ruleID: "LVS_SHORT",
                componentName: "MN1",
                netName: "out",
                rawLine: "LVS MISMATCH rule=LVS_SHORT instance=MN1 net=out message=\"layout net shorted against schematic\""
            ),
        ])
    }

    @Test func toolSpecificParsersNormalizeDiagnostics() throws {
        let catalog = SignoffReportParserCatalog()
        let magicReport = try catalog.parser(for: "magic-netgen-like").parse(
            kind: .lvs,
            toolName: "netgen",
            logPath: "/tmp/netgen.log",
            rawOutput: "Netlists do not match net=out device=MN1",
            success: true
        )
        #expect(magicReport.diagnostics == [
            ExternalSignoffDiagnostic(
                severity: .error,
                message: "Netlists do not match net=out device=MN1",
                ruleID: "NETGEN_LVS_MISMATCH",
                componentName: "MN1",
                netName: "out",
                rawLine: "Netlists do not match net=out device=MN1"
            ),
        ])

        let klayoutReport = try catalog.parser(for: "klayout-like").parse(
            kind: .drc,
            toolName: "klayout",
            logPath: "/tmp/klayout.log",
            rawOutput: "ERROR: min_space: net=out message=\"spacing violation\"",
            success: true
        )
        #expect(klayoutReport.diagnostics == [
            ExternalSignoffDiagnostic(
                severity: .error,
                message: "spacing violation",
                ruleID: "min_space",
                netName: "out",
                rawLine: "ERROR: min_space: net=out message=\"spacing violation\""
            ),
        ])

        let calibreReport = try catalog.parser(for: "calibre-like").parse(
            kind: .lvs,
            toolName: "calibre",
            logPath: "/tmp/calibre.log",
            rawOutput: "LVS INCORRECT",
            success: true
        )
        #expect(calibreReport.diagnostics == [
            ExternalSignoffDiagnostic(
                severity: .error,
                message: "LVS INCORRECT",
                ruleID: "CALIBRE_SIGNOFF_INCORRECT",
                rawLine: "LVS INCORRECT"
            ),
        ])
    }

    @Test func unsupportedReportStyleIDIsTypedError() throws {
        #expect(throws: SignoffReportParserCatalogError.unsupportedStyleID("unknown")) {
            _ = try SignoffReportParserCatalog().parser(for: "unknown")
        }
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioSignoffReviewSourceTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeTemporaryRoot(_ root: URL) {
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove temporary root: \(error)")
        }
    }

    private func writeExecutable(named name: String, in root: URL, contents: String) throws -> URL {
        let url = root.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        return url
    }
}
