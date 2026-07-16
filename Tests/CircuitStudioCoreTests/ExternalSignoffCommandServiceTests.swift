import CircuitSignoff
import Foundation
import SignoffToolSupport
import Testing
import CircuitStudioCore
@testable import CircuitStudioApp

@Suite("ExternalSignoffCommandService Tests")
struct ExternalSignoffCommandServiceTests {

    @Test func runCapturesLogArtifactAndParsesDiagnostics() async throws {
        let root = try makeTemporaryRoot("capture")
        defer { removeTemporaryRoot(root) }

        let executable = try writeExecutable(
            named: "mock-drc",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=DRC_START message="started"\\n'
            printf '[WARN] rule=MIN_SPACE net=out message="review spacing"\\n' >&2
            printf 'SIGNOFF_RESULT status=pass\\n'
            printf 'arg_count=%s\\n' "$#"
            exit 0
            """
        )
        let artifactDirectory = root.appending(path: "artifacts")
        let command = ExternalSignoffCommand(
            kind: .drc,
            toolName: "mock drc",
            executablePath: executable.path(percentEncoded: false),
            arguments: ["--layout", "layout.oas"],
            workingDirectory: root
        )

        let result = try await ExternalSignoffCommandService().run(
            command: command,
            artifactDirectory: artifactDirectory
        )

        #expect(result.exitCode == 0)
        #expect(result.commandLine == [
            executable.path(percentEncoded: false),
            "--layout",
            "layout.oas",
        ])
        #expect(result.logURL.lastPathComponent == "drc-mock-drc.log")
        #expect(FileManager.default.fileExists(atPath: result.logURL.path(percentEncoded: false)))
        #expect(result.report.passed)
        #expect(result.report.logPath == result.logURL.path(percentEncoded: false))
        #expect(result.report.diagnostics.map(\.severity) == [.info, .warning])
        #expect(result.report.diagnostics[1].ruleID == "MIN_SPACE")
        #expect(result.report.diagnostics[1].netName == "out")
        #expect(result.report.diagnostics[1].message == "review spacing")

        let log = try String(contentsOf: result.logURL, encoding: .utf8)
        #expect(log.contains("tool=mock drc"))
        #expect(log.contains("exit_code=0"))
        #expect(log.contains("[stdout]"))
        #expect(log.contains("[stderr]"))
    }

    @Test func nonZeroExitCreatesFailingReportWithoutDroppingArtifacts() async throws {
        let root = try makeTemporaryRoot("failure")
        defer { removeTemporaryRoot(root) }

        let executable = try writeExecutable(
            named: "mock-lvs",
            in: root,
            contents: """
            #!/bin/sh
            printf '[ERROR] rule=LVS_OPEN component=MN1 net=out message="open terminal"\\n' >&2
            exit 3
            """
        )
        let artifactDirectory = root.appending(path: "artifacts")
        let command = ExternalSignoffCommand(
            kind: .lvs,
            toolName: "mock-lvs",
            executablePath: executable.path(percentEncoded: false),
            logFileName: "lvs-run.log"
        )

        let result = try await ExternalSignoffCommandService().run(
            command: command,
            artifactDirectory: artifactDirectory
        )

        #expect(result.exitCode == 3)
        #expect(FileManager.default.fileExists(atPath: result.logURL.path(percentEncoded: false)))
        #expect(result.report.logPath.hasSuffix("lvs-run.log"))
        #expect(!result.report.success)
        #expect(!result.report.passed)
        #expect(result.report.diagnostics == [
            ExternalSignoffDiagnostic(
                severity: .error,
                message: "open terminal",
                ruleID: "LVS_OPEN",
                componentName: "MN1",
                netName: "out",
                rawLine: "[ERROR] rule=LVS_OPEN component=MN1 net=out message=\"open terminal\""
            ),
        ])
    }

    @Test func customLogFileNameCannotEscapeArtifactDirectory() async throws {
        let root = try makeTemporaryRoot("log-path-escape")
        defer { removeTemporaryRoot(root) }

        let executable = try writeExecutable(
            named: "mock-escape",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=DRC_DONE message="complete"\\n'
            printf 'SIGNOFF_RESULT status=pass\\n'
            exit 0
            """
        )
        let artifactDirectory = root.appending(path: "artifacts")
        let outsideLog = root.appending(path: "escape.log")
        let command = ExternalSignoffCommand(
            kind: .drc,
            toolName: "escape-drc",
            executablePath: executable.path(percentEncoded: false),
            logFileName: "../escape.log"
        )

        do {
            _ = try await ExternalSignoffCommandService().run(
                command: command,
                artifactDirectory: artifactDirectory
            )
            Issue.record("Expected invalidLogFileName")
        } catch let error as ExternalSignoffCommandError {
            #expect(error == .invalidLogFileName("../escape.log"))
        }
        #expect(!FileManager.default.fileExists(atPath: outsideLog.path(percentEncoded: false)))
    }

