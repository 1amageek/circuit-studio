import Foundation
import Testing
import CoreSpiceEvent
@testable import CircuitStudioCore

@Suite("NgspiceRunner Tests")
struct NgspiceRunnerTests {
    @Test(.timeLimit(.minutes(1)))
    func runTimesOutLongRunningProcess() async throws {
        let root = try makeTemporaryRoot("timeout")
        defer { removeTemporaryRoot(root) }

        let executable = try writeExecutable(
            named: "mock-ngspice",
            in: root,
            contents: """
            #!/bin/sh
            printf 'ngspice mock started\\n'
            exec sleep 30
            """
        )
        let netlist = root.appending(path: "input.spice")
        try "* no-op\n.end\n".write(to: netlist, atomically: true, encoding: .utf8)

        try await ProcessTimeoutTestGate.shared.withExclusiveAccess {
            // The timeout budget must absorb process spawn + shell startup
            // latency under parallel suite load, or the mock is killed
            // before it prints the marker the assertion depends on.
            let runner = NgspiceRunner(
                timeoutSeconds: 3.0,
                terminationGraceSeconds: 0.05,
                executablePath: executable.path(percentEncoded: false),
                concurrencyGate: nil
            )
            do {
                _ = try await runner.run(
                    netlistURL: netlist,
                    rawURL: root.appending(path: "output.raw"),
                    workingDirectory: root,
                    cancellation: CancellationToken()
                )
                Issue.record("Expected simulationFailure timeout")
            } catch let error as StudioError {
                guard case .simulationFailure(let message) = error else {
                    Issue.record("Expected simulationFailure timeout, got \(error)")
                    return
                }
                #expect(message.contains("timed out"))
                #expect(message.contains("ngspice mock started"))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func runDoesNotWaitForInheritedPipeEOFWhenParentExits() async throws {
        let root = try makeTemporaryRoot("pipe-inheritance")
        defer { removeTemporaryRoot(root) }

        let rawURL = root.appending(path: "output.raw")
        let childFinished = root.appending(path: "child-finished")
        let executable = try writeExecutable(
            named: "mock-ngspice-parent-exit",
            in: root,
            contents: """
            #!/usr/bin/env perl
            print "ngspice parent exited\\n";
            open my $raw, ">", "\(rawURL.path(percentEncoded: false))";
            close $raw;
            my $pid = fork();
            if (!defined $pid) {
                exit 2;
            }
            if ($pid == 0) {
                sleep 8;
                open my $fh, ">", "\(childFinished.path(percentEncoded: false))";
                print $fh "done\\n";
                close $fh;
                exit 0;
            }
            exit 0;
            """
        )
        let netlist = root.appending(path: "input.spice")
        try "* no-op\n.end\n".write(to: netlist, atomically: true, encoding: .utf8)

        try await ProcessTimeoutTestGate.shared.withExclusiveAccess {
            let runner = NgspiceRunner(
                timeoutSeconds: 5.0,
                terminationGraceSeconds: 0.05,
                executablePath: executable.path(percentEncoded: false),
                concurrencyGate: nil
            )
            let result = try await runner.run(
                netlistURL: netlist,
                rawURL: rawURL,
                workingDirectory: root,
                cancellation: CancellationToken()
            )

            #expect(result == rawURL)
            #expect(!FileManager.default.fileExists(atPath: childFinished.path(percentEncoded: false)))
        }
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioNgspiceRunnerTests-\(name)-\(UUID().uuidString)")
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
