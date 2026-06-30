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
}
