import Foundation
import Testing
@testable import CircuitStudioCore

@Suite("TimedProcessRunner Tests")
struct TimedProcessRunnerTests {
    @Test(.timeLimit(.minutes(1)))
    func parentExitDoesNotWaitForInheritedPipeEOF() async throws {
        try await ProcessTimeoutTestGate.shared.withExclusiveAccess {
            let root = try makeTemporaryRoot("pipe-inheritance")
            defer { removeTemporaryRoot(root) }

            let childFinished = root.appending(path: "child-finished")
            let executable = try writeExecutable(
                named: "mock-parent-exit",
                in: root,
                contents: """
                #!/usr/bin/env perl
                print "parent-exited\\n";
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

            let result = try await TimedProcessRunner(
                timeoutSeconds: 5.0,
                terminationGraceSeconds: 0.05,
                pipeDrainGraceSeconds: 0.05
            ).run(executableURL: executable)

            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("parent-exited"))
            #expect(!FileManager.default.fileExists(atPath: childFinished.path(percentEncoded: false)))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutEscalatesPastIgnoredSIGTERM() async throws {
        try await ProcessTimeoutTestGate.shared.withExclusiveAccess {
            let root = try makeTemporaryRoot("sigkill-escalation")
            defer { removeTemporaryRoot(root) }

            let executable = try writeExecutable(
                named: "ignore-term",
                in: root,
                contents: """
                #!/usr/bin/env perl
                $SIG{TERM} = sub {};
                $| = 1;
                print "started\\n";
                while (1) {
                    sleep 1;
                }
                """
            )

            do {
                _ = try await TimedProcessRunner(
                    timeoutSeconds: 0.2,
                    terminationGraceSeconds: 0.05,
                    pipeDrainGraceSeconds: 0.05
                ).run(executableURL: executable)
                Issue.record("Process should have timed out.")
            } catch let error as TimedProcessError {
                guard case .timedOut = error else {
                    Issue.record("Expected timeout, got \(error).")
                    return
                }
            }
        }
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioTimedProcessRunnerTests-\(name)-\(UUID().uuidString)")
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
