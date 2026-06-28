import Foundation
import Testing
import LayoutCore
import LayoutTech
import LayoutIO
@testable import CircuitStudioApp

/// BC3.5 — the full physical deck folded into ONE verdict. ERC, IR drop and EM always run
/// (in-process); DRC, LVS, antenna and density run on the real toolchain when present and are
/// honestly skipped otherwise. A small clean design closes EVERY axis (a genuine full-deck
/// pass, machine-verified); the ACC-4 core's generated antenna protection is checked at scale.
@Suite("Physical signoff deck (full tapeout deck)")
struct PhysicalSignoffDeckTests {

    static let toolchain = MagicAntennaSignoff.locate() != nil && MagicDensitySignoff.locate() != nil

    /// All physical axes a complete tapeout deck must carry.
    static let allAxes: [ConstraintVerdict.Axis] = [.erc, .ir, .em, .drc, .lvs, .antenna, .density]
    static let allBundleAxes: [TapeoutEvidenceBundle.Axis] = [.erc, .ir, .em, .drc, .lvs, .antenna, .density]

    private func synthesize(_ netlist: GateLevelNetlist, into dir: URL) throws -> (gds: URL, spice: URL) {
        let synth = try circuitSynthesizer()
        let doc = try synth.synthesize(netlist)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "\(netlist.name).gds")
        try MaskDataFormatConverter(tech: Sky130LayoutTech.tech()).exportDocument(doc, to: gds, format: .gds)
        let spice = dir.appending(path: "\(netlist.name).spice")
        try synth.referenceSPICE(for: netlist).write(to: spice, atomically: true, encoding: .utf8)
        return (gds, spice)
    }

    @Test("A small clean design closes the ENTIRE physical deck as one verified verdict",
          .enabled(if: PhysicalSignoffDeckTests.toolchain), .timeLimit(.minutes(8)))
    func smallDesignClosesFullDeck() async throws {
        let netlist = GateLevelNetlist.and2(name: "deck_and2")
        let dir = FileManager.default.temporaryDirectory.appending(path: "deck-and2-\(UUID().uuidString)")
        let (gds, spice) = try synthesize(netlist, into: dir)

        let outcome = try await PhysicalSignoffDeck().run(
            netlist: netlist, gds: gds, topCell: netlist.name, schematicNetlist: spice, artifactDirectory: dir)

        // No gated axis was skipped — the whole deck ran.
        #expect(outcome.skippedGatedAxes.isEmpty, "skipped: \(outcome.skippedGatedAxes)")

        // Fold into ONE verdict requiring every physical axis; it must pass.
        let verdict = try MultiConstraintSignoff(requiredAxes: Self.allAxes).combine(outcome.verdicts)
        #expect(verdict.passed, "failing axes: \(verdict.failing.map { ($0.axis, $0.summary) })")

        // The evidence bundle machine-verifies every axis AND that each artifact is on disk.
        let bundle = TapeoutEvidenceBundle(designName: netlist.name, targetClockPeriod: nil,
                                           claims: outcome.claims, gdsPath: gds.path)
        #expect(bundle.closesPresentSignoffAxes())
        try bundle.verify(requiredAxes: Self.allBundleAxes, runDirectory: dir)
        for axis in Self.allBundleAxes {
            #expect(bundle.claim(axis)?.passed == true, "axis \(axis) must pass")
        }
    }

    @Test("Tool-absent: the deck runs ERC/IR/EM and HONESTLY skips the Magic axes (no fake pass)",
          .timeLimit(.minutes(2)))
    func toolIndependentAxesOnly() async throws {
        let netlist = GateLevelNetlist.and2(name: "deck_ti")
        let dir = FileManager.default.temporaryDirectory.appending(path: "deck-ti-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "deck_ti.gds")     // unused when gated tools are off
        let spice = dir.appending(path: "deck_ti.spice")

        let outcome = try await PhysicalSignoffDeck(runGatedTools: false).run(
            netlist: netlist, gds: gds, topCell: netlist.name, schematicNetlist: spice, artifactDirectory: dir)

        let present = Set(outcome.verdicts.map(\.axis))
        #expect(present == Set([.erc, .ir, .em]), "tool-independent axes only; got \(present)")
        #expect(Set(outcome.skippedGatedAxes) == Set([.drc, .lvs, .antenna, .density]))
        let allPass = outcome.verdicts.allSatisfy { $0.passed }
        #expect(allPass, "ERC/IR/EM must pass for a clean small design")

        // Requiring a Magic axis that was honestly not run must FAIL — never a silent pass.
        let bundle = TapeoutEvidenceBundle(designName: netlist.name, targetClockPeriod: nil,
                                           claims: outcome.claims, gdsPath: nil)
        #expect(throws: TapeoutEvidenceBundle.VerificationError.self) {
            try bundle.verify(requiredAxes: Self.allBundleAxes)
        }
    }

    @Test("Scale: the ACC-4 core's generated antenna protection closes the deck's antenna axis",
          .enabled(if: PhysicalSignoffDeckTests.toolchain), .timeLimit(.minutes(8)))
    func acc4AntennaClosedAtScale() async throws {
        // Gate-input met1 risers are same-stage antenna risks. The Sky130 circuit synthesizer
        // now plans and inserts local diffusion ties generically before signoff, so the antenna
        // axis must pass by real Magic evidence.
        let netlist = ACC4CPUGenerator().gateLevelNetlist(name: "deck_acc4")
        let plan = try circuitSynthesizer().antennaProtectionPlan(for: netlist)
        #expect(Set(netlist.inputs).isSubset(of: Set(plan.sites.map(\.net))))
        let dir = FileManager.default.temporaryDirectory.appending(path: "deck-acc4-\(UUID().uuidString)")
        let (gds, _) = try synthesize(netlist, into: dir)

        let antenna = try #require(MagicAntennaSignoff.locate())
        let result = try await ExternalSignoffCommandService(parser: MagicAntennaSignoff.reportParser).run(
            command: antenna.command(cell: netlist.name, gds: gds, artifactDirectory: dir),
            artifactDirectory: dir)
        #expect(result.report.passed,
                "ACC-4 antenna diagnostics: \(result.report.diagnostics.map { ($0.ruleID ?? "?", $0.message) })")

        // Folded into the single verdict, the antenna axis now contributes a real passing claim.
        let verdict = MultiConstraintSignoff.antenna(passed: result.report.passed,
                                                     violationCount: result.report.diagnostics.count,
                                                     evidence: result.report.logPath)
        let folded = try MultiConstraintSignoff(requiredAxes: [.antenna]).combine([verdict])
        #expect(folded.passed)
    }

    private func circuitSynthesizer() throws -> StandardCircuitSynthesizer {
        let profile = try StandardCellLayoutProfileCatalog.loadDefaultProfile()
        let technology = try LayoutTechnologyResource.bundled(resourceName: profile.targetTechnologyResourceName)
        return StandardCircuitSynthesizer(profile: profile, layoutTechnology: technology)
    }
}
