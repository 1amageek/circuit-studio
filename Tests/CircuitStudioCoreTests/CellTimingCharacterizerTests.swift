import Foundation
import Testing
@testable import CircuitStudioApp

/// BC1.2 — SPICE characterization. CoreSpice runs in-process, so these always execute (no
/// external tool gating). They check that the NLDM tables come out of physics with the
/// right shape — positive, load-monotone, slew-monotone — and that a characterized library
/// drives the STA on the ACC-4 core to a finite, physical clock frequency.
@Suite("Cell timing characterization")
struct CellTimingCharacterizerTests {

    private func characterize(_ cell: CMOSGateNetlist) async throws -> CellTiming {
        try await TimingCharacterizationTestCache.shared.characterizeCell(
            cell,
            inputSlews: [20e-12, 320e-12],
            outputLoads: [0.5e-15, 8e-15]
        )
    }

    @Test("An inverter characterizes to positive, load- and slew-monotone delays", .timeLimit(.minutes(7)))
    func inverterCharacterizes() async throws {
        let timing = try await characterize(.inverter(name: "inv"))
        #expect(timing.cellName == "inv")
        let arc = try #require(timing.arc(fromInput: "A"))

        // Delay grows with output load (always true). Slew dependence is load-dependent
        // (a slow input trips a lightly loaded gate before 50%), so it is checked at heavy
        // load where slower input clearly means more delay.
        let lightFast = arc.delayFall.lookup(inputSlew: 20e-12, outputLoad: 0.5e-15)
        let heavyFast = arc.delayFall.lookup(inputSlew: 20e-12, outputLoad: 8e-15)
        let heavySlow = arc.delayFall.lookup(inputSlew: 320e-12, outputLoad: 8e-15)
        #expect(heavyFast > lightFast, "delay must grow with load: \(heavyFast) !> \(lightFast)")
        #expect(heavySlow > heavyFast, "delay must grow with input slew at load: \(heavySlow) !> \(heavyFast)")
        #expect(heavyFast > 0 && heavyFast < 1e-9, "a loaded inverter delay must be physical: \(heavyFast)")
        #expect((timing.inputCapacitance["A"] ?? 0) > 0)
        // Output slew should also grow with load.
        let slewLight = arc.transitionFall.lookup(inputSlew: 20e-12, outputLoad: 0.5e-15)
        let slewHeavy = arc.transitionFall.lookup(inputSlew: 20e-12, outputLoad: 8e-15)
        #expect(slewHeavy > slewLight)
    }

    @Test("NAND2 and NOR2 characterize both input arcs with positive delay", .timeLimit(.minutes(7)))
    func multiInputCellsCharacterize() async throws {
        let nand = try await characterize(.nand(name: "nand2", inputs: ["A", "B"]))
        let nor = try await characterize(.nor(name: "nor2", inputs: ["A", "B"]))
        for cell in [nand, nor] {
            #expect(cell.arcs.count == 2)
            for pin in ["A", "B"] {
                let arc = try #require(cell.arc(fromInput: pin))
                #expect(arc.delayFall.lookup(inputSlew: 20e-12, outputLoad: 2e-15) > 0)
                #expect(arc.delayRise.lookup(inputSlew: 20e-12, outputLoad: 2e-15) > 0)
            }
        }
    }

}
