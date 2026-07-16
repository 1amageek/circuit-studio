import Foundation
import Testing
@testable import SignoffCLICore

@Suite("Signoff runner")
struct SignoffRunnerTests {

    @Test("Help dispatches through the command core")
    func helpDispatchesThroughCommandCore() async {
        let buffer = SignoffCommandOutputBuffer()

        let status = await SignoffCommand.run(
            arguments: ["--help"],
            output: buffer.output
        )

        #expect(status == 0)
        #expect(buffer.standardOutput.contains("Usage:"))
        #expect(buffer.standardError.isEmpty)
    }

    @Test("Unknown commands return a usage error through the injected output")
    func unknownCommandReturnsUsageError() async {
        let buffer = SignoffCommandOutputBuffer()

        let status = await SignoffCommand.run(
            arguments: ["unknown"],
            output: buffer.output
        )

        #expect(status == 1)
        #expect(buffer.standardOutput.contains("Usage:"))
        #expect(buffer.standardError.contains("unknown command 'unknown'"))
    }

    @Test("Overall pass requires both clean signoff and successful PEX")
    func overallPassRequiresPEXSuccess() {
        #expect(SignoffCommand.overallPassed(reviewPassed: true, pexError: nil))
        #expect(!SignoffCommand.overallPassed(reviewPassed: true, pexError: "pex failed"))
        #expect(!SignoffCommand.overallPassed(reviewPassed: false, pexError: nil))
        #expect(!SignoffCommand.overallPassed(reviewPassed: false, pexError: "pex failed"))
    }

    @Test("PEX stages the real schematic netlist into artifacts")
    func stagesRealSchematicForPEX() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SignoffRunner-\(UUID().uuidString)")
        let pexDir = root.appending(path: "pex")
        let schematic = root.appending(path: "input.spice")
        try FileManager.default.createDirectory(at: pexDir, withIntermediateDirectories: true)
        defer { removeSignoffCLITestTemporaryDirectory(root) }

        let source = """
        .subckt inv A Y VPWR VGND
        X0 A Y VGND VGND sky130_fd_pr__nfet_01v8
        .ends
        """
        try Data(source.utf8).write(to: schematic)

        let staged = try SignoffCommand.stagePEXSourceNetlist(from: schematic, into: pexDir)
        #expect(staged.lastPathComponent == "pex-source.cir")
        #expect(try String(contentsOf: staged, encoding: .utf8) == source)
    }

    @Test("Batch check isolates each cell under the requested artifact root")
    func batchCheckNamespacesCellArtifacts() throws {
        let base = "/tmp/signoff-artifacts"

        #expect(SignoffCommand.parseCellList(" inv_1, nand2_1 ,, sky130_fd_sc_hd__buf_1 ") == [
            "inv_1",
            "nand2_1",
            "sky130_fd_sc_hd__buf_1",
        ])
        #expect(
            try SignoffCommand.batchCellArtifactDirectory(base: base, cell: "sky130_fd_sc_hd__inv_1")
                == "/tmp/signoff-artifacts/sky130_fd_sc_hd__inv_1"
        )
    }

    @Test("Batch and iterate artifact cell segments reject path traversal")
    func artifactCellSegmentsRejectPathTraversal() throws {
        #expect(try SignoffCommand.artifactPathSegment(forCell: " sky130_fd_sc_hd__inv_1 ") == "sky130_fd_sc_hd__inv_1")

        #expect(throws: SignoffCommand.CLIError.self) {
            _ = try SignoffCommand.artifactPathSegment(forCell: "../escape")
        }
        #expect(throws: SignoffCommand.CLIError.self) {
            _ = try SignoffCommand.artifactPathSegment(forCell: "cells/INV")
        }
        #expect(throws: SignoffCommand.CLIError.self) {
            _ = try SignoffCommand.batchCellArtifactDirectory(base: "/tmp/signoff-artifacts", cell: "..")
        }
    }
}
