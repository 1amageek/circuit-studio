import CoreSpice
import CoreSpiceIO
import Foundation
import Testing
@testable import CircuitStudioCore

@Suite("Studio BSIM4 simulation composition", .timeLimit(.minutes(1)))
struct BSIM4SimulationCompositionTests {
    @Test(arguments: ["dc", "ac", "tran", "noise"])
    func exactBSIM45RunsThroughThePublicServiceAndReleasesTheJob(_ analysis: String) async throws {
        let directive: String
        switch analysis {
        case "dc": directive = ".dc VG 1 1.5 .25"
        case "ac": directive = ".ac lin 3 1k 10k"
        case "tran": directive = ".tran 10p 100p"
        default: directive = ".noise V(d) VG lin 3 1k 10k"
        }
        let service = SimulationService(transientExecutionLimits: StudioTransientExecutionPolicy.interactivePreview)
        defer { service.shutdown() }
        let result = try await service.runSPICE(source: """
        exact BSIM45 studio execution
        .options bsim4stressiterations=8
        .model process nmos level=54 version=4.5 toxe=10n vth0=.7 u0=.05 tnoimod=1 fnoimod=0 kf=1e-25
        VD supply 0 2
        RL supply d 1k
        VG g 0 \(analysis == "tran" ? "sin(1.2 .01 10Meg)" : "1.2") ac 1
        M1 d g 0 0 process l=1u w=10u nf=2 m=3 trnqsmod=1
        \(directive)
        .end
        """, fileName: nil)
        #expect(result.status == .completed && service.activeJobID == nil)
        let waveform = try #require(result.waveform)
        #expect(waveform.pointCount >= 3)
        if analysis == "ac" {
            let variable = try #require(waveform.variableIndex(named: "V(d)"))
            let value = try #require(waveform.complexValue(variable: variable, point: 0))
            #expect(value.real.isFinite && value.real < 0 && value.imag.isFinite)
        } else {
            let variable = try #require(waveform.variableIndex(named: analysis == "noise" ? "onoise" : "V(d)"))
            let first = try #require(waveform.realValue(variable: variable, point: 0))
            let last = try #require(waveform.realValue(variable: variable, point: waveform.pointCount - 1))
            #expect(first.isFinite && first > 0 && last.isFinite && last > 0)
            if analysis != "noise" { #expect(first < 2 && last < 2 && first != last) }
        }
    }

    @Test func unknownBSIMReleaseRemainsTypedAndLeavesNoActiveJob() async throws {
        let service = SimulationService(transientExecutionLimits: nil)
        defer { service.shutdown() }
        await #expect(throws: MOSResolutionFailure.schema(.unsupportedRelease(level: 54, version: "4.62"))) {
            _ = try await service.runSPICE(source: source().replacingOccurrences(of: "version=4.8.3", with: "version=4.62"), fileName: nil)
        }
        #expect(service.activeJobID == nil)
    }

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

    @Test(arguments: ["4.5", "4.8.3"])
    func missingPreparationPolicyRemainsTypedWithoutCompletedResult(_ version: String) async throws {
        let service = SimulationService(transientExecutionLimits: nil)
        defer { service.shutdown() }
        await #expect(throws: BSIM4DeviceError.missingPreparationPolicy("process")) {
            _ = try await service.runSPICE(source: source(policy: "").replacingOccurrences(of: "version=4.8.3", with: "version=\(version)"), fileName: nil)
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
    @Test func selectedFamilyMatchesExactModelAndProcessOverrideFeedsDependentGeometry() async throws {
        let service = SimulationService(transientExecutionLimits: nil)
        defer { service.shutdown() }
        let base = source(analysis: ".dc VG 0.8 1.0 0.1\n.ac lin 1 {missing_unused} 1k", policy: "")
            .replacingOccurrences(of: ".model process nmos level=54 version=4.8.3 vth0=0.7 u0=0.05 toxe=10n",
                with: ".param length=0.5u dependent=length\n.model process nmos level=49 version=3.3.0 vth0=0.4 u0=500 tox=10n")
            .replacingOccurrences(of: "l=1u", with: "l={dependent}")
        let binned = base.replacingOccurrences(of: ".model process nmos level=49 version=3.3.0 vth0=0.4 u0=500 tox=10n",
            with: ".model process.1 nmos level=49 version=3.3.0 lmin=0.1u lmax=2u wmin=1u wmax=20u vth0=0.4 u0=500 tox=10n\n.model process.2 nmos level=49 version=3.3.0 lmin=3u lmax=5u wmin=1u wmax=20u vth0=0.9 u0=500 tox=10n")
        let exact = try drainCurrent(try await service.runSPICE(source: base.replacingOccurrences(of: "length=0.5u", with: "length=1u"), fileName: nil))
        let selected = try drainCurrent(try await service.runSPICE(source: binned, fileName: nil,
            processConfiguration: ProcessConfiguration(parameterOverrides: ["length": 1e-6])))
        #expect(exact.count == 3 && selected.count == 3)
        for index in exact.indices { #expect(abs(exact[index] - selected[index]) < 1e-12) }
    }

}
