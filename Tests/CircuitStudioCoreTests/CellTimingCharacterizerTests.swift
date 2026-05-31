import Foundation
import Testing
@testable import CircuitStudioApp

/// BC1.2 — SPICE characterization. CoreSpice runs in-process, so these always execute (no
/// external tool gating). They check that the NLDM tables come out of physics with the
/// right shape — positive, load-monotone, slew-monotone — and that a characterized library
/// drives the STA on the ACC-4 core to a finite, physical clock frequency.
@Suite("Cell timing characterization")
struct CellTimingCharacterizerTests {

    private func characterizer() -> CellTimingCharacterizer {
        // A 2x2 grid keeps the suite fast while still exercising both axes.
        CellTimingCharacterizer(inputSlews: [20e-12, 320e-12], outputLoads: [0.5e-15, 8e-15])
    }

    @Test("An inverter characterizes to positive, load- and slew-monotone delays", .timeLimit(.minutes(2)))
    func inverterCharacterizes() async throws {
        let timing = try await characterizer().characterize(.inverter(name: "inv"))
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

    @Test("NAND2 and NOR2 characterize both input arcs with positive delay", .timeLimit(.minutes(2)))
    func multiInputCellsCharacterize() async throws {
        let nand = try await characterizer().characterize(.nand(name: "nand2", inputs: ["A", "B"]))
        let nor = try await characterizer().characterize(.nor(name: "nor2", inputs: ["A", "B"]))
        for cell in [nand, nor] {
            #expect(cell.arcs.count == 2)
            for pin in ["A", "B"] {
                let arc = try #require(cell.arc(fromInput: pin))
                #expect(arc.delayFall.lookup(inputSlew: 20e-12, outputLoad: 2e-15) > 0)
                #expect(arc.delayRise.lookup(inputSlew: 20e-12, outputLoad: 2e-15) > 0)
            }
        }
    }

    @Test("A characterized library drives STA on the ACC-4 core to a finite, physical fmax", .timeLimit(.minutes(3)))
    func characterizedLibraryDrivesSTA() async throws {
        let char = characterizer()
        var lib = TimingLibrary()
        lib.add(try await char.characterize(.inverter(name: "inv")))
        lib.add(try await char.characterize(.nand(name: "nand2", inputs: ["A", "B"])))
        lib.add(try await char.characterize(.nor(name: "nor2", inputs: ["A", "B"])))
        // A hand flip-flop model (SPICE-characterized in BC1.2b); plausible for this smoke.
        lib.flipFlop = SequentialTiming(
            clkToQRise: .constant(120e-12), clkToQFall: .constant(120e-12),
            qTransitionRise: .constant(40e-12), qTransitionFall: .constant(40e-12),
            setupTime: 30e-12, holdTime: 10e-12, dataCapacitance: 1e-15, clockCapacitance: 2e-15)

        let seq = ACC4CPUGenerator().sequentialNetlist()
        let report = try StaticTimingAnalyzer(library: lib).analyze(seq, clockPeriod: 10e-9, defaultInputSlew: 50e-12)
        #expect(report.fmaxHz.isFinite && report.fmaxHz > 0, "fmax = \(report.fmaxHz)")
        #expect(report.criticalPath.endpoint.hasPrefix("acc_d"))
        #expect(report.criticalPath.stages.allSatisfy { $0.stageDelay > 0 })
        // The critical path runs through the carry chain: several gate stages deep.
        #expect(report.criticalPath.stages.count >= 6, "stages = \(report.criticalPath.stages.count)")
    }
}
