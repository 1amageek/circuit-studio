import CoreSpice
import Foundation
import Testing
@testable import CircuitStudioCore

@Suite("Studio BSIM4 simulation composition", .timeLimit(.minutes(1)))
struct BSIM4SimulationCompositionTests {
    private func source(analysis: String = ".op", policy: String = ".options bsim4stressiterations=8",
                        temperature: Double = 27) -> String {
        """
        Explicit studio BSIM4 composition
        \(policy)
        .temp \(temperature)
        .model process nmos level=54 version=4.8.3 vth0=0.7 u0=0.05 toxe=10n
        VD d 0 1
        VG g 0 1.2 ac 1
        VS s 0 0
        VB b 0 -0.1
        M1 d g s b process w=10u l=1u
        \(analysis)
        .end
        """
    }

    private func drainCurrent(_ result: SimulationResult) throws -> [Double] {
        #expect(result.status == .completed)
        let waveform = try #require(result.waveform)
        let variable = try #require(waveform.variables.first { $0.name.lowercased() == "i(vd)" })
        return try (0..<waveform.pointCount).map {
            try #require(waveform.realValue(variable: variable.index, point: $0))
        }
    }

    @Test(arguments: [false, true])
    func preparationPolicySurvivesInitialAndSweepBinding(_ sweep: Bool) async throws {
        let service = SimulationService(transientExecutionLimits: nil)
        defer { service.shutdown() }
        let result = try await service.runSPICE(source: source(analysis: sweep ? ".dc VG 1.0 1.2 0.1" : ".op"), fileName: nil)
        let current = try drainCurrent(result)
        #expect(current.count == (sweep ? 3 : 1))
        #expect(current.allSatisfy { $0.isFinite && $0 < -1e-10 })
        if sweep { #expect(current.first != current.last) }
        #expect(service.activeJobID == nil)
    }

    @Test func missingPreparationPolicyRemainsTypedWithoutCompletedResult() async throws {
        let service = SimulationService(transientExecutionLimits: nil)
        defer { service.shutdown() }
        await #expect(throws: BSIM4DeviceError.missingPreparationPolicy("process")) {
            _ = try await service.runSPICE(source: source(policy: ""), fileName: nil)
        }
        #expect(service.activeJobID == nil)
    }

    @Test func selectedTemperatureIsSharedAndProcessOverrideKeepsPriority() async throws {
        let service = SimulationService(transientExecutionLimits: nil)
        defer { service.shutdown() }
        let nominal = try drainCurrent(try await service.runSPICE(source: source(temperature: 27), fileName: nil))[0]
        let hot = try drainCurrent(try await service.runSPICE(source: source(temperature: 125), fileName: nil))[0]
        let overridden = try drainCurrent(try await service.runSPICE(source: source(temperature: 125), fileName: nil,
            processConfiguration: ProcessConfiguration(temperatureOverride: 27)))[0]
        #expect(nominal.isFinite && hot.isFinite)
        #expect(abs(nominal - hot) > 1e-8)
        #expect(abs(nominal - overridden) <= 1e-12 + 1e-8 * abs(nominal))
    }

    @Test(arguments: [false, true])
    func parsedAndTypedNoiseIntentPrepareActualOutputNoise(_ explicit: Bool) async throws {
        let service = SimulationService(transientExecutionLimits: nil)
        defer { service.shutdown() }
        let text = source(analysis: explicit ? "" : ".noise V(d) VG lin 1 1k 1k")
            .replacingOccurrences(of: "VD d 0 1", with: "VD supply 0 2\nRL supply d 1k")
            .replacingOccurrences(of: "toxe=10n", with: "toxe=10n tnoimod=2 fnoimod=0 kf=1e-25")
        let result: SimulationResult
        if explicit {
            result = try await service.runAnalysis(source: text, fileName: nil,
                command: .noise(NoiseSpec(outputNode: "d", inputSource: "vg", scaleType: .linear,
                    numberOfPoints: 1, startFrequency: 1e3, stopFrequency: 1e3)))
        } else {
            result = try await service.runSPICE(source: text, fileName: nil)
        }
        #expect(result.status == .completed)
        let waveform = try #require(result.waveform)
        let variable = try #require(waveform.variableIndex(named: "onoise"))
        let noise = try #require(waveform.realValue(variable: variable, point: 0))
        #expect(noise.isFinite && noise > 0)
        #expect(waveform.variables.filter { $0.name.hasPrefix("m1_") }.count == 14)
    }

    @Test func unappliedOptionDiagnosticsComeFromTheAdmittedPipeline() async throws {
        let service = SimulationService(transientExecutionLimits: nil)
        defer { service.shutdown() }
        let result = try await service.runSPICE(source: source(policy: ".options bsim4stressiterations=8 host_unapplied=1"), fileName: nil)
        #expect(result.status == .completed)
        #expect(result.logMessages.contains { $0.contains("host_unapplied") && $0.contains("not applied") })
    }
}
