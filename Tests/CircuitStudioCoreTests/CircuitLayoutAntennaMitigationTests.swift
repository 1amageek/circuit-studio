import Foundation
import CircuitPhysicalDesign
import Testing
import LayoutCore
import LayoutTech
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

/// End-to-end antenna mitigation through the circuit layout synthesis pipeline: the
/// post-route DRC finds staged antenna violations, the jumper pass repairs
/// them, and the rerun DRC plus LVS prove the repair is real.
@Suite("Circuit Layout Antenna Mitigation")
struct CircuitLayoutAntennaMitigationTests {

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func defaultProcessNeedsNoJumpersOnInverter() throws {
        let schematic = SchematicPreview.cmosInverterViewModel().document

        let output = try CircuitLayoutSynthesizer().generate(
            from: schematic,
            catalog: .standard()
        )

        #expect(output.antennaJumpersInserted == 0)
        #expect(output.antennaMitigationFailures.isEmpty)
        #expect(!output.drcResult.violations.contains { $0.kind == .antenna })
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func topMetalViolationFailsHonestlyWithoutBridgeLayer() throws {
        // The routes sit mostly on M2 — the top metal of sampleProcess —
        // and a top-metal antenna cannot be jumpered. The pass must report
        // the gates it cannot protect and leave the violations in the DRC
        // result instead of claiming success.
        let schematic = SchematicPreview.cmosInverterViewModel().document
        var tech = LayoutTechDatabase.sampleProcess()
        tech.antennaRules = [
            LayoutAntennaRule(layerID: LayoutLayerID(name: "M1", purpose: "drawing"), maxRatio: 2.0),
            LayoutAntennaRule(layerID: LayoutLayerID(name: "M2", purpose: "drawing"), maxRatio: 2.0),
        ]

        let output = try CircuitLayoutSynthesizer().generate(
            from: schematic,
            catalog: .standard(),
            tech: tech
        )

        #expect(!output.antennaMitigationFailures.isEmpty)
        #expect(output.antennaMitigationFailures.allSatisfy {
            $0.contains("no conductor layer above")
        })
        #expect(output.drcResult.violations.contains { $0.kind == .antenna })
    }

    @Test(.timeLimit(.minutes(2)))
    @MainActor
    func tightAntennaLimitTriggersJumperRepairAndStaysLVSClean() throws {
        let schematic = SchematicPreview.cmosInverterViewModel().document
        // Tight enough that the inverter's input route violates before
        // mitigation, loose enough that the post-jumper gate-side stub
        // passes with margin. M3 gives the top routing metal a bridge
        // layer so every violation is jumperable.
        let tech = techWithThirdMetal(maxRatio: 2.0)

        let output = try CircuitLayoutSynthesizer().generate(
            from: schematic,
            catalog: .standard(),
            tech: tech
        )

        #expect(output.antennaJumpersInserted >= 1)
        #expect(output.antennaMitigationFailures.isEmpty)
        #expect(!output.drcResult.violations.contains { $0.kind == .antenna })

        // The jumper rewires the net through the bridge layer without
        // changing connectivity; LVS against the schematic must still pass.
        let verification = PhysicalVerificationService().runPrePEXVerification(
            schematic: schematic,
            layout: output.document,
            tech: output.tech,
            designUnit: output.designUnit
        )
        #expect(verification.lvs.passed)
    }

    // MARK: - Fixtures

    /// sampleProcess plus an M3/VIA2 stage and tight antenna limits on the
    /// two routing metals.
    private func techWithThirdMetal(maxRatio: Double) -> LayoutTechDatabase {
        var tech = LayoutTechDatabase.sampleProcess()
        let m1 = LayoutLayerID(name: "M1", purpose: "drawing")
        let m2 = LayoutLayerID(name: "M2", purpose: "drawing")
        let m3 = LayoutLayerID(name: "M3", purpose: "drawing")
        let via2 = LayoutLayerID(name: "VIA2", purpose: "cut")

        tech.layers.append(LayoutLayerDefinition(
            id: m3, displayName: "Metal3", gdsLayer: 4, gdsDatatype: 0,
            color: LayoutColor(red: 0.5, green: 0.8, blue: 0.5),
            fillPattern: .forwardDiagonal,
            preferredDirection: .horizontal
        ))
        tech.layers.append(LayoutLayerDefinition(
            id: via2, displayName: "Via2", gdsLayer: 5, gdsDatatype: 0,
            color: LayoutColor(red: 0.8, green: 0.8, blue: 0.2),
            fillPattern: .crosshatch
        ))
        tech.layerRules.append(LayoutLayerRuleSet(
            layerID: m3, minWidth: 0.28, minSpacing: 0.28,
            minArea: 0.01, minDensity: 0.0, maxDensity: 1.0
        ))
        tech.vias.append(LayoutViaDefinition(
            id: "VIA2",
            cutLayer: via2,
            topLayer: m3,
            bottomLayer: m2,
            cutSize: LayoutSize(width: 0.22, height: 0.22),
            enclosure: LayoutViaEnclosure(top: 0.05, bottom: 0.05),
            cutSpacing: 0.25
        ))
        tech.antennaRules = [
            LayoutAntennaRule(layerID: m1, maxRatio: maxRatio),
            LayoutAntennaRule(layerID: m2, maxRatio: maxRatio),
        ]
        return tech
    }
}
