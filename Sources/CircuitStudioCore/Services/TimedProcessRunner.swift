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
          let stdout = String(data: out, encoding: .utf8) ?? ""
          let stderr = String(data: err, encoding: .utf8) ?? ""

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
          process.terminate()
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
                process.terminate()
                break
              }

              if let shouldCancel, shouldCancel() {
                executionState.completion.withLock { $0.didCancel = true }
                process.terminate()
                break
              }

              if Date().timeIntervalSince(startedAt) >= timeoutSeconds {
                executionState.completion.withLock { $0.didTimeout = true }
                process.terminate()
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
          if process.isRunning {
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
              kill(process.processIdentifier, SIGKILL)
            #else
              process.terminate()
            #endif
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
      process.terminate()
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
