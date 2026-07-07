import Foundation
import Synchronization

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
  import Darwin
#endif

public struct TimedProcessResult: Sendable, Hashable {
  public let exitCode: Int32
  public let standardOutput: String
  public let standardError: String

  public init(exitCode: Int32, standardOutput: String, standardError: String) {
    self.exitCode = exitCode
    self.standardOutput = standardOutput
    self.standardError = standardError
  }
}

public enum TimedProcessError: Error, LocalizedError, Equatable {
  case invalidConfiguration(String)
  case launchFailed(executablePath: String, message: String)
  case cancelled(
    executablePath: String,
    standardOutput: String,
    standardError: String
  )
  case timedOut(
    executablePath: String,
    timeoutSeconds: Double,
    standardOutput: String,
    standardError: String
  )

  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let message):
      return "Invalid process runner configuration: \(message)"
    case .launchFailed(let executablePath, let message):
      return "Process failed to launch: \(executablePath): \(message)"
    case .cancelled(let executablePath, _, _):
      return "Process was cancelled: \(executablePath)"
    case .timedOut(let executablePath, let timeoutSeconds, _, _):
      return "Process timed out after \(timeoutSeconds)s: \(executablePath)"
    }
  }
}

public struct TimedProcessRunner: Sendable {
  public let timeoutSeconds: Double
  public let terminationGraceSeconds: Double
  public let pipeDrainGraceSeconds: Double
  private static let processTableSnapshotTimeoutSeconds: Double = 0.2
  private static let processTableSnapshotKillWaitSeconds: Double = 0.1

  public init(
    timeoutSeconds: Double = 300,
    terminationGraceSeconds: Double = 2,
    pipeDrainGraceSeconds: Double = 0.25
  ) {
    self.timeoutSeconds = timeoutSeconds
    self.terminationGraceSeconds = terminationGraceSeconds
    self.pipeDrainGraceSeconds = pipeDrainGraceSeconds
  }

