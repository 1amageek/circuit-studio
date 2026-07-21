import CircuiteFoundation
import Darwin
import Foundation
import SignoffToolSupport

enum CircuitStudioExecutionEnvironmentError: Error, LocalizedError, Equatable {
    case currentExecutableUnavailable
    case executableIsNotARegularFile(String)
    case executableIsNotExecutable(String)
    case executableMetadataUnavailable(path: String, reason: String)
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
        case .executableMetadataUnavailable(let path, let reason):
            "The provenance executable metadata could not be read for \(path): \(reason)"
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
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw CircuitStudioExecutionEnvironmentError.executableIsNotARegularFile(path)
        }
        let resourceValues: URLResourceValues
        do {
            resourceValues = try executableURL.resourceValues(forKeys: [.isRegularFileKey])
        } catch {
            throw CircuitStudioExecutionEnvironmentError.executableMetadataUnavailable(
                path: path,
                reason: error.localizedDescription
            )
        }
        guard resourceValues.isRegularFile == true else {
            throw CircuitStudioExecutionEnvironmentError.executableIsNotARegularFile(path)
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw CircuitStudioExecutionEnvironmentError.executableIsNotExecutable(path)
        }
        let digest = try SHA256ContentDigester()
            .digest(fileAt: executableURL, using: .sha256)
            .hexadecimalValue
        let measuredVersion = "sha256-\(digest)"
        return try ProducerIdentity(
            kind: kind,
            identifier: identifier,
            version: measuredVersion,
            build: measuredVersion
        )
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
