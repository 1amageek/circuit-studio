import Foundation
import Synchronization
import CoreSpice
import CoreSpiceIO
import Testing

@testable import CircuitStudioCore

@Suite("Simulation Service Execution Tests")
struct SimulationServiceExecutionTests {

    @Test(.timeLimit(.minutes(1)))
    func runExplicitOctaveACAnalysisUsesNativeOctaveSpacing() async throws {
        let service = SimulationService(transientExecutionLimits: StudioTransientExecutionPolicy.interactivePreview)
        let source = """
        RC lowpass filter
        V1 in 0 AC 1
        R1 in out 1k
        C1 out 0 1n
        .end
        """

        let result = try await service.runAnalysis(
            source: source,
            fileName: nil,
            processConfiguration: nil,
            command: .ac(ACSpec(
                scaleType: .octave,
                numberOfPoints: 1,
                startFrequency: 1,
                stopFrequency: 4
            ))
        )

        let waveform = try #require(result.waveform)
        #expect(waveform.pointCount == 3)
        #expect(waveform.sweepValues == [1, 2, 4])
    }

    @Test(.timeLimit(.minutes(1)))
    func runDCSweepRejectsMissingSource() async throws {
        let service = SimulationService(transientExecutionLimits: StudioTransientExecutionPolicy.interactivePreview)
        defer { service.shutdown() }
        let source = """
        Voltage divider
        V1 in 0 5
        R1 in out 1k
        R2 out 0 1k
        .end
        """

        do {
            _ = try await service.runAnalysis(
                source: source,
                fileName: nil,
                processConfiguration: nil,
                command: .dcSweep(DCSweepSpec(
                    source: "VX",
                    startValue: 0,
                    stopValue: 1,
                    stepValue: 0.1
                ))
            )
            Issue.record("Expected missing DC sweep source to fail")
        } catch let error as SPICENativeExecutionError {
            guard case .unsupportedCapability(let message) = error else { throw error }
            #expect(message == "Missing DC source")
        }
        #expect(service.activeJobID == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func runDCSweepRejectsNonSourceComponent() async throws {
        let service = SimulationService(transientExecutionLimits: StudioTransientExecutionPolicy.interactivePreview)
        defer { service.shutdown() }
        let source = """
        Voltage divider
        V1 in 0 5
        R1 in out 1k
        R2 out 0 1k
        .end
        """

        do {
            _ = try await service.runAnalysis(
                source: source,
                fileName: nil,
                processConfiguration: nil,
                command: .dcSweep(DCSweepSpec(
                    source: "R1",
                    startValue: 0,
                    stopValue: 1,
                    stepValue: 0.1
                ))
            )
            Issue.record("Expected non-source DC sweep target to fail")
        } catch let error as SPICENativeExecutionError {
            guard case .unsupportedCapability(let message) = error else { throw error }
            #expect(message == "DC sweep requires an independent source")
        }
        #expect(service.activeJobID == nil)
    }

