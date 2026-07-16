import Foundation
import Testing
import CircuitSignoff
@testable import SignoffCLICore

@Suite("live signoff CLI integration", .serialized)
struct LiveSignoffCLIIntegrationTests {
    static let enabled = ProcessInfo.processInfo.environment["CIRCUIT_STUDIO_RUN_LIVE_SIGNOFF_TESTS"] == "1"
        && LiveSignoffService.locate() != nil

    @Test(
        "installed toolchain completes a standard-cell signoff",
        .enabled(if: LiveSignoffCLIIntegrationTests.enabled),
        .timeLimit(.minutes(5))
    )
    func standardCellSignoff() async {
        let artifacts = FileManager.default.temporaryDirectory
            .appending(path: "LiveSignoffCLIIntegrationTests-\(UUID().uuidString)")
        let buffer = SignoffCommandOutputBuffer()
        defer { removeSignoffCLITestTemporaryDirectory(artifacts) }

        let status = await SignoffCommand.run(
            arguments: [
                "check",
                "--cell", "sky130_fd_sc_hd__inv_1",
                "--artifacts", artifacts.path(percentEncoded: false),
            ],
            output: buffer.output
        )

        #expect(status == 0)
        #expect(buffer.standardOutput.contains("Result: PASS"))
    }
}
