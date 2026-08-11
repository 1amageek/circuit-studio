import CircuiteFoundation
import CircuiteFoundationCrypto
import Darwin
import Foundation
import SignoffToolSupport

enum CircuitStudioExecutionEnvironmentError: Error, LocalizedError, Equatable {
    case currentExecutableUnavailable
    case executableIsNotARegularFile(String)
    case executableIsNotExecutable(String)
    case executableOpenFailed(path: String, reason: String)
    case executableMetadataUnavailable(path: String, reason: String)
    case executableChangedDuringFingerprint(String)
    case executableCloseFailed(path: String, reason: String)
    case executableCleanupFailed(path: String, primary: String, closeReason: String)
    case architectureUnavailable(Int32)
    case commandLaunchFailed(executable: String, reason: String)
    case commandFailed(executable: String, status: Int32, diagnostic: String)
    case commandOutputIsEmpty(String)

    var errorDescription: String? {
        switch self {
        case .currentExecutableUnavailable:
            "The current process executable could not be identified for provenance."
        case .executableIsNotARegularFile(let path):
            "The provenance executable is not a regular file: \(path)"
        case .executableIsNotExecutable(let path):
            "The provenance executable does not have execute permission: \(path)"
        case .executableOpenFailed(let path, let reason):
            "The provenance executable could not be opened at \(path): \(reason)"
        case .executableMetadataUnavailable(let path, let reason):
            "The provenance executable metadata could not be read for \(path): \(reason)"
        case .executableChangedDuringFingerprint(let path):
            "The provenance executable changed while it was being fingerprinted: \(path)"
        case .executableCloseFailed(let path, let reason):
            "The provenance executable could not be closed at \(path): \(reason)"
        case .executableCleanupFailed(let path, let primary, let closeReason):
            "The provenance executable fingerprint failed at \(path) with '\(primary)', and cleanup also failed: \(closeReason)"
        case .architectureUnavailable(let code):
            "The runtime architecture could not be measured with uname (errno \(code))."
        case .commandLaunchFailed(let executable, let reason):
            "The provenance probe could not launch \(executable): \(reason)"
        case .commandFailed(let executable, let status, let diagnostic):
            "The provenance probe \(executable) exited with status \(status): \(diagnostic)"
        case .commandOutputIsEmpty(let executable):
            "The provenance probe \(executable) returned no identifying output."
        }
    }
}

enum CircuitStudioExecutionEnvironment {
    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> ExecutionEnvironmentFingerprint {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let swiftCompiler = try await swiftCompilerDescription()
        return try ExecutionEnvironmentFingerprint(
            platform: "macos-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: try runtimeArchitecture(),
            toolchain: swiftCompiler,
            environmentDigest: try environmentDigest(environment)
        )
    }

    static func producerIdentity(
        kind: ProducerKind,
        identifier: String
    ) async throws -> ProducerIdentity {
        try await Task.detached {
            try producerIdentitySynchronously(
                kind: kind,
                identifier: identifier,
                executableURL: currentExecutableURL()
            )
        }.value
    }

    static func producerIdentity(
        kind: ProducerKind,
        identifier: String,
        executablePath: String
    ) async throws -> ProducerIdentity {
        try await Task.detached {
            try producerIdentitySynchronously(
                kind: kind,
                identifier: identifier,
                executableURL: URL(filePath: executablePath)
            )
        }.value
    }

    private static func producerIdentitySynchronously(
        kind: ProducerKind,
        identifier: String,
        executableURL: URL
    ) throws -> ProducerIdentity {
        let path = executableURL.standardizedFileURL.path(percentEncoded: false)
        let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw CircuitStudioExecutionEnvironmentError.executableOpenFailed(
                path: path,
                reason: currentPOSIXErrorDescription()
            )
        }

