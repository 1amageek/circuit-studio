import Foundation
import Synchronization
import Testing
@testable import SignoffCLICore

@Suite("signoff command core", .serialized)
struct SignoffCLITests {
    private enum FixtureError: Error {
        case missingResource(String)
    }

    private func fixture(_ relativePath: String) throws -> String {
        let path = relativePath as NSString
        let directory = path.deletingLastPathComponent
        let fileName = path.lastPathComponent as NSString
        let resourceName = fileName.deletingPathExtension
        let resourceExtension = fileName.pathExtension
        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: directory
        ) else {
            throw FixtureError.missingResource(relativePath)
        }
        return url.path(percentEncoded: false)
    }

    private func temporaryArtifactDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "SignoffCommandCoreTests-\(UUID().uuidString)")
    }

    @Test("doctor reports the toolchain ready", .timeLimit(.minutes(1)))
    func doctor() async {
        let buffer = SignoffCommandOutputBuffer()
        let status = await SignoffCommand.run(
            arguments: ["doctor"],
            output: buffer.output,
            runtime: DeterministicSignoffCommandRuntime()
        )
        #expect(status == 0)
        #expect(buffer.standardOutput.contains("Ready."))
    }

    @Test("check by cell name runs the whole flow", .timeLimit(.minutes(1)))
    func checkByCellName() async {
        let artifactDirectory = temporaryArtifactDirectory()
        let buffer = SignoffCommandOutputBuffer()
        defer { removeSignoffCLITestTemporaryDirectory(artifactDirectory) }

        let status = await SignoffCommand.run(arguments: [
            "check",
            "--cell", "sky130_fd_sc_hd__inv_1",
            "--rc",
            "--artifacts", artifactDirectory.path(percentEncoded: false),
        ], output: buffer.output, runtime: DeterministicSignoffCommandRuntime())
        #expect(status == 0)
        #expect(buffer.standardOutput.contains("DRC  [PASS]"))
        #expect(buffer.standardOutput.contains("LVS  [PASS]"))
        #expect(buffer.standardOutput.contains("resistors"))
        #expect(buffer.standardOutput.contains("Result: PASS"))
    }

    @Test("check supports machine-readable output mode", .timeLimit(.minutes(1)))
    func checkJSON() async throws {
        let artifactDirectory = temporaryArtifactDirectory()
        let buffer = SignoffCommandOutputBuffer()
        defer { removeSignoffCLITestTemporaryDirectory(artifactDirectory) }

        let status = await SignoffCommand.run(arguments: [
            "check",
            "--cell", "sky130_fd_sc_hd__inv_1",
            "--json",
            "--artifacts", artifactDirectory.path(percentEncoded: false),
        ], output: buffer.output, runtime: DeterministicSignoffCommandRuntime())
        #expect(status == 0)
        let data = Data(buffer.standardOutput.utf8)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["passed"] as? Bool == true)
        #expect((json["pex"] as? [String: Any])?["elements"] != nil)
    }

    @Test("batch check aggregates multiple cells", .timeLimit(.minutes(1)))
    func batchCheck() async {
        let artifactDirectory = temporaryArtifactDirectory()
        let buffer = SignoffCommandOutputBuffer()
        defer { removeSignoffCLITestTemporaryDirectory(artifactDirectory) }

        let status = await SignoffCommand.run(arguments: [
            "check",
            "--cells", "sky130_fd_sc_hd__inv_1,sky130_fd_sc_hd__dfxtp_1",
            "--artifacts", artifactDirectory.path(percentEncoded: false),
        ], output: buffer.output, runtime: DeterministicSignoffCommandRuntime())
        #expect(status == 0)
        #expect(buffer.standardOutput.contains("Overall: PASS across 2 cells"))
    }

    @Test("iterate converges on a passing candidate", .timeLimit(.minutes(1)))
    func iterateConverges() async {
        let artifactDirectory = temporaryArtifactDirectory()
        let buffer = SignoffCommandOutputBuffer()
        defer { removeSignoffCLITestTemporaryDirectory(artifactDirectory) }

        let status = await SignoffCommand.run(arguments: [
            "iterate",
            "--cells", "sky130_fd_sc_hd__inv_1,sky130_fd_sc_hd__dfxtp_1",
            "--artifacts", artifactDirectory.path(percentEncoded: false),
        ], output: buffer.output, runtime: DeterministicSignoffCommandRuntime())
        #expect(status == 0)
        #expect(buffer.standardOutput.contains("Converged"))
        #expect(buffer.standardOutput.contains("iter 0"))
    }

    @Test("check returns design-failure status for a DRC violation", .timeLimit(.minutes(1)))
    func checkViolation() async throws {
        let artifactDirectory = temporaryArtifactDirectory()
        let buffer = SignoffCommandOutputBuffer()
        defer { removeSignoffCLITestTemporaryDirectory(artifactDirectory) }

        let status = await SignoffCommand.run(arguments: [
            "check",
            "--layout", try fixture("magic/met1_spacing_violation.gds"),
            "--top-cell", "drc_broken",
            "--schematic", try fixture("lvs/inv_schematic.spice"),
            "--artifacts", artifactDirectory.path(percentEncoded: false),
        ], output: buffer.output, runtime: DeterministicSignoffCommandRuntime())
        #expect(status == 3)
        #expect(buffer.standardOutput.contains("met1.2"))
        #expect(buffer.standardOutput.contains("Result: FAIL"))
    }
}

final class SignoffCommandOutputBuffer: Sendable {
    private struct State: Sendable {
        var standardOutput = ""
        var standardError = ""
    }

    private let state = Mutex(State())

    var output: SignoffCommandOutput {
        SignoffCommandOutput(
            standardOutput: { [self] message in
                state.withLock { $0.standardOutput.append(message) }
            },
            standardError: { [self] message in
                state.withLock { $0.standardError.append(message) }
            }
        )
    }

    var standardOutput: String {
        state.withLock { $0.standardOutput }
    }

    var standardError: String {
        state.withLock { $0.standardError }
    }
}
