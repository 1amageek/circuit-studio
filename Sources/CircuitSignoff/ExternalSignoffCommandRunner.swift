import CircuiteFoundation
import CircuiteFoundationCrypto
import Darwin
import Foundation
import SignoffToolSupport

public struct ExternalSignoffCommandRunner: SignoffCommandRunning {
    private let parser: ExternalSignoffReportParser

    public init(parser: ExternalSignoffReportParser = ExternalSignoffReportParser()) {
        self.parser = parser
    }

    public func run(
        command: ExternalSignoffCommand,
        artifactDirectory: URL
    ) async throws -> ExternalSignoffCommandResult {
        try await run(command: command, artifactDirectory: artifactDirectory, executionOrdinal: nil)
    }

    public func run(
        commands: [ExternalSignoffCommand],
        artifactDirectory: URL
    ) async throws -> ExternalSignoffBatchResult {
        var results: [ExternalSignoffCommandResult] = []
        for (index, command) in commands.enumerated() {
            do {
                results.append(try await run(
                    command: command,
                    artifactDirectory: artifactDirectory,
                    executionOrdinal: index
                ))
            } catch let cause as ExternalSignoffCommandError {
                let producer: ProducerIdentity?
                if case .executionFailed(let measuredProducer, _) = cause {
                    producer = measuredProducer
                } else if case .sourceExecutableDigestMismatch(let measuredProducer, _) = cause {
                    producer = measuredProducer
                } else {
                    producer = nil
                }
                let evidenceURL: URL?
                do {
                    evidenceURL = try persistBatchEvidence(
                        completedResults: results,
                        failedCommandIndex: index,
                        failedProducer: producer,
                        sanitizedFailureReason: cause.localizedDescription,
                        artifactDirectory: artifactDirectory
                    )
                } catch let evidenceError as ExternalSignoffCommandError {
                    throw ExternalSignoffBatchError(
                        completedResults: results,
                        failedCommandIndex: index,
                        failedProducer: producer,
                        evidenceURL: nil,
                        cause: .artifactWriteFailed(
                            "Could not retain the sanitized batch failure after '\(cause.localizedDescription)': \(evidenceError.localizedDescription)"
                        )
                    )
                }
                throw ExternalSignoffBatchError(
                    completedResults: results,
                    failedCommandIndex: index,
                    failedProducer: producer,
                    evidenceURL: evidenceURL,
                    cause: cause
                )
            }
        }

        let review = ExternalSignoffReview(reports: results.map(\.report))
        let evidenceURL = try persistBatchEvidence(
            completedResults: results,
            failedCommandIndex: nil,
            failedProducer: nil,
            sanitizedFailureReason: nil,
            artifactDirectory: artifactDirectory
        )
        return ExternalSignoffBatchResult(
            results: results,
            review: review,
            evidenceURL: evidenceURL
        )
    }