    @Test func logHeaderEscapesCommandMetadataNewlines() async throws {
        let root = try makeTemporaryRoot("log-header-escape")
        defer { removeTemporaryRoot(root) }

        let executable = try writeExecutable(
            named: "mock-header",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=DRC_DONE message="complete"\\n'
            printf 'SIGNOFF_RESULT status=pass\\n'
            exit 0
            """
        )
        let artifactDirectory = root.appending(path: "artifacts")
        let command = ExternalSignoffCommand(
            kind: .drc,
            toolName: "mock\nforged=true",
            executablePath: executable.path(percentEncoded: false),
            arguments: ["--rule", "MIN\nSPACE"]
        )

        let result = try await ExternalSignoffCommandService().run(
            command: command,
            artifactDirectory: artifactDirectory
        )
        let log = try String(contentsOf: result.logURL, encoding: .utf8)

        #expect(log.contains("tool=mock\\nforged=true"))
        #expect(log.contains("--rule MIN\\nSPACE"))
        #expect(!log.contains("tool=mock\nforged=true"))
        #expect(!log.contains("--rule MIN\nSPACE"))
    }

    @Test(.timeLimit(.minutes(1)))
    func largeStdoutAndStderrAreDrainedWithoutDeadlock() async throws {
        let root = try makeTemporaryRoot("large-output")
        defer { removeTemporaryRoot(root) }

        let executable = try writeExecutable(
            named: "mock-large-output",
            in: root,
            contents: """
            #!/usr/bin/env perl
            for my $i (1..2500) {
                print STDOUT "stdout-$i " . ("x" x 96) . "\\n";
            print STDERR "stderr-$i " . ("y" x 96) . "\\n";
            }
            print STDOUT "[INFO] rule=DRC_DONE message=\\"complete\\"\\n";
            print STDOUT "SIGNOFF_RESULT status=pass\\n";
            print STDERR "[WARN] rule=LARGE_STDERR message=\\"drained\\"\\n";
            exit 0;
            """
        )
        let artifactDirectory = root.appending(path: "artifacts")
        let command = ExternalSignoffCommand(
            kind: .drc,
            toolName: "large-output-drc",
            executablePath: executable.path(percentEncoded: false),
            timeoutSeconds: 5.0
        )

        let result = try await ExternalSignoffCommandService().run(
            command: command,
            artifactDirectory: artifactDirectory
        )

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("stdout-2500"))
        #expect(result.standardError.contains("stderr-2500"))
        #expect(result.standardOutput.utf8.count > 200_000)
        #expect(result.standardError.utf8.count > 200_000)
        #expect(result.report.passed)
        #expect(result.report.diagnostics.contains {
            $0.ruleID == "LARGE_STDERR" && $0.message == "drained"
        })

        let log = try String(contentsOf: result.logURL, encoding: .utf8)
        #expect(log.contains("stdout-2500"))
        #expect(log.contains("stderr-2500"))
    }

    @Test func runCommandsBuildsUnapprovedReview() async throws {
        let root = try makeTemporaryRoot("aggregate")
        defer { removeTemporaryRoot(root) }

        let executable = try writeExecutable(
            named: "mock-clean",
            in: root,
            contents: """
            #!/bin/sh
            printf '[INFO] rule=CLEAN message="clean"\\n'
            printf 'SIGNOFF_RESULT status=pass\\n'
            exit 0
            """
        )
        let commands = [
            ExternalSignoffCommand(
                kind: .drc,
                toolName: "clean-drc",
                executablePath: executable.path(percentEncoded: false)
            ),
            ExternalSignoffCommand(
                kind: .lvs,
                toolName: "clean-lvs",
                executablePath: executable.path(percentEncoded: false)
            ),
        ]

        let review = try await ExternalSignoffCommandService().run(
            commands: commands,
            artifactDirectory: root.appending(path: "artifacts")
        )

        #expect(review.reports.count == 2)
        #expect(review.passed)
        #expect(!review.isApproved)
        #expect(!review.isReadyForPEX)
    }

    @Test(.timeLimit(.minutes(1)))
    func commandTimeoutTerminatesToolAndPreservesCapturedOutput() async throws {
        try await ProcessTimeoutTestGate.shared.withExclusiveAccess {
            let root = try makeTemporaryRoot("timeout")
            defer { removeTemporaryRoot(root) }

            let executable = try writeExecutable(
                named: "mock-timeout",
                in: root,
                contents: """
                #!/bin/sh
                printf '[INFO] rule=START message="started"\\n'
                exec sleep 30
                """
            )
            let command = ExternalSignoffCommand(
                kind: .drc,
                toolName: "slow-drc",
                executablePath: executable.path(percentEncoded: false),
                timeoutSeconds: 3.0
            )

            do {
                _ = try await ExternalSignoffCommandService().run(
                    command: command,
                    artifactDirectory: root.appending(path: "artifacts")
                )
                Issue.record("Expected timedOut")
            } catch let error as TimedProcessError {
                guard case .timedOut(let executablePath, let timeoutSeconds, let stdout, _) = error else {
                    Issue.record("Expected timedOut, got \(error)")
                    return
                }
                #expect(executablePath == executable.path(percentEncoded: false))
                #expect(timeoutSeconds == 3.0)
                #expect(stdout.contains("START"))
            }
        }
    }

    @Test func reviewStorePersistsApproval() throws {
        let root = try makeTemporaryRoot("review-store")
        defer { removeTemporaryRoot(root) }
        let store = ExternalSignoffReviewStore()
        let review = ExternalSignoffReview(reports: [
            ExternalSignoffToolReport(
                kind: .drc,
                toolName: "mock-drc",
                success: true,
                logPath: "/tmp/drc.log"
            ),
            ExternalSignoffToolReport(
                kind: .lvs,
                toolName: "mock-lvs",
                success: true,
                logPath: "/tmp/lvs.log"
            ),
        ])

        let url = try store.save(review, forProjectAt: root)
        #expect(url.lastPathComponent == "external-signoff-review.json")
        let unapproved = try store.load(forProjectAt: root)
        #expect(!unapproved.isReadyForPEX)

        let approvedAt = Date(timeIntervalSince1970: 1_800)
        let approved = try store.approve(
            forProjectAt: root,
            approvedBy: "layout-reviewer",
            approvedAt: approvedAt,
            waiverIDs: ["W-001"]
        )
        let loaded = try store.load(forProjectAt: root)

        #expect(approved.isReadyForPEX)
        #expect(loaded.approvedBy == "layout-reviewer")
        #expect(loaded.approvedAt == approvedAt)
        #expect(loaded.approvalKind == .human)
        #expect(loaded.waiverIDs == ["W-001"])
        #expect(loaded.isReadyForPEX)

        let automated = review.approving(
            by: "design-flow-command",
            at: approvedAt,
            approvalKind: .automated
        )
        #expect(automated.approvalKind == .automated)
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioExternalSignoffCommandServiceTests-\(name)-\(UUID().uuidString)")
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
