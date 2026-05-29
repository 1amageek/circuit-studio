import Foundation
import Testing
@testable import CircuitStudioApp

/// Smoke tests for the `signoff` CLI (doctor + check), exercising the built binary
/// end-to-end with explicit exit codes. Gated on the toolchain; builds the
/// executable on demand.
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

    @Test("doctor reports the toolchain ready (exit 0)",
          .enabled(if: SignoffCLITests.available), .timeLimit(.minutes(5)))
    func doctor() throws {
        let (status, output) = try run(try signoffBinary().path, ["doctor"])
        #expect(status == 0)
        #expect(output.contains("Ready."))
    }

    @Test("check by cell name runs the whole flow and passes (exit 0)",
          .enabled(if: SignoffCLITests.available), .timeLimit(.minutes(5)))
    func checkByCellName() throws {
        // Design-by-reference: only a cell name — layout + schematic are derived.
        let (status, output) = try run(try signoffBinary().path, [
            "check", "--cell", "sky130_fd_sc_hd__inv_1", "--rc",
        ])
        #expect(status == 0, "\(output)")
        #expect(output.contains("DRC  [PASS]"))
        #expect(output.contains("LVS  [PASS]"))
        #expect(output.contains("resistors"))   // --rc honored
        #expect(output.contains("Result: PASS"))
    }

    @Test("check emits valid JSON",
          .enabled(if: SignoffCLITests.available), .timeLimit(.minutes(5)))
    func checkJSON() throws {
        let (status, output) = try run(try signoffBinary().path, [
            "check", "--cell", "sky130_fd_sc_hd__inv_1", "--json",
        ])
        #expect(status == 0)
        let data = try #require(output.data(using: .utf8))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["passed"] as? Bool == true)
        #expect((json["pex"] as? [String: Any])?["elements"] != nil)
    }

    @Test("batch check over multiple cells aggregates to an overall result",
          .enabled(if: SignoffCLITests.available), .timeLimit(.minutes(5)))
    func batchCheck() throws {
        let (status, output) = try run(try signoffBinary().path, [
            "check", "--cells", "sky130_fd_sc_hd__inv_1,sky130_fd_sc_hd__dfxtp_1",
        ])
        #expect(status == 0, "\(output)")
        #expect(output.contains("Overall: PASS across 2 cells"))
    }

    @Test("check fails loud on a DRC-violating layout (exit 3)",
          .enabled(if: SignoffCLITests.available), .timeLimit(.minutes(5)))
    func checkViolation() throws {
        let (status, output) = try run(try signoffBinary().path, [
            "check",
            "--layout", fixture("magic/met1_spacing_violation.gds"),
            "--top-cell", "drc_broken",
            "--schematic", fixture("lvs/inv_schematic.spice"),
        ])
        #expect(status == 3)
        #expect(output.contains("met1.2"))
        #expect(output.contains("Result: FAIL"))
    }
}