    private func run(
        command: ExternalSignoffCommand,
        artifactDirectory: URL,
        executionOrdinal: Int?
    ) async throws -> ExternalSignoffCommandResult {
        let sensitiveArgumentIndexes = try validatedSensitiveArgumentIndexes(command)
        let effectiveEnvironment = ProcessInfo.processInfo.environment.merging(
            command.environment
        ) { _, supplied in supplied }
        try validateSensitiveEnvironmentKeys(
            command,
            effectiveEnvironment: effectiveEnvironment
        )
        let sanitizedArguments = command.arguments.enumerated().map { index, argument in
            sensitiveArgumentIndexes.contains(index) ? "<redacted>" : argument
        }
        let sensitiveValues = sensitiveArgumentIndexes.map { command.arguments[$0] }
            + command.sensitiveEnvironmentKeys.sorted().compactMap { effectiveEnvironment[$0] }
        let retainedLogFileName = try validatedLogFileName(
            command.logFileName,
            sensitiveValues: sensitiveValues
        )
        let executableURL = try validateExecutable(
            path: command.executablePath,
            redacting: sensitiveValues
        )
        let sourceExecutablePath = executableURL.path(percentEncoded: false)
        let retainedExecutablePath = sanitize(sourceExecutablePath, values: sensitiveValues)
        let retainedToolName = sanitize(command.toolName, values: sensitiveValues)
        let retainedWorkingDirectory = command.workingDirectory.map { directory in
            URL(filePath: sanitize(
                directory.standardizedFileURL.path(percentEncoded: false),
                values: sensitiveValues
            ))
        }
        let executableData: Data
        do {
            executableData = try Data(contentsOf: executableURL)
        } catch {
            throw ExternalSignoffCommandError.invalidExecutablePath(retainedExecutablePath)
        }
        let executableDigest = try SHA256ContentDigester().digest(
            data: executableData,
            using: .sha256
        )
        let producer: ProducerIdentity
        do {
            producer = try ProducerIdentity(
                kind: .tool,
                identifier: retainedToolName,
                version: "sha256-\(executableDigest.hexadecimalValue)",
                build: "sha256-\(executableDigest.hexadecimalValue)"
            )
        } catch {
            throw ExternalSignoffCommandError.invalidMetadata(
                sanitize(error.localizedDescription, values: sensitiveValues)
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: artifactDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw ExternalSignoffCommandError.artifactWriteFailed(
                sanitize(error.localizedDescription, values: sensitiveValues)
            )
        }
        let snapshotURL = try executableSnapshotURL(
            data: executableData,
            digest: executableDigest,
            artifactDirectory: artifactDirectory
        )
        let invocation: ExecutionInvocation
        do {
            invocation = try .externalProcess(
                executable: retainedExecutablePath,
                arguments: sanitizedArguments,
                workingDirectory: retainedWorkingDirectory?.path(percentEncoded: false)
            )
        } catch {
            throw ExternalSignoffCommandError.invalidMetadata(
                sanitize(error.localizedDescription, values: sensitiveValues)
            )
        }
        let environment = try executionEnvironmentFingerprint(
            effectiveEnvironment: effectiveEnvironment,
            toolchain: producer.version
        )
        let configurationDigest = try executionConfigurationDigest(
            command: command,
            executableDigest: executableDigest,
            environment: environment
        )
        let startedAt = Date()
        try verifySourceExecutable(
            executableURL,
            expectedDigest: executableDigest,
            producer: producer,
            sanitizedPath: retainedExecutablePath
        )
        let processResult: TimedProcessResult
        do {
            processResult = try await TimedProcessRunner(timeoutSeconds: command.timeoutSeconds).run(
                executableURL: executableURL,
                arguments: command.arguments,
                environment: effectiveEnvironment,
                workingDirectory: command.workingDirectory
            )
        } catch let error as TimedProcessError {
            throw ExternalSignoffCommandError.executionFailed(
                producer: producer,
                failure: sanitizedFailure(error, redacting: sensitiveValues)
            )
        }
        let completedAt = Date()
        try verifySourceExecutable(
            executableURL,
            expectedDigest: executableDigest,
            producer: producer,
            sanitizedPath: retainedExecutablePath
        )
        try verifyExecutableSnapshot(snapshotURL, expectedDigest: executableDigest)

        let stdout = sanitize(processResult.standardOutput, values: sensitiveValues)
        let stderr = sanitize(processResult.standardError, values: sensitiveValues)
        let sanitizedCommandLine = [retainedExecutablePath] + sanitizedArguments
        let logContents = sanitize(renderLog(
            command: command,
            retainedToolName: retainedToolName,
            commandLine: sanitizedCommandLine,
            retainedExecutablePath: retainedExecutablePath,
            retainedWorkingDirectory: retainedWorkingDirectory,
            exitCode: processResult.exitCode,
            stdout: stdout,
            stderr: stderr
        ), values: sensitiveValues)
        let logData = Data(logContents.utf8)
        let executionIdentity = try executionIdentityDigest(
            logData: logData,
            executableDigest: executableDigest,
            environment: environment,
            configurationDigest: configurationDigest
        )
        let logURL = logURL(
            for: command,
            retainedLogFileName: retainedLogFileName,
            retainedToolName: retainedToolName,
            producerDigest: executableDigest.hexadecimalValue,
            executionIdentity: executionIdentity.hexadecimalValue,
            executionOrdinal: executionOrdinal,
            artifactDirectory: artifactDirectory
        )
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw ExternalSignoffCommandError.artifactWriteFailed(
                sanitize(error.localizedDescription, values: sensitiveValues)
            )
        }
        try writeImmutable(logData, to: logURL)

        let report = parser(for: command.parserStyle).parse(
            kind: command.kind,
            toolName: retainedToolName,
            logPath: logURL.path(percentEncoded: false),
            rawOutput: [stdout, stderr].joined(separator: "\n"),
            success: processResult.exitCode == 0
        )
        let provenance = try ExecutionProvenance(
            producer: producer,
            invocation: invocation,
            environment: environment,
            configurationDigest: configurationDigest,
            startedAt: startedAt,
            completedAt: completedAt
        )
        return ExternalSignoffCommandResult(
            sanitizedCommandLine: sanitizedCommandLine,
            sanitizedSourceExecutablePath: retainedExecutablePath,
            executableSnapshotURL: snapshotURL,
            sanitizedWorkingDirectory: retainedWorkingDirectory,
            exitCode: processResult.exitCode,
            standardOutput: stdout,
            standardError: stderr,
            logURL: logURL,
            report: report,
            provenance: provenance
        )
    }

