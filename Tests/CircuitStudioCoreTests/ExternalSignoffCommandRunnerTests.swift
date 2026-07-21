import CircuitSignoff
import CircuiteFoundation
import Foundation
import SignoffToolSupport
import Testing
import CircuitStudioCore
@testable import CircuitStudioApp

@Suite("ExternalSignoffCommandRunner Tests")
struct ExternalSignoffCommandRunnerTests {

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

        let result = try await ExternalSignoffCommandRunner().run(
            command: command,
            artifactDirectory: artifactDirectory
        )

        #expect(result.exitCode == 0)
        #expect(result.sanitizedCommandLine.dropFirst() == ["--layout", "layout.oas"])
        #expect(result.sanitizedSourceExecutablePath == executable.path(percentEncoded: false))
        #expect(result.sanitizedCommandLine.first == executable.path(percentEncoded: false))
        #expect(result.logURL.lastPathComponent.hasPrefix("drc-mock-drc-"))
        #expect(result.logURL.pathExtension == "log")
        #expect(FileManager.default.fileExists(atPath: result.logURL.path(percentEncoded: false)))
        #expect(result.report.passed)
        #expect(result.report.logPath == result.logURL.path(percentEncoded: false))
        #expect(result.report.diagnostics.map(\.severity) == [.info, .warning])
        #expect(result.report.diagnostics[1].ruleID == "MIN_SPACE")
        #expect(result.report.diagnostics[1].netName == "out")
        #expect(result.report.diagnostics[1].message == "review spacing")
        #expect(result.provenance.environment?.environmentDigest != nil)

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