    @Test("native transient records the exact explicit caller policy and waveform", .timeLimit(.minutes(1)))
    func callerTransientPolicy() async throws {
        let policy = StudioTransientExecutionPolicy.interactivePreview
        let service = SimulationService(transientExecutionLimits: policy)
        defer { service.shutdown() }
        let source = Self.transientSource
            .replacingOccurrences(of: "R2 out 0 1k", with: "R2 out 0 1k\nC1 out 0 10p")
            .replacingOccurrences(of: ".tran 1n 10n", with: ".tran 1n 100n")
        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)
        #expect(result.transientExecutionPolicy?.source == .caller)
        #expect(result.transientExecutionPolicy?.limits == policy)
        let waveform = try #require(result.waveform)
        let output = try #require(waveform.variableIndex(named: "V(out)"))
        let value = try #require(waveform.realValue(variable: output, point: waveform.pointCount - 1))
        #expect(abs(value - 0.5) < 1e-5)
        let finalTime = try #require(waveform.sweepValues.last)
        #expect(abs(finalTime - 100e-9) < 1e-18)
        #expect(waveform.pointCount > 2)
        #expect(service.activeJobID == nil)
    }

    @Test("complete parsed deck policy overrides caller ceilings exactly", .timeLimit(.minutes(1)))
    func deckTransientPolicy() async throws {
        var caller = StudioTransientExecutionPolicy.interactivePreview
        caller.maximumSavedScalars = 1
        let service = SimulationService(transientExecutionLimits: caller)
        defer { service.shutdown() }
        let source = Self.transientSource.replacingOccurrences(of: ".tran", with: Self.deckLimits + "\n.tran")
        let result = try await service.runSPICE(source: source, fileName: nil)
        let selected = try #require(result.transientExecutionPolicy)
        #expect(selected.source == .deckOptions)
        #expect(selected.limits.maximumAcceptedSteps == 200)
        #expect(selected.limits.maximumSolveAttempts == 1000)
        #expect(selected.limits.maximumNewtonIterations == 10000)
        #expect(selected.limits.maximumSavedScalars == 10000)
        #expect(selected.limits.maximumMatrixDimension == 16)
        #expect(selected.limits.maximumWorkUnits == 1000000)
        #expect(selected.limits.maximumBreakpoints == 100)
    }

    @Test("explicit command also retains its complete deck policy", .timeLimit(.minutes(1)))
    func explicitTransientCommandPolicy() async throws {
        let service = SimulationService(transientExecutionLimits: nil)
        defer { service.shutdown() }
        let source = Self.transientSource.replacingOccurrences(of: ".tran 1n 10n", with: Self.deckLimits)
        let result = try await service.runAnalysis(source: source, fileName: nil, command: .tran(TranSpec(
            stopTime: 10e-9, stepTime: 1e-9, maxStep: 1e-9)))
        #expect(result.status == .completed)
        #expect(result.transientExecutionPolicy?.source == .deckOptions)
    }

    @Test("missing and partial policies fail as typed errors before any waveform", .timeLimit(.minutes(1)), arguments: [false, true])
    func missingTransientPolicy(_ partial: Bool) async throws {
        let service = SimulationService(transientExecutionLimits: partial ? StudioTransientExecutionPolicy.interactivePreview : nil)
        defer { service.shutdown() }
        let source = partial
            ? Self.transientSource.replacingOccurrences(of: ".tran", with: ".options tranmaxaccepted=1\n.tran")
            : Self.transientSource
        let sawWaveform = Mutex(false)
        await #expect(throws: TransientExecutionError.missingExecutionLimits) {
            _ = try await service.runSPICE(source: source, fileName: nil, onWaveformUpdate: { _ in sawWaveform.withLock { $0 = true } })
        }
        #expect(!sawWaveform.withLock { $0 })
        #expect(service.activeJobID == nil)
    }

    @Test("an exhausted caller policy fails without a completed result", .timeLimit(.minutes(1)))
    func lowTransientPolicy() async throws {
        var policy = StudioTransientExecutionPolicy.interactivePreview
        policy.maximumSavedScalars = 1
        let service = SimulationService(transientExecutionLimits: policy)
        defer { service.shutdown() }
        let sawWaveform = Mutex(false)
        do {
            _ = try await service.runSPICE(source: Self.transientSource, fileName: nil,
                onWaveformUpdate: { _ in sawWaveform.withLock { $0 = true } })
            Issue.record("An insufficient saved-scalar policy unexpectedly completed")
        } catch let failure as SPICENativeExecutionError {
            guard case .resource(let cause) = failure,
                  let numerical = cause as? TransientExecutionError else { throw failure }
            #expect(numerical == .invalidLimit(name: "savedScalars", value: 1))
        }
        #expect(!sawWaveform.withLock { $0 })
        #expect(service.activeJobID == nil)
    }

    @Test("actual transient progress can cancel the native run with a typed terminal outcome", .timeLimit(.minutes(1)))
    func cancelTransientProgress() async throws {
        var policy = StudioTransientExecutionPolicy.interactivePreview
        policy.maximumAcceptedSteps = 2_000_000
        policy.maximumSavedScalars = 16_000_000
        policy.maximumNewtonIterations = 4_000_000
        policy.maximumSolveAttempts = 4_000_000
        let service = SimulationService(transientExecutionLimits: policy)
        defer { service.shutdown() }
        let sawPartialWaveform = Mutex(false)
        let source = Self.transientSource.replacingOccurrences(of: ".tran 1n 10n", with: ".tran 1p 1m")
        await #expect(throws: StudioError.cancelled) {
            _ = try await service.runSPICE(source: source, fileName: nil, onWaveformUpdate: { waveform in
                guard waveform.pointCount > 1, let time = waveform.sweepValues.last, time < 1e-3 else { return }
                sawPartialWaveform.withLock { $0 = true }
                if let job = service.activeJobID { service.cancel(jobID: job) }
            })
        }
        #expect(sawPartialWaveform.withLock { $0 })
        #expect(service.activeJobID == nil)
    }

    private static let deckLimits = ".options tranmaxaccepted=200 tranmaxattempts=1000 tranmaxiterations=10000 tranmaxscalars=10000 tranmaxdimension=16 tranmaxwork=1000000 tranmaxbreakpoints=100"
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func sourceInitialConditionReachesImplicitAndExplicitTransient(_ explicit: Bool) async throws {
        let service = SimulationService(transientExecutionLimits: StudioTransientExecutionPolicy.interactivePreview)
        defer { service.shutdown() }
        let result: SimulationResult
        if explicit {
            result = try await service.runAnalysis(source: Self.initialConditionSource, fileName: nil,
                command: .tran(.init(stopTime: 10e-9, stepTime: 1e-9, useInitialConditions: true)))
        } else {
            result = try await service.runSPICE(source: Self.initialConditionSource, fileName: nil)
        }
        let waveform = try #require(result.waveform)
        let node = try #require(waveform.variableIndex(named: "V(out)"))
        #expect(abs(try #require(waveform.realValue(variable: node, point: 0)) - 2) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [".ic", ".nodeset"])
    func undefinedSourceNodeVoltageFailsBeforeCompletion(_ directive: String) async throws {
        let service = SimulationService(transientExecutionLimits: StudioTransientExecutionPolicy.interactivePreview)
        defer { service.shutdown() }
        let source = Self.initialConditionSource.replacingOccurrences(of: ".ic V(out)=2",
            with: "\(directive) V(out)={missing_voltage}")
        do {
            _ = try await service.runSPICE(source: source, fileName: nil)
            Issue.record("Undefined source node voltage unexpectedly completed")
        } catch let failure as SPICENodeVoltageResolutionError {
            guard case .evaluation(let node, let cause) = failure,
                  let resolution = cause as? MOSResolutionFailure, case .undefinedParameter = resolution else { throw failure }
            #expect(node.lowercased() == "out")
        }
        #expect(service.activeJobID == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func initialConditionSharesCircuitRandomStream() async throws {
        let service = SimulationService(transientExecutionLimits: StudioTransientExecutionPolicy.interactivePreview)
        defer { service.shutdown() }
        let source = Self.initialConditionSource.replacingOccurrences(of: "R1 out 0 1k", with: "R1 out 0 {1000+rand()}")
            .replacingOccurrences(of: ".ic V(out)=2", with: ".ic V(out)={rand()}")
        let waveform = try #require(try await service.runSPICE(source: source, fileName: nil).waveform)
        let node = try #require(waveform.variableIndex(named: "V(out)"))
        #expect(abs(try #require(waveform.realValue(variable: node, point: 0)) - 0.33112028100185353) < 1e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceInitialConditionWithoutUICIsExplicitlyRefused() async throws {
        let service = SimulationService(transientExecutionLimits: StudioTransientExecutionPolicy.interactivePreview)
        defer { service.shutdown() }
        await #expect(throws: StudioError.simulationFailure("IC requires transient UIC")) {
            _ = try await service.runSPICE(source: Self.initialConditionSource.replacingOccurrences(of: " uic", with: ""), fileName: nil)
        }
        #expect(service.activeJobID == nil)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func sourceNodesetWithUICIsExplicitlyRefused(_ explicit: Bool) async throws {
        let service = SimulationService(transientExecutionLimits: StudioTransientExecutionPolicy.interactivePreview)
        defer { service.shutdown() }
        let source = Self.initialConditionSource.replacingOccurrences(of: ".ic V(out)=2",
            with: ".nodeset V(out)=2")
        do {
            if explicit {
                _ = try await service.runAnalysis(source: source, fileName: nil,
                    command: .tran(.init(stopTime: 10e-9, stepTime: 1e-9, useInitialConditions: true)))
            } else {
                _ = try await service.runSPICE(source: source, fileName: nil)
            }
            Issue.record("UIC skipped the source node set without refusing it")
        } catch let failure as SPICESimulationPreparationError {
            guard case .unsupportedCapability(let capability) = failure else { throw failure }
            #expect(capability == "Nodeset with UIC skips its DC application")
        }
        #expect(service.activeJobID == nil)
    }

    private static let initialConditionSource = """
    Studio source initial condition
    R1 out 0 1k
    C1 out 0 1n
    .ic V(out)=2
    .tran 1n 10n uic
    .end
    """
    private static let transientSource = """
    Explicit transient fixture
    V1 in 0 PWL(0 0 1n 0 2n 1 10n 1)
    R1 in out 1k
    R2 out 0 1k
    .tran 1n 10n
    .end
    """
}
