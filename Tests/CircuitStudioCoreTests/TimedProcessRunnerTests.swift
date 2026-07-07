import Foundation
import Testing

@testable import CircuitStudioCore

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
  import Darwin
#endif

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

  @Test(.timeLimit(.minutes(1)))
  func timeoutTerminatesChildProcessThatIgnoresSIGTERM() async throws {
    try await ProcessTimeoutTestGate.shared.withExclusiveAccess {
      let root = try makeTemporaryRoot("child-sigkill-escalation")
      defer { removeTemporaryRoot(root) }

      let executable = try writeExecutable(
        named: "ignore-term-with-child",
        in: root,
        contents: """
          #!/bin/sh
          trap '' TERM
          (trap '' TERM; while true; do sleep 1; done) &
          echo child=$!
          while true; do sleep 1; done
          """
      )

      var childPID: pid_t?
      do {
        _ = try await TimedProcessRunner(
          timeoutSeconds: 0.2,
          terminationGraceSeconds: 0.05,
          pipeDrainGraceSeconds: 0.05
        ).run(executableURL: executable)
        Issue.record("Process should have timed out.")
      } catch let error as TimedProcessError {
        guard case .timedOut(_, _, let standardOutput, _) = error else {
          Issue.record("Expected timeout, got \(error).")
          return
        }
        childPID = parseChildPID(from: standardOutput)
      }

      let pid = try #require(childPID)
      let exited = await waitForProcessExit(pid, timeoutSeconds: 2.0)
      if !exited {
        forceKill(pid)
      }
      #expect(exited)
    }
  }

  @Test
  func invalidTimeoutConfigurationThrowsBeforeLaunch() async throws {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/true")

    var didThrowExpectedError = false
    do {
      _ = try await TimedProcessRunner(timeoutSeconds: .nan).run(process: process)
    } catch let error as TimedProcessError {
      didThrowExpectedError = error == .invalidConfiguration("timeoutSeconds must be positive finite seconds")
    } catch {
      throw error
    }

    #expect(didThrowExpectedError)
    #expect(!process.isRunning)
  }

  @Test(.timeLimit(.minutes(1)))
  func parentTaskCancellationTerminatesRunningProcess() async throws {
    try await ProcessTimeoutTestGate.shared.withExclusiveAccess {
      let root = try makeTemporaryRoot("task-cancellation")
      defer { removeTemporaryRoot(root) }

      let started = root.appending(path: "started")
      let terminated = root.appending(path: "terminated")
      let executable = try writeExecutable(
        named: "cancel-aware-child",
        in: root,
        contents: """
          #!/usr/bin/env perl
          $SIG{TERM} = sub {
              open my $fh, ">", "\(terminated.path(percentEncoded: false))";
              print $fh "terminated\\n";
              close $fh;
              exit 0;
          };
          open my $fh, ">", "\(started.path(percentEncoded: false))";
          print $fh "started\\n";
          close $fh;
          while (1) {
              sleep 1;
          }
          """
      )

      let task = Task {
        try await TimedProcessRunner(
          timeoutSeconds: 10.0,
          terminationGraceSeconds: 0.05,
          pipeDrainGraceSeconds: 0.05
        ).run(executableURL: executable)
      }

      #expect(await waitForFile(started, timeoutSeconds: 2.0))
      task.cancel()

      do {
        _ = try await task.value
        Issue.record("Process should have been cancelled.")
      } catch let error as TimedProcessError {
        guard case .cancelled = error else {
          Issue.record("Expected cancellation, got \(error).")
          return
        }
      }

      #expect(await waitForFile(terminated, timeoutSeconds: 2.0))
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

  private func parseChildPID(from standardOutput: String) -> pid_t? {
    for line in standardOutput.split(whereSeparator: \.isNewline) {
      guard line.hasPrefix("child=") else { continue }
      return pid_t(String(line.dropFirst("child=".count)))
    }
    return nil
  }

  private func isProcessAlive(_ pid: pid_t) -> Bool {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
      if Darwin.kill(pid, 0) == 0 {
        return true
      }
      return errno == EPERM
    #else
      return false
    #endif
  }

  private func waitForProcessExit(_ pid: pid_t, timeoutSeconds: Double) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
      if !isProcessAlive(pid) {
        return true
      }
      do {
        try await Task.sleep(nanoseconds: 50_000_000)
      } catch {
        return !isProcessAlive(pid)
      }
    }
    return !isProcessAlive(pid)
  }

  private func forceKill(_ pid: pid_t) {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
      Darwin.kill(pid, SIGKILL)
    #endif
  }

  private func waitForFile(_ url: URL, timeoutSeconds: Double) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
      if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
        return true
      }
      do {
        try await Task.sleep(nanoseconds: 20_000_000)
      } catch {
        return false
      }
    }
    return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
  }
}