  public func run(
    executableURL: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    workingDirectory: URL? = nil
  ) async throws -> TimedProcessResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    process.environment = environment
    return try await run(process: process)
  }

  public func run(
    process: Process,
    shouldCancel: (@Sendable () -> Bool)? = nil
  ) async throws -> TimedProcessResult {
    guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
      throw TimedProcessError.invalidConfiguration("timeoutSeconds must be positive finite seconds")
    }
    guard terminationGraceSeconds.isFinite, terminationGraceSeconds >= 0 else {
      throw TimedProcessError.invalidConfiguration("terminationGraceSeconds must be finite and non-negative")
    }
    guard pipeDrainGraceSeconds.isFinite, pipeDrainGraceSeconds >= 0 else {
      throw TimedProcessError.invalidConfiguration("pipeDrainGraceSeconds must be finite and non-negative")
    }

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    let executablePath = process.executableURL?.path(percentEncoded: false) ?? "<unknown>"
    let timeoutSeconds = timeoutSeconds
    let terminationGraceSeconds = terminationGraceSeconds
    let pipeDrainGraceSeconds = pipeDrainGraceSeconds
    let executionState = TimedProcessExecutionState()

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if Task.isCancelled || executionState.completion.withLock({ $0.didCancel }) {
          let shouldResume = executionState.completion.withLock { completion -> Bool in
            guard !completion.didResume else { return false }
            completion.didCancel = true
            completion.didResume = true
            return true
          }
          guard shouldResume else { return }
          outputPipe.fileHandleForWriting.closeFile()
          errorPipe.fileHandleForWriting.closeFile()
          outputPipe.fileHandleForReading.closeFile()
          errorPipe.fileHandleForReading.closeFile()
          continuation.resume(
            throwing: TimedProcessError.cancelled(
              executablePath: executablePath,
              standardOutput: "",
              standardError: ""
            ))
          return
        }

        let resume: @Sendable (ProcessCompletionSnapshot) -> Void = { snapshot in
          outputPipe.fileHandleForReading.readabilityHandler = nil
          errorPipe.fileHandleForReading.readabilityHandler = nil
          let remainingOutput = Self.drainAvailableData(from: outputPipe.fileHandleForReading)
          let remainingError = Self.drainAvailableData(from: errorPipe.fileHandleForReading)
          if !remainingOutput.isEmpty {
            executionState.standardOutput.withLock { $0.append(remainingOutput) }
          }
          if !remainingError.isEmpty {
            executionState.standardError.withLock { $0.append(remainingError) }
          }
          outputPipe.fileHandleForReading.closeFile()
          errorPipe.fileHandleForReading.closeFile()

          let out = executionState.standardOutput.withLock { $0 }
          let err = executionState.standardError.withLock { $0 }
          let stdout = Self.utf8String(from: out)
          let stderr = Self.utf8String(from: err)

          if snapshot.didCancel {
            continuation.resume(
              throwing: TimedProcessError.cancelled(
                executablePath: executablePath,
                standardOutput: stdout,
                standardError: stderr
              ))
            return
          }

          if snapshot.didTimeout {
            continuation.resume(
              throwing: TimedProcessError.timedOut(
                executablePath: executablePath,
                timeoutSeconds: timeoutSeconds,
                standardOutput: stdout,
                standardError: stderr
              ))
            return
          }

          continuation.resume(
            returning: TimedProcessResult(
              exitCode: snapshot.exitCode,
              standardOutput: stdout,
              standardError: stderr
            ))
        }

        let finalizeIfReady: @Sendable (_ force: Bool) -> Void = { force in
          let snapshot = executionState.completion.withLock {
            completion -> ProcessCompletionSnapshot? in
            guard !completion.didResume else { return nil }
            guard force || completion.isComplete else { return nil }
            completion.didResume = true
            return completion.snapshot
          }
          guard let snapshot else { return }
          resume(snapshot)
        }

        let scheduleForcedFinalize: @Sendable () -> Void = {
          let shouldSchedule = executionState.completion.withLock { completion -> Bool in
            guard !completion.didResume, !completion.forceFinalizeScheduled else { return false }
            completion.forceFinalizeScheduled = true
            return true
          }
          guard shouldSchedule else { return }
          Task.detached {
            do {
              try await Self.sleep(seconds: pipeDrainGraceSeconds)
            } catch {
              return
            }
            finalizeIfReady(true)
          }
        }

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
          let data = handle.availableData
          if data.isEmpty {
            handle.readabilityHandler = nil
            executionState.completion.withLock { $0.stdoutClosed = true }
            finalizeIfReady(false)
          } else {
            executionState.standardOutput.withLock { $0.append(data) }
          }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
          let data = handle.availableData
          if data.isEmpty {
            handle.readabilityHandler = nil
            executionState.completion.withLock { $0.stderrClosed = true }
            finalizeIfReady(false)
          } else {
            executionState.standardError.withLock { $0.append(data) }
          }
        }

        process.terminationHandler = { @Sendable proc in
          executionState.completion.withLock {
            $0.processTerminated = true
            $0.exitCode = proc.terminationStatus
          }
          finalizeIfReady(false)
          scheduleForcedFinalize()
        }

        do {
          try process.run()
          #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            let processGroupID = process.processIdentifier
            if setpgid(processGroupID, processGroupID) == 0 {
              executionState.completion.withLock { $0.processGroupID = processGroupID }
            }
          #endif
        } catch {
          outputPipe.fileHandleForWriting.closeFile()
          errorPipe.fileHandleForWriting.closeFile()
          let shouldResume = executionState.completion.withLock { completion -> Bool in
            guard !completion.didResume else { return false }
            completion.didResume = true
            return true
          }
          if shouldResume {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputPipe.fileHandleForReading.closeFile()
            errorPipe.fileHandleForReading.closeFile()
            continuation.resume(
              throwing: TimedProcessError.launchFailed(
                executablePath: executablePath,
                message: error.localizedDescription
              ))
          }
          return
        }
        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()

        if executionState.completion.withLock({ $0.didCancel }) {
          let processGroupID = executionState.completion.withLock { $0.processGroupID }
          let descendants = Self.terminate(process: process, processGroupID: processGroupID)
          executionState.completion.withLock {
            $0.knownDescendantProcessIDs.formUnion(descendants)
          }
        }

        Task.detached {
          let startedAt = Date()
          do {
            while true {
              try await Self.sleep(seconds: 0.1)
              let shouldStop = executionState.completion.withLock {
                $0.didResume || $0.processTerminated
              }
              if shouldStop { return }

              if executionState.completion.withLock({ $0.didCancel }) {
                let processGroupID = executionState.completion.withLock { $0.processGroupID }
                let descendants = Self.terminate(process: process, processGroupID: processGroupID)
                executionState.completion.withLock {
                  $0.knownDescendantProcessIDs.formUnion(descendants)
                }
                break
              }

              if let shouldCancel, shouldCancel() {
                let processGroupID = executionState.completion.withLock { completion -> pid_t? in
                  completion.didCancel = true
                  return completion.processGroupID
                }
                let descendants = Self.terminate(process: process, processGroupID: processGroupID)
                executionState.completion.withLock {
                  $0.knownDescendantProcessIDs.formUnion(descendants)
                }
                break
              }

              if Date().timeIntervalSince(startedAt) >= timeoutSeconds {
                let processGroupID = executionState.completion.withLock { completion -> pid_t? in
                  completion.didTimeout = true
                  return completion.processGroupID
                }
                let descendants = Self.terminate(process: process, processGroupID: processGroupID)
                executionState.completion.withLock {
                  $0.knownDescendantProcessIDs.formUnion(descendants)
                }
                break
              }
            }
          } catch {
            return
          }

          do {
            try await Self.sleep(seconds: terminationGraceSeconds)
          } catch {
            return
          }
          if executionState.completion.withLock({ $0.didResume }) { return }
          let escalation = executionState.completion.withLock { completion -> (Bool, pid_t?, Set<pid_t>) in
            (
              !completion.didResume && (completion.didCancel || completion.didTimeout),
              completion.processGroupID,
              completion.knownDescendantProcessIDs
            )
          }
          if escalation.0 {
            Self.kill(
              process: process,
              processGroupID: escalation.1,
              knownDescendants: escalation.2
            )
          }
          scheduleForcedFinalize()
        }
      }
    } onCancel: {
      let shouldTerminate = executionState.completion.withLock { completion -> Bool in
        guard !completion.didResume else { return false }
        completion.didCancel = true
        return true
      }
      guard shouldTerminate, process.isRunning else {
        return
      }
      let processGroupID = executionState.completion.withLock { $0.processGroupID }
      let descendants = Self.terminate(process: process, processGroupID: processGroupID)
      executionState.completion.withLock {
        $0.knownDescendantProcessIDs.formUnion(descendants)
      }
    }
  }

  private static func sleep(seconds: Double) async throws {
    let boundedSeconds = max(0, seconds)
    let nanoseconds = UInt64((boundedSeconds * 1_000_000_000).rounded())
    try await Task.sleep(nanoseconds: nanoseconds)
  }

  private static func drainAvailableData(from handle: FileHandle) -> Data {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
      let fileDescriptor = handle.fileDescriptor
      let existingFlags = fcntl(fileDescriptor, F_GETFL)
      if existingFlags >= 0 {
        _ = fcntl(fileDescriptor, F_SETFL, existingFlags | O_NONBLOCK)
      }
      defer {
        if existingFlags >= 0 {
          _ = fcntl(fileDescriptor, F_SETFL, existingFlags)
        }
      }

      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while true {
        let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
          Darwin.read(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
        }
        if readCount > 0 {
          data.append(buffer, count: readCount)
          continue
        }
        if readCount == 0 {
          break
        }
        if errno == EAGAIN || errno == EWOULDBLOCK {
          break
        }
        break
      }
      return data
    #else
      return Data()
    #endif
  }

  @discardableResult
  private static func terminate(process: Process, processGroupID: pid_t?) -> Set<pid_t> {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
      let descendants = signalProcessTree(
        rootPID: process.processIdentifier,
        processGroupID: processGroupID,
        signal: SIGTERM
      )
      if let processGroupID {
        Darwin.kill(-processGroupID, SIGTERM)
      } else {
        process.terminate()
      }
      return descendants
    #else
      process.terminate()
      return []
    #endif
  }

  private static func kill(
    process: Process,
    processGroupID: pid_t?,
    knownDescendants: Set<pid_t>
  ) {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
      signalKnownProcessIDs(knownDescendants, signal: SIGKILL)
      if process.isRunning {
        signalProcessTree(rootPID: process.processIdentifier, processGroupID: processGroupID, signal: SIGKILL)
      }
      if let processGroupID {
        Darwin.kill(-processGroupID, SIGKILL)
      } else if process.isRunning {
        Darwin.kill(process.processIdentifier, SIGKILL)
      }
    #else
      process.terminate()
    #endif
  }

  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    @discardableResult
    private static func signalProcessTree(rootPID: pid_t, processGroupID: pid_t?, signal: Int32) -> Set<pid_t> {
      let descendants = Set(descendantProcessIDs(of: rootPID))
      signalKnownProcessIDs(descendants, signal: signal)
      Darwin.kill(rootPID, signal)
      if let processGroupID {
        Darwin.kill(-processGroupID, signal)
      }
      return descendants
    }

    private static func signalKnownProcessIDs(_ processIDs: Set<pid_t>, signal: Int32) {
      for pid in processIDs {
        Darwin.kill(pid, signal)
      }
    }

    private static func descendantProcessIDs(of rootPID: pid_t) -> [pid_t] {
      let process = Process()
      process.executableURL = URL(filePath: "/bin/ps")
      process.arguments = ["-axo", "pid=,ppid="]
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice

      do {
        try process.run()
      } catch {
        pipe.fileHandleForReading.closeFile()
        return []
      }

      guard waitForProcessExit(process, timeoutSeconds: processTableSnapshotTimeoutSeconds) else {
        Darwin.kill(process.processIdentifier, SIGKILL)
        _ = waitForProcessExit(process, timeoutSeconds: processTableSnapshotKillWaitSeconds)
        pipe.fileHandleForReading.closeFile()
        return []
      }

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      pipe.fileHandleForReading.closeFile()
      let output = Self.utf8String(from: data)
      var childrenByParent: [pid_t: [pid_t]] = [:]
      for line in output.split(whereSeparator: \.isNewline) {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2,
          let pid = pid_t(String(parts[0])),
          let parent = pid_t(String(parts[1]))
        else {
          continue
        }
        childrenByParent[parent, default: []].append(pid)
      }

      var result: [pid_t] = []
      var stack = childrenByParent[rootPID] ?? []
      while let pid = stack.popLast() {
        result.append(pid)
        stack.append(contentsOf: childrenByParent[pid] ?? [])
      }
      return result
    }

    private static func waitForProcessExit(_ process: Process, timeoutSeconds: Double) -> Bool {
      let deadline = Date().addingTimeInterval(timeoutSeconds)
      while process.isRunning && Date() < deadline {
        usleep(10_000)
      }
      return !process.isRunning
    }
  #endif

  private static func utf8String(from data: Data) -> String {
    String(decoding: data, as: UTF8.self)
  }
}

private final class TimedProcessExecutionState: Sendable {
  let standardOutput = Mutex(Data())
  let standardError = Mutex(Data())
  let completion = Mutex(ProcessCompletionState())
}

private struct ProcessCompletionState: Sendable {
  var stdoutClosed = false
  var stderrClosed = false
  var processTerminated = false
  var exitCode: Int32 = 0
  var processGroupID: pid_t?
  var knownDescendantProcessIDs: Set<pid_t> = []
  var didTimeout = false
  var didCancel = false
  var didResume = false
  var forceFinalizeScheduled = false

  var isComplete: Bool {
    stdoutClosed && stderrClosed && processTerminated
  }

  var snapshot: ProcessCompletionSnapshot {
    ProcessCompletionSnapshot(exitCode: exitCode, didTimeout: didTimeout, didCancel: didCancel)
  }
}

private struct ProcessCompletionSnapshot: Sendable {
  let exitCode: Int32
  let didTimeout: Bool
  let didCancel: Bool
}