    private func validateExecutable(path: String, redacting sensitiveValues: [String]) throws -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        let executableURL = URL(filePath: expanded).resolvingSymlinksInPath().standardizedFileURL
        let canonicalPath = executableURL.path(percentEncoded: false)
        let resourceValues: URLResourceValues
        do {
            resourceValues = try executableURL.resourceValues(forKeys: [.isRegularFileKey])
        } catch {
            throw ExternalSignoffCommandError.invalidExecutablePath(
                sanitize(path, values: sensitiveValues)
            )
        }
        guard resourceValues.isRegularFile == true else {
            throw ExternalSignoffCommandError.executableIsNotARegularFile(
                sanitize(canonicalPath, values: sensitiveValues)
            )
        }
        guard FileManager.default.isExecutableFile(atPath: canonicalPath) else {
            throw ExternalSignoffCommandError.invalidExecutablePath(
                sanitize(path, values: sensitiveValues)
            )
        }
        return executableURL
    }

    private func validatedSensitiveArgumentIndexes(
        _ command: ExternalSignoffCommand
    ) throws -> Set<Int> {
        var indexes: Set<Int> = []
        for index in command.sensitiveArgumentIndexes {
            guard command.arguments.indices.contains(index) else {
                throw ExternalSignoffCommandError.invalidSensitiveArgumentIndex(
                    index: index,
                    argumentCount: command.arguments.count
                )
            }
            guard indexes.insert(index).inserted else {
                throw ExternalSignoffCommandError.duplicateSensitiveArgumentIndex(index)
            }
        }
        return indexes
    }

    private func validateSensitiveEnvironmentKeys(
        _ command: ExternalSignoffCommand,
        effectiveEnvironment: [String: String]
    ) throws {
        for key in command.sensitiveEnvironmentKeys.sorted() where effectiveEnvironment[key] == nil {
            throw ExternalSignoffCommandError.unknownSensitiveEnvironmentKey(key)
        }
    }

    private func executableSnapshotURL(
        data: Data,
        digest: ContentDigest,
        artifactDirectory: URL
    ) throws -> URL {
        let directory = artifactDirectory
            .appending(path: ".executables", directoryHint: .isDirectory)
            .appending(path: digest.hexadecimalValue, directoryHint: .isDirectory)
        let url = directory.appending(path: "executable", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeImmutable(data, to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o400))],
                ofItemAtPath: url.path(percentEncoded: false)
            )
            let retainedDigest = try SHA256ContentDigester().digest(fileAt: url, using: .sha256)
            guard retainedDigest == digest else {
                throw ExternalSignoffCommandError.artifactWriteFailed(
                    "Executable snapshot digest mismatch at \(url.path(percentEncoded: false))."
                )
            }
            return url
        } catch let error as ExternalSignoffCommandError {
            throw error
        } catch {
            throw ExternalSignoffCommandError.artifactWriteFailed(error.localizedDescription)
        }
    }

    private func verifySourceExecutable(
        _ executableURL: URL,
        expectedDigest: ContentDigest,
        producer: ProducerIdentity,
        sanitizedPath: String
    ) throws {
        let observedDigest: ContentDigest
        do {
            observedDigest = try SHA256ContentDigester().digest(
                fileAt: executableURL,
                using: .sha256
            )
        } catch {
            throw ExternalSignoffCommandError.sourceExecutableDigestMismatch(
                producer: producer,
                path: sanitizedPath
            )
        }
        guard observedDigest == expectedDigest else {
            throw ExternalSignoffCommandError.sourceExecutableDigestMismatch(
                producer: producer,
                path: sanitizedPath
            )
        }
    }

    private func verifyExecutableSnapshot(
        _ snapshotURL: URL,
        expectedDigest: ContentDigest
    ) throws {
        let observedDigest: ContentDigest
        do {
            observedDigest = try SHA256ContentDigester().digest(
                fileAt: snapshotURL,
                using: .sha256
            )
        } catch {
            throw ExternalSignoffCommandError.artifactWriteFailed(
                "Executable evidence snapshot could not be verified at \(snapshotURL.path(percentEncoded: false)): \(error.localizedDescription)"
            )
        }
        guard observedDigest == expectedDigest else {
            throw ExternalSignoffCommandError.artifactWriteFailed(
                "Executable evidence snapshot digest mismatch at \(snapshotURL.path(percentEncoded: false))."
            )
        }
    }

    private func logURL(
        for command: ExternalSignoffCommand,
        retainedLogFileName: String?,
        retainedToolName: String,
        producerDigest: String,
        executionIdentity: String,
        executionOrdinal: Int?,
        artifactDirectory: URL
    ) -> URL {
        let fileName = logFileName(
            for: command,
            retainedLogFileName: retainedLogFileName,
            retainedToolName: retainedToolName,
            producerDigest: producerDigest,
            executionIdentity: executionIdentity,
            executionOrdinal: executionOrdinal
        )
        return artifactDirectory
            .appending(path: ".logs", directoryHint: .isDirectory)
            .appending(path: executionIdentity, directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    private func logFileName(
        for command: ExternalSignoffCommand,
        retainedLogFileName: String?,
        retainedToolName: String,
        producerDigest: String,
        executionIdentity: String,
        executionOrdinal: Int?
    ) -> String {
        if let retainedLogFileName { return retainedLogFileName }
        let safeToolName = safeFileComponent(retainedToolName)
        let ordinal = executionOrdinal.map { "-\($0)" } ?? ""
        return "\(command.kind.rawValue)-\(safeToolName)-\(producerDigest.prefix(16))-\(executionIdentity.prefix(16))\(ordinal).log"
    }

    private func executionIdentityDigest(
        logData: Data,
        executableDigest: ContentDigest,
        environment: ExecutionEnvironmentFingerprint,
        configurationDigest: ContentDigest
    ) throws -> ContentDigest {
        var manifest = Data("external-signoff-execution-v1\0".utf8)
        manifest.append(Data(executableDigest.hexadecimalValue.utf8))
        manifest.append(0)
        if let environmentDigest = environment.environmentDigest {
            manifest.append(Data(environmentDigest.hexadecimalValue.utf8))
        }
        manifest.append(0)
        manifest.append(Data(configurationDigest.hexadecimalValue.utf8))
        manifest.append(0)
        manifest.append(logData)
        return try SHA256ContentDigester().digest(data: manifest, using: .sha256)
    }

    private func executionConfigurationDigest(
        command: ExternalSignoffCommand,
        executableDigest: ContentDigest,
        environment: ExecutionEnvironmentFingerprint
    ) throws -> ContentDigest {
        let fingerprint = ExecutionConfigurationFingerprint(
            kind: command.kind.rawValue,
            executableDigest: executableDigest.hexadecimalValue,
            arguments: command.arguments,
            workingDirectory: command.workingDirectory?.standardizedFileURL.path(
                percentEncoded: false
            ),
            environmentDigest: environment.environmentDigest?.hexadecimalValue,
            sensitiveArgumentIndexes: command.sensitiveArgumentIndexes,
            sensitiveEnvironmentKeys: command.sensitiveEnvironmentKeys.sorted(),
            timeoutBitPattern: command.timeoutSeconds.bitPattern,
            parserStyle: command.parserStyle?.rawValue,
            logFileName: command.logFileName
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try SHA256ContentDigester().digest(
            data: encoder.encode(fingerprint),
            using: .sha256
        )
    }

    private func isSafeLogFileName(_ fileName: String) -> Bool {
        guard !fileName.isEmpty, fileName != ".", fileName != ".." else { return false }
        guard !fileName.contains("/"), !fileName.contains("\\") else { return false }
        return (fileName as NSString).lastPathComponent == fileName
    }

    private func validatedLogFileName(
        _ requestedFileName: String?,
        sensitiveValues: [String]
    ) throws -> String? {
        guard let requestedFileName else { return nil }
        let trimmed = requestedFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let retained = sanitize(trimmed, values: sensitiveValues)
        guard isSafeLogFileName(retained) else {
            throw ExternalSignoffCommandError.invalidLogFileName(retained)
        }
        return retained
    }

    private func safeFileComponent(_ value: String) -> String {
        let sanitized = value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character
                : "-"
        }
        let result = String(sanitized)
        return result.isEmpty ? "tool" : result
    }

    private func parser(for override: ExternalSignoffReportParser.Style?) -> ExternalSignoffReportParser {
        override.map(ExternalSignoffReportParser.init(style:)) ?? parser
    }

    private func sanitizedFailure(
        _ error: TimedProcessError,
        redacting sensitiveValues: [String]
    ) -> ExternalSignoffExecutionFailure {
        switch error {
        case .invalidConfiguration(let message):
            return .invalidRunnerConfiguration(sanitize(message, values: sensitiveValues))
        case .launchFailed(_, let message):
            return .launchFailed(message: sanitize(message, values: sensitiveValues))
        case .cancellationCheckFailed(_, let message, let stdout, let stderr):
            return .cancellationCheckFailed(
                message: sanitize(message, values: sensitiveValues),
                standardOutput: sanitize(stdout, values: sensitiveValues),
                standardError: sanitize(stderr, values: sensitiveValues)
            )
        case .cancelled(_, let stdout, let stderr):
            return .cancelled(
                standardOutput: sanitize(stdout, values: sensitiveValues),
                standardError: sanitize(stderr, values: sensitiveValues)
            )
        case .timedOut(_, let timeoutSeconds, let stdout, let stderr):
            return .timedOut(
                timeoutSeconds: timeoutSeconds,
                standardOutput: sanitize(stdout, values: sensitiveValues),
                standardError: sanitize(stderr, values: sensitiveValues)
            )
        }
    }

    private func sanitize(_ value: String, values: [String]) -> String {
        let secrets = Set(values.filter { !$0.isEmpty }).sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs < rhs
        }
        return secrets.reduce(value) { partialResult, secret in
            partialResult.replacingOccurrences(of: secret, with: "<redacted>")
        }
    }

    private func executionEnvironmentFingerprint(
        effectiveEnvironment: [String: String],
        toolchain: String
    ) throws -> ExecutionEnvironmentFingerprint {
        var manifest = Data()
        for key in effectiveEnvironment.keys.sorted() {
            manifest.append(Data(key.utf8))
            manifest.append(0)
            manifest.append(Data((effectiveEnvironment[key] ?? "").utf8))
            manifest.append(0)
        }
        let digest = try SHA256ContentDigester().digest(data: manifest, using: .sha256)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return try ExecutionEnvironmentFingerprint(
            platform: "macos-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: Self.architecture,
            toolchain: toolchain,
            environmentDigest: digest
        )
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private func renderLog(
        command: ExternalSignoffCommand,
        retainedToolName: String,
        commandLine: [String],
        retainedExecutablePath: String,
        retainedWorkingDirectory: URL?,
        exitCode: Int32,
        stdout: String,
        stderr: String
    ) -> String {
        """
        tool=\(Self.logScalar(retainedToolName))
        kind=\(Self.logScalar(command.kind.rawValue))
        original_executable=\(Self.logScalar(retainedExecutablePath))
        command=\(commandLine.map(Self.logScalar).joined(separator: " "))
        working_directory=\(Self.logScalar(retainedWorkingDirectory?.path(percentEncoded: false) ?? ""))
        exit_code=\(exitCode)

        [stdout]
        \(stdout)
        [stderr]
        \(stderr)
        """
    }

    private static func logScalar(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func persistBatchEvidence(
        completedResults: [ExternalSignoffCommandResult],
        failedCommandIndex: Int?,
        failedProducer: ProducerIdentity?,
        sanitizedFailureReason: String?,
        artifactDirectory: URL
    ) throws -> URL {
        do {
            try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
            let evidence = try ExternalSignoffExecutionEvidence(
                completedResults: completedResults,
                failedCommandIndex: failedCommandIndex,
                failedProducer: failedProducer,
                sanitizedFailureReason: sanitizedFailureReason
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(evidence)
            let digest = try SHA256ContentDigester().digest(data: data, using: .sha256)
            let url = artifactDirectory.appending(
                path: "external-signoff-execution-evidence-\(digest.hexadecimalValue).json"
            )
            try writeImmutable(data, to: url)
            return url
        } catch let error as ExternalSignoffCommandError {
            throw error
        } catch {
            throw ExternalSignoffCommandError.artifactWriteFailed(error.localizedDescription)
        }
    }

    private func writeImmutable(_ data: Data, to url: URL) throws {
        let path = url.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: path) {
            let existing: Data
            do {
                existing = try Data(contentsOf: url)
            } catch {
                throw ExternalSignoffCommandError.artifactWriteFailed(error.localizedDescription)
            }
            guard existing == data else {
                throw ExternalSignoffCommandError.immutableArtifactConflict(path)
            }
            return
        }
        let temporaryURL = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            let linkResult = temporaryURL.path(percentEncoded: false).withCString { source in
                path.withCString { destination in Darwin.link(source, destination) }
            }
            let linkError = errno
            try FileManager.default.removeItem(at: temporaryURL)
            if linkResult == 0 { return }
            if linkError == EEXIST {
                let existing = try Data(contentsOf: url)
                guard existing == data else {
                    throw ExternalSignoffCommandError.immutableArtifactConflict(path)
                }
                return
            }
            throw ExternalSignoffCommandError.artifactWriteFailed(
                "Could not atomically retain \(path) (errno \(linkError))."
            )
        } catch let error as ExternalSignoffCommandError {
            throw error
        } catch {
            if FileManager.default.fileExists(
                atPath: temporaryURL.path(percentEncoded: false)
            ) {
                do {
                    try FileManager.default.removeItem(at: temporaryURL)
                } catch let cleanupError {
                    throw ExternalSignoffCommandError.artifactWriteFailed(
                        "\(error.localizedDescription); temporary artifact cleanup failed: \(cleanupError.localizedDescription)"
                    )
                }
            }
            throw ExternalSignoffCommandError.artifactWriteFailed(error.localizedDescription)
        }
    }

    private struct ExecutionConfigurationFingerprint: Encodable {
        let kind: String
        let executableDigest: String
        let arguments: [String]
        let workingDirectory: String?
        let environmentDigest: String?
        let sensitiveArgumentIndexes: [Int]
        let sensitiveEnvironmentKeys: [String]
        let timeoutBitPattern: UInt64
        let parserStyle: String?
        let logFileName: String?
    }
}
