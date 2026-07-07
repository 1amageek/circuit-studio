import Foundation
import Testing
@testable import SignoffRunner

@Suite("Signoff runner")
struct SignoffRunnerTests {

    @Test("Overall pass requires both clean signoff and successful PEX")
    func overallPassRequiresPEXSuccess() {
        #expect(SignoffRunner.overallPassed(reviewPassed: true, pexError: nil))
        #expect(!SignoffRunner.overallPassed(reviewPassed: true, pexError: "pex failed"))
        #expect(!SignoffRunner.overallPassed(reviewPassed: false, pexError: nil))
        #expect(!SignoffRunner.overallPassed(reviewPassed: false, pexError: "pex failed"))
    }

    @Test("PEX stages the real schematic netlist into artifacts")
    func stagesRealSchematicForPEX() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SignoffRunner-\(UUID().uuidString)")
        let pexDir = root.appending(path: "pex")
        let schematic = root.appending(path: "input.spice")
        try FileManager.default.createDirectory(at: pexDir, withIntermediateDirectories: true)
        defer { removeCoreTestTemporaryDirectory(root) }

        let source = """
        .subckt inv A Y VPWR VGND
        X0 A Y VGND VGND sky130_fd_pr__nfet_01v8
        .ends
        """
        try Data(source.utf8).write(to: schematic)

        let staged = try SignoffRunner.stagePEXSourceNetlist(from: schematic, into: pexDir)
        #expect(staged.lastPathComponent == "pex-source.cir")
        #expect(try String(contentsOf: staged, encoding: .utf8) == source)
    }

    @Test("Batch check isolates each cell under the requested artifact root")
    func batchCheckNamespacesCellArtifacts() throws {
        let base = "/tmp/signoff-artifacts"

        #expect(SignoffRunner.parseCellList(" inv_1, nand2_1 ,, sky130_fd_sc_hd__buf_1 ") == [
            "inv_1",
            "nand2_1",
            "sky130_fd_sc_hd__buf_1",
        ])
        #expect(
            try SignoffRunner.batchCellArtifactDirectory(base: base, cell: "sky130_fd_sc_hd__inv_1")
                == "/tmp/signoff-artifacts/sky130_fd_sc_hd__inv_1"
        )
    }

    @Test("Batch and iterate artifact cell segments reject path traversal")
    func artifactCellSegmentsRejectPathTraversal() throws {
        #expect(try SignoffRunner.artifactPathSegment(forCell: " sky130_fd_sc_hd__inv_1 ") == "sky130_fd_sc_hd__inv_1")

        #expect(throws: SignoffRunner.CLIError.self) {
            _ = try SignoffRunner.artifactPathSegment(forCell: "../escape")
        }
        #expect(throws: SignoffRunner.CLIError.self) {
            _ = try SignoffRunner.artifactPathSegment(forCell: "cells/INV")
        }
        #expect(throws: SignoffRunner.CLIError.self) {
            _ = try SignoffRunner.batchCellArtifactDirectory(base: "/tmp/signoff-artifacts", cell: "..")
        }
    }
}
