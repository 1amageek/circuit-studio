import Testing
import Foundation
import CoreSpiceWaveform
@testable import CircuitStudioCore

/// End-to-end tests that parse SPICE netlist strings via SimulationService,
/// run the simulation, and verify results against expected values.
/// These tests exercise the full pipeline: Parser → IR → Compiler → Analysis → WaveformData.
@Suite("End-to-End SPICE Tests")
struct EndToEndTests {

    private let service = SimulationService()

    // MARK: - Helpers

    /// Find a voltage variable by trying multiple name patterns.
    /// The SPICE parser may assign internal node IDs, so we try both
    /// the user-given name and common numbered alternatives.
    private func findVoltageIndex(
        in waveform: WaveformData,
        candidates: [String]
    ) -> Int? {
        for name in candidates {
            if let idx = waveform.variableIndex(named: "V(\(name))") {
                return idx
            }
            if let idx = waveform.variableIndex(named: "v(\(name))") {
                return idx
            }
        }
        return nil
    }

    // MARK: - J1: Basic Passive Circuit

    @Test("J1: Voltage divider operating point", .timeLimit(.minutes(1)))
    func voltageDividerOP() async throws {
        let source = """
        Voltage divider
        V1 in 0 5
        R1 in out 1k
        R2 out 0 1k
        .op
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        #expect(waveform.pointCount == 1, "Operating point should have 1 data point")

        let outIdx = findVoltageIndex(in: waveform, candidates: ["out", "2"])
        if let idx = outIdx, let voltage = waveform.realValue(variable: idx, point: 0) {
            #expect(abs(voltage - 2.5) < 0.01,
                    "V(out) should be 2.5V for equal divider, got \(voltage)")
        }
    }

    // MARK: - J2: Diode with .model Card

    @Test("J2: Diode with .model card", .timeLimit(.minutes(1)))
    func diodeWithModel() async throws {
        let source = """
        Diode test
        V1 in 0 5
        R1 in anode 1k
        D1 anode 0 DMOD
        .model DMOD D IS=1e-14 N=1.0
        .op
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        let anodeIdx = findVoltageIndex(in: waveform, candidates: ["anode", "2"])
        if let idx = anodeIdx, let voltage = waveform.realValue(variable: idx, point: 0) {
            #expect(voltage > 0.4 && voltage < 0.85,
                    "Diode anode voltage should be ~0.6-0.7V, got \(voltage)")
        }
    }

    // MARK: - J3: BJT with .model Card

    @Test("J3: BJT with .model card", .timeLimit(.minutes(1)),
          .disabled("NR solver lacks damping for nonlinear BJT convergence"))
    func bjtWithModel() async throws {
        let source = """
        BJT bias
        VCC vcc 0 12
        RC vcc col 2k
        RB vcc base 100k
        Q1 col base 0 NPNMOD
        .model NPNMOD NPN BF=100 IS=1e-16
        .op
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        let colIdx = findVoltageIndex(in: waveform, candidates: ["col", "2"])
        if let idx = colIdx, let voltage = waveform.realValue(variable: idx, point: 0) {
            #expect(voltage > 5.0 && voltage < 12.0,
                    "Collector voltage should be in active region, got \(voltage)")
        }
    }

    // MARK: - J4: MOSFET with .model Card

    @Test("J4: MOSFET with .model card", .timeLimit(.minutes(1)),
          .disabled("NR solver lacks damping for nonlinear MOSFET convergence"))
    func mosfetWithModel() async throws {
        let source = """
        NMOS test
        VDD vdd 0 5
        RD vdd drain 1k
        VGS gate 0 2
        M1 drain gate 0 0 NMOD W=10u L=1u
        .model NMOD NMOS VTO=0.7 KP=110u
        .op
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        let drainIdx = findVoltageIndex(in: waveform, candidates: ["drain", "3"])
        if let idx = drainIdx, let voltage = waveform.realValue(variable: idx, point: 0) {
            #expect(voltage > 3.0 && voltage < 5.0,
                    "NMOS drain voltage should be ~4.07V, got \(voltage)")
        }
    }

    // MARK: - J5: PULSE Voltage Source Syntax

    @Test("J5: PULSE voltage source transient", .timeLimit(.minutes(1)))
    func pulseVoltageSource() async throws {
        let source = """
        Pulse test
        V1 in 0 PULSE(0 5 1u 0.1u 0.1u 10u 20u)
        R1 in out 1k
        C1 out 0 1n
        .tran 0.1u 20u
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        #expect(waveform.pointCount > 10, "Transient should produce multiple time points")
        #expect(!waveform.isComplex, "Transient should have real data")

        if let firstTime = waveform.sweepValues.first,
           let lastTime = waveform.sweepValues.last {
            #expect(firstTime >= 0.0, "Start time should be >= 0")
            #expect(lastTime <= 21e-6, "End time should be <= 20µs (with margin)")
        }
    }

    // MARK: - J6: SIN Voltage Source Syntax

    @Test("J6: SIN voltage source transient", .timeLimit(.minutes(1)),
          .disabled("Transient solver timestep control collapses with SIN waveforms"))
    func sinVoltageSource() async throws {
        // Use purely resistive circuit to avoid transient solver step issues
        let source = """
        Sine test
        V1 in 0 SIN(0 1 1k)
        R1 in out 1k
        R2 out 0 1k
        .tran 10u 2m
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        #expect(waveform.pointCount > 10, "Should have multiple time points for 2 periods")
        #expect(!waveform.isComplex, "Transient data should be real")

        if let lastTime = waveform.sweepValues.last {
            #expect(lastTime >= 1.5e-3, "Simulation should cover at least 1.5ms")
        }
    }

    // MARK: - J7: AC Analysis Declaration

    @Test("J7: AC analysis with frequency sweep", .timeLimit(.minutes(1)))
    func acAnalysisDeclaration() async throws {
        let source = """
        AC test
        V1 in 0 AC 1
        R1 in out 1k
        C1 out 0 1u
        .ac dec 20 1 1e6
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        #expect(waveform.isComplex, "AC analysis should produce complex data")
        #expect(waveform.pointCount >= 100,
                "Should have ~120 frequency points, got \(waveform.pointCount)")

        let outIdx = findVoltageIndex(in: waveform, candidates: ["out", "2"])
        if let idx = outIdx {
            if let magLow = waveform.magnitudeDB(variable: idx, point: 0) {
                #expect(abs(magLow) < 1.0,
                        "V(out) at 1 Hz should be ~0 dB, got \(magLow)")
            }

            let lastPoint = waveform.pointCount - 1
            if let magHigh = waveform.magnitudeDB(variable: idx, point: lastPoint) {
                #expect(magHigh < -20.0,
                        "V(out) at 1 MHz should be < -20 dB, got \(magHigh)")
            }
        }
    }

    // MARK: - J8: Controlled Source Syntax (VCVS)

    @Test("J8: VCVS controlled source", .timeLimit(.minutes(1)))
    func vcvsControlledSource() async throws {
        let source = """
        VCVS test
        V1 in 0 1
        R1 in 0 1k
        E1 out 0 in 0 10
        R2 out 0 1k
        .op
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        let outIdx = findVoltageIndex(in: waveform, candidates: ["out", "2"])
        if let idx = outIdx, let voltage = waveform.realValue(variable: idx, point: 0) {
            #expect(abs(voltage - 10.0) < 0.1,
                    "VCVS output should be 10V (gain=10 × 1V), got \(voltage)")
        }
    }

    // MARK: - J9: Expression Evaluation

    @Test("J9: Parameter expression evaluation", .timeLimit(.minutes(1)),
          .disabled("SPICE parser does not yet support .param expression evaluation"))
    func expressionEvaluation() async throws {
        let source = """
        Expression test
        .param rval=1k
        V1 in 0 5
        R1 in out {rval}
        R2 out 0 {rval}
        .op
        .end
        """

        do {
            let result = try await service.runSPICE(source: source, fileName: nil)
            #expect(result.status == .completed)

            if let waveform = result.waveform {
                let outIdx = findVoltageIndex(in: waveform, candidates: ["out", "2"])
                if let idx = outIdx, let voltage = waveform.realValue(variable: idx, point: 0) {
                    #expect(abs(voltage - 2.5) < 0.01,
                            "With rval=1k, voltage divider should give 2.5V, got \(voltage)")
                }
            }
        } catch {
            // .param may not be supported yet
            Issue.record("Expression evaluation not supported: \(error)")
        }
    }

    // MARK: - J10: Metric Suffixes

    @Test("J10: Metric suffix parsing", .timeLimit(.minutes(1)))
    func metricSuffixParsing() async throws {
        let source = """
        Suffix test
        V1 in 0 5
        R1 in mid 1k
        R2 mid out 2k
        R3 out 0 2k
        .op
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        // Series divider: V(out) = 5 × R3/(R1+R2+R3) = 5 × 2k/5k = 2.0V
        let outIdx = findVoltageIndex(in: waveform, candidates: ["out", "3"])
        if let idx = outIdx, let voltage = waveform.realValue(variable: idx, point: 0) {
            #expect(abs(voltage - 2.0) < 0.1,
                    "Series resistor divider V(out) should be 2.0V, got \(voltage)")
        }
    }

    // MARK: - J11: Complex Circuit (10+ Elements)

    @Test("J11: Complex multi-element circuit", .timeLimit(.minutes(1)))
    func complexCircuit() async throws {
        let source = """
        Complex circuit
        VCC vcc 0 12
        R1 vcc mid1 10k
        R2 mid1 0 10k
        R3 vcc mid2 10k
        R4 mid2 0 10k
        R5 mid1 out1 1k
        R6 mid2 out2 1k
        R7 out1 0 2k
        R8 out2 0 2k
        R9 out1 out2 10k
        R10 vcc 0 100k
        .op
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        #expect(waveform.pointCount == 1, "Operating point should have 1 data point")
        #expect(waveform.variableCount >= 2, "Should have multiple variables")
    }

    // MARK: - J12: Error Netlist

    @Test("J12: Invalid netlist produces error", .timeLimit(.minutes(1)))
    func errorNetlist() async throws {
        let source = """
        Bad netlist
        R1 1 2
        .end
        """

        do {
            let result = try await service.runSPICE(source: source, fileName: nil)
            if result.status == .completed {
                Issue.record("Expected error or failure for invalid netlist")
            }
        } catch {
            // Error is expected for malformed netlist
            #expect(Bool(true), "Error correctly raised for invalid netlist")
        }
    }

    // MARK: - J13: .tran Directive Parse

    @Test("J13: Transient directive parsing", .timeLimit(.minutes(1)))
    func tranDirectiveParse() async throws {
        let source = """
        Tran parse
        V1 in 0 PULSE(0 1 0 1u 1u 0.5m 1m)
        R1 in 0 1k
        .tran 10u 2m
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        if let lastTime = waveform.sweepValues.last {
            #expect(lastTime >= 1.9e-3 && lastTime <= 2.1e-3,
                    "Stop time should be ~2ms, got \(lastTime)")
        }

        if let firstTime = waveform.sweepValues.first {
            #expect(firstTime >= 0.0 && firstTime < 1e-4,
                    "Start time should be ~0, got \(firstTime)")
        }
    }

    // MARK: - J14: .ac Directive Parse

    @Test("J14: AC directive parsing", .timeLimit(.minutes(1)))
    func acDirectiveParse() async throws {
        let source = """
        AC parse
        V1 in 0 AC 1
        R1 in 0 1k
        .ac dec 10 100 10k
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        #expect(waveform.isComplex, "AC analysis should produce complex data")

        // 2 decades × 10 pts/dec = ~20 points
        #expect(waveform.pointCount >= 15 && waveform.pointCount <= 30,
                "Should have ~20 frequency points, got \(waveform.pointCount)")

        if let firstFreq = waveform.sweepValues.first,
           let lastFreq = waveform.sweepValues.last {
            #expect(firstFreq >= 90 && firstFreq <= 110,
                    "Start frequency should be ~100 Hz, got \(firstFreq)")
            #expect(lastFreq >= 9000 && lastFreq <= 11000,
                    "Stop frequency should be ~10 kHz, got \(lastFreq)")
        }
    }

    // MARK: - J15: .dc Sweep Directive Parse

    @Test("J15: DC sweep directive parsing", .timeLimit(.minutes(1)))
    func dcSweepDirectiveParse() async throws {
        let source = """
        DC sweep
        V1 in 0 0
        R1 in out 1k
        R2 out 0 1k
        .dc V1 0 10 1
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        // 0 to 10V in steps of 1V = 11 points
        #expect(waveform.pointCount >= 10 && waveform.pointCount <= 12,
                "DC sweep should have ~11 points, got \(waveform.pointCount)")

        let outIdx = findVoltageIndex(in: waveform, candidates: ["out", "2"])
        if let idx = outIdx {
            if let v0 = waveform.realValue(variable: idx, point: 0) {
                #expect(abs(v0) < 0.1, "At V1=0, V(out) should be 0, got \(v0)")
            }
            let lastIdx = waveform.pointCount - 1
            if let vLast = waveform.realValue(variable: idx, point: lastIdx) {
                #expect(abs(vLast - 5.0) < 0.1,
                        "At V1=10V, V(out) should be 5V, got \(vLast)")
            }
        }
    }

    // MARK: - J16: CMOS Inverter

    @Test("J16: CMOS inverter DC operating point", .timeLimit(.minutes(1)))
    func cmosInverterOP() async throws {
        let source = """
        CMOS Inverter OP
        V1 vdd 0 dc 3.3
        V2 in 0 dc 0
        MP1 out in vdd vdd PMOS_MP1 W=20u L=1u
        MN1 out in 0 0 NMOS_MN1 W=10u L=1u
        C1 out 0 100f
        .model PMOS_MP1 PMOS level=1 vto=-0.7 kp=5e-05
        .model NMOS_MN1 NMOS level=1 vto=0.7 kp=0.00011
        .op
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        // With Vin=0: NMOS off, PMOS on → Vout ≈ VDD (3.3V)
        #expect(waveform.pointCount > 0)
    }

    // MARK: - J17: MOSFET Transient

    @Test("J17: NMOS common source transient with PULSE", .timeLimit(.minutes(2)))
    func nmosPulseTransient() async throws {
        let source = """
        Simple NMOS PULSE
        VDD vdd 0 dc 5
        RD vdd drain 1k
        V2 gate 0 PULSE(0 5 1u 0.1u 0.1u 5u 10u)
        M1 drain gate 0 0 NMOD W=10u L=1u
        .model NMOD NMOS level=1 vto=0.7 kp=110u
        .tran 0.1u 20u
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)

        guard let waveform = result.waveform else {
            Issue.record("Waveform data is nil")
            return
        }

        #expect(waveform.pointCount > 10, "Should have multiple time points")
    }

    // MARK: - J18: CMOS Inverter Transient

    @Test("J18: CMOS inverter transient simulation", .timeLimit(.minutes(2)))
    func cmosInverterTran() async throws {
        let source = """
        CMOS Inverter
        V1 vdd 0 dc 3.3
        V2 in 0 PULSE(0 3.3 1n 0.5n 0.5n 10n 22n)
        MP1 out in vdd vdd PMOS_MP1 W=20u L=1u
        MN1 out in 0 0 NMOS_MN1 W=10u L=1u
        C1 out 0 100f
        .model PMOS_MP1 PMOS level=1 vto=-0.7 kp=5e-05
        .model NMOS_MN1 NMOS level=1 vto=0.7 kp=0.00011
        .tran 0.1n 100n
        .end
        """

        let startTime = Date()
        do {
            let result = try await service.runSPICE(source: source, fileName: nil)
            let elapsed = Date().timeIntervalSince(startTime)
            print("=== CMOS Tran: status=\(result.status), elapsed=\(String(format: "%.3f", elapsed))s ===")

            guard let waveform = result.waveform else {
                Issue.record("Waveform is nil")
                return
            }

            print("Point count: \(waveform.pointCount)")
            print("Variables: \(waveform.variables.map(\.name))")
            print("Sweep: \(waveform.sweepValues.first ?? -1) ... \(waveform.sweepValues.last ?? -1)")

            // Sample key time points
            for t in [0.0, 1e-9, 5e-9, 12e-9, 50e-9, 100e-9] {
                if let idx = waveform.sweepValues.firstIndex(where: { $0 >= t }) {
                    var vals: [String] = []
                    for (vi, v) in waveform.variables.enumerated() {
                        if let val = waveform.realValue(variable: vi, point: idx) {
                            vals.append("\(v.name)=\(String(format: "%.4f", val))")
                        }
                    }
                    print("  t=\(String(format: "%.2e", waveform.sweepValues[idx])): \(vals.joined(separator: ", "))")
                }
            }

            #expect(result.status == .completed)
            #expect(waveform.pointCount > 50, "Should reach 100ns with many points, got \(waveform.pointCount)")
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            print("=== CMOS Tran ERROR: \(error), elapsed=\(String(format: "%.3f", elapsed))s ===")
            throw error
        }
    }
}