        let result = try await ExternalSignoffCommandRunner().run(
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

    @Test func executionProvenanceBindsMeasuredExecutableAndRedactsSecrets() async throws {
        let root = try makeTemporaryRoot("provenance-redaction")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-redaction",
            in: root,
            contents: """
            #!/bin/sh
            printf 'received=%s\n' "$1"
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        let secret = "signoff-token-42"
        let command = ExternalSignoffCommand(
            kind: .drc,
            toolName: "mock-redaction-\(secret)",
            executablePath: executable.path(percentEncoded: false),
            arguments: [secret],
            sensitiveArgumentIndexes: [0]
        )
        #expect(!String(describing: command).contains(secret))
        #expect(!String(reflecting: command).contains(secret))
        let result = try await ExternalSignoffCommandRunner().run(
            command: command,
            artifactDirectory: root.appending(path: "artifacts")
        )

        #expect(result.sanitizedCommandLine == [
            executable.path(percentEncoded: false),
            "<redacted>",
        ])
        #expect(result.standardOutput.contains("received=<redacted>"))
        #expect(!result.standardOutput.contains(secret))
        #expect(result.provenance.producer.kind == .tool)
        #expect(result.provenance.producer.version.hasPrefix("sha256-"))
        #expect(result.provenance.producer.version == result.provenance.producer.build)
        #expect(result.provenance.invocation?.executable == executable.path(percentEncoded: false))
        #expect(result.provenance.invocation?.arguments == ["<redacted>"])
        let log = try String(contentsOf: result.logURL, encoding: .utf8)
        #expect(!log.contains(secret))
        #expect(log.contains("<redacted>"))
        let encoded = try JSONEncoder().encode(result)
        #expect(!String(decoding: encoded, as: UTF8.self).contains(secret))
    }

    @Test func suppliedEnvironmentSecretsAreRedactedAndOnlyDigested() async throws {
        let root = try makeTemporaryRoot("environment-redaction")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-environment",
            in: root,
            contents: """
            #!/bin/sh
            printf 'environment=%s\n' "$SIGNOFF_TOKEN"
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        let secret = "environment-secret-73"
        let result = try await ExternalSignoffCommandRunner().run(
            command: ExternalSignoffCommand(
                kind: .drc,
                toolName: "environment-drc",
                executablePath: executable.path(percentEncoded: false),
                environment: ["SIGNOFF_TOKEN": secret],
                sensitiveEnvironmentKeys: ["SIGNOFF_TOKEN"]
            ),
            artifactDirectory: root.appending(path: "artifacts")
        )

        #expect(result.standardOutput.contains("environment=<redacted>"))
        #expect(result.provenance.environment?.environmentDigest != nil)
        let encoded = try JSONEncoder().encode(result)
        let persisted = String(decoding: encoded, as: UTF8.self)
        #expect(!persisted.contains(secret))
        let log = try String(contentsOf: result.logURL, encoding: .utf8)
        #expect(!log.contains(secret))
    }

    @Test func nonSensitiveEnvironmentValuesRemainAvailableToReportParsers() async throws {
        let root = try makeTemporaryRoot("environment-report-input")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-report-environment",
            in: root,
            contents: """
            #!/bin/sh
            printf 'DENSITY_LAYER %s\n' "$DENSITY_LAYER"
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )

        let result = try await ExternalSignoffCommandRunner().run(
            command: ExternalSignoffCommand(
                kind: .density,
                toolName: "environment-report-input",
                executablePath: executable.path(percentEncoded: false),
                environment: ["DENSITY_LAYER": "MET1"]
            ),
            artifactDirectory: root.appending(path: "artifacts")
        )

        #expect(result.standardOutput.contains("DENSITY_LAYER MET1"))
        #expect(result.provenance.environment?.environmentDigest != nil)
    }

    @Test func effectiveEnvironmentFingerprintChangesWithSuppliedEnvironment() async throws {
        let root = try makeTemporaryRoot("effective-environment-fingerprint")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-effective-environment",
            in: root,
            contents: """
            #!/bin/sh
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        let artifactDirectory = root.appending(path: "artifacts")
        let first = try await ExternalSignoffCommandRunner().run(
            command: ExternalSignoffCommand(
                kind: .drc,
                toolName: "environment-fingerprint",
                executablePath: executable.path(percentEncoded: false),
                environment: ["SIGNOFF_CORNER": "slow"]
            ),
            artifactDirectory: artifactDirectory
        )
        let second = try await ExternalSignoffCommandRunner().run(
            command: ExternalSignoffCommand(
                kind: .drc,
                toolName: "environment-fingerprint",
                executablePath: executable.path(percentEncoded: false),
                environment: ["SIGNOFF_CORNER": "fast"]
            ),
            artifactDirectory: artifactDirectory
        )

        let firstDigest = try #require(first.provenance.environment?.environmentDigest)
        let secondDigest = try #require(second.provenance.environment?.environmentDigest)
        #expect(firstDigest != secondDigest)
        #expect(first.logURL != second.logURL)
    }

    @Test func invalidSensitiveArgumentIndexFailsBeforeLaunchingTheTool() async throws {
        let root = try makeTemporaryRoot("invalid-redaction-index")
        defer { removeTemporaryRoot(root) }
        let marker = root.appending(path: "launched")
        let executable = try writeExecutable(
            named: "mock-invalid-redaction",
            in: root,
            contents: """
            #!/bin/sh
            touch "\(marker.path(percentEncoded: false))"
            exit 0
            """
        )

        await #expect(throws: ExternalSignoffCommandError.invalidSensitiveArgumentIndex(
            index: 1,
            argumentCount: 1
        )) {
            _ = try await ExternalSignoffCommandRunner().run(
                command: ExternalSignoffCommand(
                    kind: .drc,
                    toolName: "mock-invalid-redaction",
                    executablePath: executable.path(percentEncoded: false),
                    arguments: ["secret"],
                    sensitiveArgumentIndexes: [1]
                ),
                artifactDirectory: root.appending(path: "artifacts")
            )
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test func sourceExecutableRunsWithAdjacentResourceAndRetainsNonExecutableSnapshot() async throws {
        let root = try makeTemporaryRoot("source-executable-adjacent-resource")
        defer { removeTemporaryRoot(root) }
        let resource = root.appending(path: "signoff-resource.txt")
        try Data("adjacent-resource-loaded\n".utf8).write(to: resource, options: .atomic)
        let executable = try writeExecutable(
            named: "mock-resource-tool",
            in: root,
            contents: """
            #!/bin/sh
            cat "$(dirname "$0")/signoff-resource.txt"
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        let executablePath = executable.path(percentEncoded: false)
        let original = try Data(contentsOf: executable)
        let result = try await ExternalSignoffCommandRunner().run(
            command: ExternalSignoffCommand(
                kind: .drc,
                toolName: "mock-resource-tool",
                executablePath: executablePath
            ),
            artifactDirectory: root.appending(path: "artifacts")
        )

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("adjacent-resource-loaded"))
        #expect(result.sanitizedCommandLine.first == executablePath)
        #expect(try Data(contentsOf: executable) == original)
        #expect(try Data(contentsOf: result.executableSnapshotURL) == original)
        #expect(!FileManager.default.isExecutableFile(
            atPath: result.executableSnapshotURL.path(percentEncoded: false)
        ))
    }

    @Test func sourceExecutableMutationDuringExecutionFailsDigestVerification() async throws {
        let root = try makeTemporaryRoot("source-executable-mutation")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-mutating-tool",
            in: root,
            contents: """
            #!/bin/sh
            printf '\n# mutated\n' >> "$0"
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        let executablePath = executable.path(percentEncoded: false)

        do {
            _ = try await ExternalSignoffCommandRunner().run(
                command: ExternalSignoffCommand(
                    kind: .drc,
                    toolName: "mock-mutating-tool",
                    executablePath: executablePath
                ),
                artifactDirectory: root.appending(path: "artifacts")
            )
            Issue.record("Expected source executable mutation to fail digest verification.")
        } catch ExternalSignoffCommandError.sourceExecutableDigestMismatch(let producer, let path) {
            #expect(producer.identifier == "mock-mutating-tool")
            #expect(path == executablePath)
        } catch {
            Issue.record("Expected typed source digest mismatch, got \(error).")
        }
    }

    @Test func customLogFileNameCannotEscapeArtifactDirectory() async throws {
        let root = try makeTemporaryRoot("log-path-escape")
        defer { removeTemporaryRoot(root) }

        let marker = root.appending(path: "launched")
        let executable = try writeExecutable(
            named: "mock-escape",
            in: root,
            contents: """
            #!/bin/sh
            touch "\(marker.path(percentEncoded: false))"
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
            _ = try await ExternalSignoffCommandRunner().run(
                command: command,
                artifactDirectory: artifactDirectory
            )
            Issue.record("Expected invalidLogFileName")
        } catch let error as ExternalSignoffCommandError {
            #expect(error == .invalidLogFileName("../escape.log"))
        }
        #expect(!FileManager.default.fileExists(atPath: outsideLog.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test func controlCharactersInCommandMetadataAreRejectedBeforeLaunch() async throws {
        let root = try makeTemporaryRoot("log-header-escape")
        defer { removeTemporaryRoot(root) }

        let marker = root.appending(path: "launched")
        let executable = try writeExecutable(
            named: "mock-header",
            in: root,
            contents: """
            #!/bin/sh
            touch "\(marker.path(percentEncoded: false))"
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

        await #expect(throws: ExternalSignoffCommandError.self) {
            _ = try await ExternalSignoffCommandRunner().run(
                command: command,
                artifactDirectory: artifactDirectory
            )
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test func controlCharactersInArgumentsAreRejectedBeforeLaunch() async throws {
        let root = try makeTemporaryRoot("argument-control-character")
        defer { removeTemporaryRoot(root) }
        let marker = root.appending(path: "launched")
        let executable = try writeExecutable(
            named: "mock-argument-metadata",
            in: root,
            contents: """
            #!/bin/sh
            touch "\(marker.path(percentEncoded: false))"
            exit 0
            """
        )

        await #expect(throws: ExternalSignoffCommandError.self) {
            _ = try await ExternalSignoffCommandRunner().run(
                command: ExternalSignoffCommand(
                    kind: .drc,
                    toolName: "valid-tool-name",
                    executablePath: executable.path(percentEncoded: false),
                    arguments: ["MIN\nSPACE"]
                ),
                artifactDirectory: root.appending(path: "artifacts")
            )
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
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

        let result = try await ExternalSignoffCommandRunner().run(
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

        let batch = try await ExternalSignoffCommandRunner().run(
            commands: commands,
            artifactDirectory: root.appending(path: "artifacts")
        )

        #expect(batch.results.count == 2)
        #expect(batch.review.reports.count == 2)
        #expect(batch.review.passed)
        #expect(!batch.review.isApproved)
        #expect(!batch.review.isReadyForPEX)
        #expect(FileManager.default.fileExists(atPath: batch.evidenceURL.path(percentEncoded: false)))
        let evidence = try JSONDecoder().decode(
            ExternalSignoffExecutionEvidence.self,
            from: Data(contentsOf: batch.evidenceURL)
        )
        #expect(evidence.completedResults == batch.results)
        #expect(evidence.failedCommandIndex == nil)
    }

    @Test func repeatedToolExecutionsRetainDistinctImmutableLogs() async throws {
        let root = try makeTemporaryRoot("repeated-tool")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-repeated",
            in: root,
            contents: """
            #!/bin/sh
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        let command = ExternalSignoffCommand(
            kind: .drc,
            toolName: "repeated-drc",
            executablePath: executable.path(percentEncoded: false)
        )
        let batch = try await ExternalSignoffCommandRunner().run(
            commands: [command, command],
            artifactDirectory: root.appending(path: "artifacts")
        )

        #expect(batch.results.count == 2)
        #expect(batch.results[0].logURL != batch.results[1].logURL)
        #expect(batch.results.allSatisfy {
            FileManager.default.fileExists(atPath: $0.logURL.path(percentEncoded: false))
        })
    }

    @Test func distinctInvocationsDoNotConflictInSharedArtifactDirectory() async throws {
        let root = try makeTemporaryRoot("distinct-invocations")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-distinct-invocations",
            in: root,
            contents: """
            #!/bin/sh
            printf 'argument=%s\n' "$1"
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        let artifactDirectory = root.appending(path: "artifacts")
        let first = try await ExternalSignoffCommandRunner().run(
            command: ExternalSignoffCommand(
                kind: .drc,
                toolName: "shared-tool",
                executablePath: executable.path(percentEncoded: false),
                arguments: ["first"]
            ),
            artifactDirectory: artifactDirectory
        )
        let second = try await ExternalSignoffCommandRunner().run(
            command: ExternalSignoffCommand(
                kind: .drc,
                toolName: "shared-tool",
                executablePath: executable.path(percentEncoded: false),
                arguments: ["second"]
            ),
            artifactDirectory: artifactDirectory
        )

        #expect(first.logURL != second.logURL)
        #expect(first.logURL.pathComponents.contains(".logs"))
        #expect(second.logURL.pathComponents.contains(".logs"))
        #expect(try String(contentsOf: first.logURL, encoding: .utf8).contains("argument=first"))
        #expect(try String(contentsOf: second.logURL, encoding: .utf8).contains("argument=second"))
    }

    @Test func customLogNameIsScopedByImmutableExecutionIdentity() async throws {
        let root = try makeTemporaryRoot("custom-log-execution-identity")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-custom-log",
            in: root,
            contents: """
            #!/bin/sh
            printf 'argument=%s\n' "$1"
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        let artifactDirectory = root.appending(path: "artifacts")
        func command(_ argument: String) -> ExternalSignoffCommand {
            ExternalSignoffCommand(
                kind: .drc,
                toolName: "custom-log-tool",
                executablePath: executable.path(percentEncoded: false),
                arguments: [argument],
                logFileName: "signoff.log"
            )
        }

        let first = try await ExternalSignoffCommandRunner().run(
            command: command("first"),
            artifactDirectory: artifactDirectory
        )
        let second = try await ExternalSignoffCommandRunner().run(
            command: command("second"),
            artifactDirectory: artifactDirectory
        )

        #expect(first.logURL != second.logURL)
        #expect(first.logURL.lastPathComponent == "signoff.log")
        #expect(second.logURL.lastPathComponent == "signoff.log")
        #expect(FileManager.default.fileExists(atPath: first.logURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: second.logURL.path(percentEncoded: false)))
    }

    @Test func distinctSensitiveInvocationsRetainOpaqueConfigurationIdentity() async throws {
        let root = try makeTemporaryRoot("sensitive-execution-identity")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-sensitive-identity",
            in: root,
            contents: """
            #!/bin/sh
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        let firstSecret = "sensitive-invocation-alpha"
        let secondSecret = "sensitive-invocation-beta"
        func command(_ secret: String) -> ExternalSignoffCommand {
            ExternalSignoffCommand(
                kind: .drc,
                toolName: "sensitive-identity-tool",
                executablePath: executable.path(percentEncoded: false),
                arguments: [secret],
                sensitiveArgumentIndexes: [0]
            )
        }

        let first = try await ExternalSignoffCommandRunner().run(
            command: command(firstSecret),
            artifactDirectory: root.appending(path: "artifacts")
        )
        let second = try await ExternalSignoffCommandRunner().run(
            command: command(secondSecret),
            artifactDirectory: root.appending(path: "artifacts")
        )

        #expect(first.logURL != second.logURL)
        let firstDigest = try #require(first.provenance.configurationDigest)
        let secondDigest = try #require(second.provenance.configurationDigest)
        #expect(firstDigest != secondDigest)
        let retained = try JSONEncoder().encode([first, second])
        let retainedText = String(decoding: retained, as: UTF8.self)
        #expect(!retainedText.contains(firstSecret))
        #expect(!retainedText.contains(secondSecret))
    }

    @Test func batchEvidenceAndLogsExcludeDeclaredSensitiveValues() async throws {
        let root = try makeTemporaryRoot("batch-evidence-redaction")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-batch-redaction",
            in: root,
            contents: """
            #!/bin/sh
            printf 'argument=%s environment=%s\n' "$1" "$SIGNOFF_TOKEN"
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        let argumentSecret = "batch-argument-secret-19"
        let environmentSecret = "batch-environment-secret-31"
        let batch = try await ExternalSignoffCommandRunner().run(
            commands: [
                ExternalSignoffCommand(
                    kind: .drc,
                    toolName: "batch-redaction",
                    executablePath: executable.path(percentEncoded: false),
                    arguments: [argumentSecret],
                    sensitiveArgumentIndexes: [0],
                    environment: ["SIGNOFF_TOKEN": environmentSecret],
                    sensitiveEnvironmentKeys: ["SIGNOFF_TOKEN"]
                ),
            ],
            artifactDirectory: root.appending(path: "artifacts")
        )

        let evidenceData = try Data(contentsOf: batch.evidenceURL)
        let evidenceText = String(decoding: evidenceData, as: UTF8.self)
        let logText = try String(contentsOf: batch.results[0].logURL, encoding: .utf8)
        for retainedText in [evidenceText, logText] {
            #expect(!retainedText.contains(argumentSecret))
            #expect(!retainedText.contains(environmentSecret))
            #expect(retainedText.contains("<redacted>"))
        }
    }

    @Test func batchFailureRetainsCompletedAndFailedToolIdentity() async throws {
        let root = try makeTemporaryRoot("partial-batch")
        defer { removeTemporaryRoot(root) }
        let executable = try writeExecutable(
            named: "mock-partial",
            in: root,
            contents: """
            #!/bin/sh
            printf 'SIGNOFF_RESULT status=pass\n'
            exit 0
            """
        )
        do {
            _ = try await ExternalSignoffCommandRunner().run(
                commands: [
                    ExternalSignoffCommand(
                        kind: .drc,
                        toolName: "completed-drc",
                        executablePath: executable.path(percentEncoded: false)
                    ),
                    ExternalSignoffCommand(
                        kind: .lvs,
                        toolName: "failed-lvs",
                        executablePath: executable.path(percentEncoded: false),
                        timeoutSeconds: 0
                    ),
                ],
                artifactDirectory: root.appending(path: "artifacts")
            )
            Issue.record("Expected a typed partial batch failure")
        } catch let error as ExternalSignoffBatchError {
            #expect(error.completedResults.map(\.provenance.producer.identifier) == ["completed-drc"])
            #expect(error.failedProducer?.identifier == "failed-lvs")
            let evidenceURL = try #require(error.evidenceURL)
            let evidenceData = try Data(contentsOf: evidenceURL)
            let evidence = try JSONDecoder().decode(
                ExternalSignoffExecutionEvidence.self,
                from: evidenceData
            )
            #expect(evidence.completedResults.map(\.provenance.producer.identifier) == ["completed-drc"])
            #expect(evidence.failedProducer?.identifier == "failed-lvs")
        }
    }

    @Test func executionEvidenceRejectsUnknownSchemaVersion() throws {
        let data = Data("""
        {"schemaVersion":999,"completedResults":[]}
        """.utf8)
        #expect(throws: ExternalSignoffEvidenceError.unsupportedSchemaVersion(999)) {
            _ = try JSONDecoder().decode(ExternalSignoffExecutionEvidence.self, from: data)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutFailureRedactsSensitiveOutput() async throws {
        try await ProcessTimeoutTestGate.shared.withExclusiveAccess {
            let root = try makeTemporaryRoot("timeout-redaction")
            defer { removeTemporaryRoot(root) }
            let executable = try writeExecutable(
                named: "mock-timeout-redaction",
                in: root,
                contents: """
                #!/bin/sh
                printf 'token=%s\n' "$1"
                exec sleep 30
                """
            )
            let secret = "timeout-secret-88"
            do {
                _ = try await ExternalSignoffCommandRunner().run(
                    command: ExternalSignoffCommand(
                        kind: .drc,
                        toolName: "timeout-redaction-drc",
                        executablePath: executable.path(percentEncoded: false),
                        arguments: [secret],
                        sensitiveArgumentIndexes: [0],
                        timeoutSeconds: 3
                    ),
                    artifactDirectory: root.appending(path: "artifacts")
                )
                Issue.record("Expected timeout")
            } catch let error as ExternalSignoffCommandError {
                guard case .executionFailed(_, let failure) = error,
                      case .timedOut(_, let stdout, _) = failure else {
                    Issue.record("Expected sanitized timeout, got \(error)")
                    return
                }
                #expect(stdout.contains("token=<redacted>"))
                #expect(!stdout.contains(secret))
                let encoded = try JSONEncoder().encode(failure)
                #expect(!String(decoding: encoded, as: UTF8.self).contains(secret))
            }
        }
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
                _ = try await ExternalSignoffCommandRunner().run(
                    command: command,
                    artifactDirectory: root.appending(path: "artifacts")
                )
                Issue.record("Expected timedOut")
            } catch let error as ExternalSignoffCommandError {
                guard case .executionFailed(let producer, let failure) = error,
                      case .timedOut(let timeoutSeconds, let stdout, _) = failure else {
                    Issue.record("Expected timedOut, got \(error)")
                    return
                }
                #expect(producer.identifier == "slow-drc")
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
            .appending(path: "CircuitStudioExternalSignoffCommandRunnerTests-\(name)-\(UUID().uuidString)")
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
