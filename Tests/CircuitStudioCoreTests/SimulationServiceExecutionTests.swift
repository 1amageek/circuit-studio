import Foundation
import Testing

@testable import CircuitStudioCore

@Suite("Simulation Service Execution Tests")
struct SimulationServiceExecutionTests {

    @Test(.timeLimit(.minutes(1)))
    func runExplicitOctaveACAnalysisUsesNativeOctaveSpacing() async throws {
        let service = SimulationService()
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
        let service = SimulationService()
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
        } catch let error as StudioError {
            guard case .simulationFailure(let message) = error else {
                Issue.record("Expected simulationFailure, got \(error)")
                return
            }
            #expect(message.contains("was not found"))
        } catch {
            Issue.record("Expected StudioError, got \(error)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func runDCSweepRejectsNonSourceComponent() async throws {
        let service = SimulationService()
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
        } catch let error as StudioError {
            guard case .simulationFailure(let message) = error else {
                Issue.record("Expected simulationFailure, got \(error)")
                return
            }
            #expect(message.contains("not an independent source"))
        } catch {
            Issue.record("Expected StudioError, got \(error)")
        }
    }
}
