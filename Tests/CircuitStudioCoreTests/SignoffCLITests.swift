import Foundation
import Testing
@testable import CircuitStudioApp

/// Smoke tests for the `signoff` CLI harness, exercising the actual built binary
/// end-to-end (doctor / drc-lvs / failing case → exit codes). Gated on the
/// toolchain; builds the executable on demand (like CoreSpice's trust-gate test).
@Suite("signoff CLI (gated)")
struct SignoffCLITests {

    static let available = LiveSignoffService.locate() != nil

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func run(_ launch: String, _ args: [String], cwd: URL? = nil) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [launch] + args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func signoffBinary() throws -> URL {
        let root = packageRoot()
        let bin = root.appendingPathComponent(".build/debug/signoff")
        if !FileManager.default.fileExists(atPath: bin.path) {
            let (status, output) = try run("swift", ["build", "--product", "signoff"], cwd: root)
            try #require(status == 0, "failed to build signoff:\n\(output)")
        }
        return bin
    }

    private func fixture(_ rel: String) -> String {
        packageRoot().appendingPathComponent("Tests/CircuitStudioCoreTests/Fixtures/\(rel)").path
    }

    @Test("doctor reports the toolchain present (exit 0)",
          .enabled(if: SignoffCLITests.available), .timeLimit(.minutes(5)))
    func doctor() throws {
        let (status, output) = try run(try signoffBinary().path, ["doctor"])
        #expect(status == 0)
        #expect(output.contains("All tools available"))
    }

    @Test("drc-lvs passes on the clean inverter (exit 0)",
          .enabled(if: SignoffCLITests.available), .timeLimit(.minutes(5)))
    func drcLvsClean() throws {
        let (status, output) = try run(try signoffBinary().path, [
            "drc-lvs",
            "--layout", fixture("lvs/inv1.gds"),
            "--top-cell", "sky130_fd_sc_hd__inv_1",
            "--schematic", fixture("lvs/inv_schematic.spice"),
        ])
        #expect(status == 0, "\(output)")
        #expect(output.contains("Result: PASS"))
    }

    @Test("drc-lvs fails loud on a DRC-violating layout (exit 3)",
          .enabled(if: SignoffCLITests.available), .timeLimit(.minutes(5)))
    func drcLvsViolation() throws {
        let (status, output) = try run(try signoffBinary().path, [
            "drc-lvs",
            "--layout", fixture("magic/met1_spacing_violation.gds"),
            "--top-cell", "drc_broken",
            "--schematic", fixture("lvs/inv_schematic.spice"),
        ])
        #expect(status == 3)
        #expect(output.contains("met1.2"))
        #expect(output.contains("Result: FAIL"))
    }
}