        let measuredVersion: String
        do {
            let initialSnapshot = try executableSnapshot(
                descriptor: descriptor,
                path: path
            )
            guard initialSnapshot.isRegularFile else {
                throw CircuitStudioExecutionEnvironmentError.executableIsNotARegularFile(path)
            }
            guard initialSnapshot.hasExecutePermission else {
                throw CircuitStudioExecutionEnvironmentError.executableIsNotExecutable(path)
            }
            let digest = try executableDigest(
                descriptor: descriptor,
                byteCount: initialSnapshot.byteCount
            )
            let finalSnapshot = try executableSnapshot(
                descriptor: descriptor,
                path: path
            )
            guard finalSnapshot == initialSnapshot else {
                throw CircuitStudioExecutionEnvironmentError.executableChangedDuringFingerprint(path)
            }
            measuredVersion = "sha256-\(digest.hexadecimalValue)"
        } catch {
            let primary = error
            guard Darwin.close(descriptor) == 0 else {
                throw CircuitStudioExecutionEnvironmentError.executableCleanupFailed(
                    path: path,
                    primary: String(describing: primary),
                    closeReason: currentPOSIXErrorDescription()
                )
            }
            throw primary
        }
        guard Darwin.close(descriptor) == 0 else {
            throw CircuitStudioExecutionEnvironmentError.executableCloseFailed(
                path: path,
                reason: currentPOSIXErrorDescription()
            )
        }
        return try ProducerIdentity(
            kind: kind,
            identifier: identifier,
            version: measuredVersion,
            build: measuredVersion
        )
    }

    private static func executableSnapshot(
        descriptor: Int32,
        path: String
    ) throws -> ExecutableSnapshot {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            throw CircuitStudioExecutionEnvironmentError.executableMetadataUnavailable(
                path: path,
                reason: currentPOSIXErrorDescription()
            )
        }
        guard metadata.st_size >= 0 else {
            throw CircuitStudioExecutionEnvironmentError.executableMetadataUnavailable(
                path: path,
                reason: "The executable has a negative byte count."
            )
        }
        return ExecutableSnapshot(metadata: metadata)
    }

    private static func executableDigest(
        descriptor: Int32,
        byteCount: UInt64
    ) throws -> ContentDigest {
        let maximumChunkByteCount: UInt64 = 1_048_576
        let updateCount = byteCount == 0
            ? 0
            : (byteCount - 1) / maximumChunkByteCount + 1
        let limits = try ContentDigestSessionLimits(
            maximumChunkByteCount: maximumChunkByteCount,
            maximumTotalByteCount: max(byteCount, 1),
            maximumUpdateCount: max(updateCount, 1)
        )
        return try SHA256ContentDigester().digest(
            using: .sha256,
            limits: limits
        ) { (lease: borrowing ContentDigestUpdateLease) throws(ContentDigestError) in
            var offset: UInt64 = 0
            while offset < byteCount {
                let requestedByteCount = min(
                    maximumChunkByteCount,
                    byteCount - offset
                )
                guard requestedByteCount <= UInt64(Int.max),
                      offset <= UInt64(Int64.max) else {
                    throw ContentDigestError.backendUpdateFailed(
                        reason: "The executable exceeds the platform read range."
                    )
                }
                var bytes = [UInt8](
                    repeating: 0,
                    count: Int(requestedByteCount)
                )
                let readByteCount = bytes.withUnsafeMutableBytes { buffer in
                    Darwin.pread(
                        descriptor,
                        buffer.baseAddress,
                        buffer.count,
                        off_t(offset)
                    )
                }
                guard readByteCount >= 0 else {
                    throw ContentDigestError.backendUpdateFailed(
                        reason: currentPOSIXErrorDescription()
                    )
                }
                guard readByteCount == bytes.count else {
                    throw ContentDigestError.backendUpdateFailed(
                        reason: "The executable produced a short read: expected \(bytes.count), received \(readByteCount)."
                    )
                }
                try lease.update(bytes)
                offset += requestedByteCount
            }
        }.digest
    }

    private static func currentPOSIXErrorDescription() -> String {
        String(cString: strerror(errno))
    }

    private static func currentExecutableURL() throws -> URL {
        if let executableURL = Bundle.main.executableURL {
            return executableURL
        }
        guard let argument = ProcessInfo.processInfo.arguments.first,
              !argument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CircuitStudioExecutionEnvironmentError.currentExecutableUnavailable
        }
        return URL(filePath: argument)
    }

    private static func runtimeArchitecture() throws -> String {
        var systemInformation = utsname()
        guard uname(&systemInformation) == 0 else {
            throw CircuitStudioExecutionEnvironmentError.architectureUnavailable(errno)
        }
        let capacity = MemoryLayout.size(ofValue: systemInformation.machine)
        return withUnsafePointer(to: &systemInformation.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }

    private static func environmentDigest(
        _ environment: [String: String]
    ) throws -> ContentDigest {
        var manifest = Data()
        for key in environment.keys.sorted() {
            manifest.append(Data(key.utf8))
            manifest.append(0)
            manifest.append(Data((environment[key] ?? "").utf8))
            manifest.append(0)
        }
        return try SHA256ContentDigester().digest(data: manifest, using: .sha256)
    }

    private static func swiftCompilerDescription() async throws -> String {
        let xcrunURL = URL(filePath: "/usr/bin/xcrun")
        let compilerPath = try await run(executableURL: xcrunURL, arguments: ["--find", "swiftc"])
        return try await run(
            executableURL: URL(filePath: compilerPath),
            arguments: ["--version"]
        )
    }

    private static func run(executableURL: URL, arguments: [String]) async throws -> String {
        let result: TimedProcessResult
        do {
            result = try await TimedProcessRunner(timeoutSeconds: 10).run(
                executableURL: executableURL,
                arguments: arguments
            )
        } catch {
            throw CircuitStudioExecutionEnvironmentError.commandLaunchFailed(
                executable: executableURL.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }
        guard result.exitCode == 0 else {
            let diagnostic = normalizedOutput(result.standardError) ?? "no diagnostic output"
            throw CircuitStudioExecutionEnvironmentError.commandFailed(
                executable: executableURL.path(percentEncoded: false),
                status: result.exitCode,
                diagnostic: diagnostic
            )
        }
        guard let normalized = normalizedOutput(result.standardOutput) else {
            throw CircuitStudioExecutionEnvironmentError.commandOutputIsEmpty(
                executableURL.path(percentEncoded: false)
            )
        }
        return normalized
    }

    private static func normalizedOutput(_ value: String) -> String? {
        let normalized = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}

private struct ExecutableSnapshot: Equatable {
    let device: dev_t
    let inode: ino_t
    let byteCount: UInt64
    let mode: mode_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    var isRegularFile: Bool {
        mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    }

    var hasExecutePermission: Bool {
        mode & mode_t(S_IXUSR | S_IXGRP | S_IXOTH) != 0
    }

    init(metadata: stat) {
        device = metadata.st_dev
        inode = metadata.st_ino
        byteCount = UInt64(metadata.st_size)
        mode = metadata.st_mode
        modifiedSeconds = metadata.st_mtimespec.tv_sec
        modifiedNanoseconds = metadata.st_mtimespec.tv_nsec
        changedSeconds = metadata.st_ctimespec.tv_sec
        changedNanoseconds = metadata.st_ctimespec.tv_nsec
    }
}
