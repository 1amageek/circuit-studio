import Foundation
import Testing
@testable import CircuitStudioCore

@Suite("PEXCommandService Tests")
struct PEXCommandServiceTests {

    @Test func runUsesExplicitExecutableAndCapturesOutput() throws {
        let root = try makeTemporaryRoot("run")
        defer { removeTemporaryRoot(root) }

        let executable = try writeExecutable(
            named: "mock-pexengine",
            in: root,
            contents: """
            #!/bin/sh
            printf 'pwd=%s\\n' "$PWD"
            for arg in "$@"; do
              printf 'arg=%s\\n' "$arg"
            done
            printf 'warning output\\n' >&2
            exit 0
            """
        )
        let workingDirectory = root.appending(path: "work")
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let service = PEXCommandService(executablePath: executable.path(percentEncoded: false))
        let result = try service.run(
            arguments: ["doctor", "--json"],
            workingDirectory: workingDirectory
        )

        #expect(result.exitCode == 0)
        #expect(result.workingDirectory == workingDirectory)
        #expect(result.commandLine == [
            executable.path(percentEncoded: false),
            "doctor",
            "--json",
        ])
        #expect(result.standardOutput.contains("\(root.lastPathComponent)/work"))
        #expect(result.standardOutput.contains("arg=doctor"))
        #expect(result.standardOutput.contains("arg=--json"))
        #expect(result.standardError == "warning output\n")
    }

    @Test func extractBuildsExpectedCommandLine() throws {
        let root = try makeTemporaryRoot("extract")
        defer { removeTemporaryRoot(root) }

        let executable = try writeExecutable(
            named: "mock-pexengine",
            in: root,
            contents: """
            #!/bin/sh
            for arg in "$@"; do
              printf '%s\\n' "$arg"
            done
            exit 0
            """
        )
        let configURL = root.appending(path: "pex.json")
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)

        let service = PEXCommandService(executablePath: executable.path(percentEncoded: false))
        let result = try service.extract(
            configURL: configURL,
            workingDirectory: root,
            additionalArguments: ["--json", "--verbose"]
        )

        #expect(result.commandLine == [
            executable.path(percentEncoded: false),
            "extract",
            "--config",
            configURL.path(percentEncoded: false),
            "--json",
            "--verbose",
        ])
        #expect(result.standardOutput == """
        extract
        --config
        \(configURL.path(percentEncoded: false))
        --json
        --verbose

        """)
    }

    @Test func nonZeroExitThrowsTypedErrorWithStderr() throws {
        let root = try makeTemporaryRoot("failure")
        defer { removeTemporaryRoot(root) }

        let executable = try writeExecutable(
            named: "mock-pexengine",
            in: root,
            contents: """
            #!/bin/sh
            printf 'backend failed\\n' >&2
            exit 7
            """
        )

        let service = PEXCommandService(executablePath: executable.path(percentEncoded: false))

        do {
            _ = try service.run(arguments: ["extract"])
            Issue.record("Expected nonZeroExit")
        } catch let error as PEXCommandError {
            guard case .nonZeroExit(let code, let stderr) = error else {
                Issue.record("Expected nonZeroExit, got \(error)")
                return
            }
            #expect(code == 7)
            #expect(stderr == "backend failed\n")
        }
    }

    @Test func invalidExplicitExecutablePathThrowsBeforeLaunch() throws {
        let service = PEXCommandService(executablePath: "/definitely/missing/pexengine")

        do {
            _ = try service.run(arguments: ["doctor"])
            Issue.record("Expected invalidExecutablePath")
        } catch let error as PEXCommandError {
            guard case .invalidExecutablePath(let path) = error else {
                Issue.record("Expected invalidExecutablePath, got \(error)")
                return
            }
            #expect(path == "/definitely/missing/pexengine")
        }
    }

    private func makeTemporaryRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CircuitStudioPEXCommandServiceTests-\(name)-\(UUID().uuidString)")
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
