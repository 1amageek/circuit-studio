import Foundation
import Testing
import PEXEngine
@testable import CircuitStudioApp

/// Tests the in-engine parasitic back-annotation: extracted capacitance → RC step
/// in CoreSpice → measured time constant matches R*C. Runs in-process (CoreSpice),
/// so it needs no external tool and executes in CI.
@Suite("Parasitic back-annotation (CoreSpice)")
struct ParasiticBackAnnotationServiceTests {

    private func ir(totalGroundCapF: Double, resistanceOhm: Double = 0) -> ParasiticIR {
        let net = ParasiticNet(
            name: NetName("n1"),
            nodes: [ParasiticNode(name: NodeName("n1"), kind: .internal, instancePath: nil, coordinate: nil)],
            totalGroundCapF: totalGroundCapF, totalCouplingCapF: 0, totalResistanceOhm: resistanceOhm
        )
        return ParasiticIR(
            version: ParasiticIR.currentVersion, cornerID: PEXCornerID("tt"),
            units: .canonical, nets: [net], elements: [], metadata: [:]
        )
    }

    @Test("Measured RC time constant matches R*C for the extracted capacitance")
    func backAnnotationMatchesAnalytic() async throws {
        let service = ParasiticBackAnnotationService()
        let result = try await service.backAnnotate(
            ir: ir(totalGroundCapF: 10e-15), driverResistanceOhm: 1_000_000
        )
        // 1 MΩ × 10 fF = 10 ns.
        #expect(abs(result.expectedTauS - 1e-8) < 1e-12)
        #expect(result.consistent, "measured τ \(result.measuredTauS) vs expected \(result.expectedTauS) (err \(result.relativeError))")
    }

    @Test("Scales with capacitance (4x C → 4x τ)")
    func scalesWithCapacitance() async throws {
        let service = ParasiticBackAnnotationService()
        let small = try await service.backAnnotate(ir: ir(totalGroundCapF: 5e-15), driverResistanceOhm: 1_000_000)
        let large = try await service.backAnnotate(ir: ir(totalGroundCapF: 20e-15), driverResistanceOhm: 1_000_000)
        #expect(small.consistent && large.consistent)
        let ratio = large.measuredTauS / small.measuredTauS
        #expect(abs(ratio - 4.0) < 0.4, "expected ~4x, got \(ratio)")
    }

    @Test("Zero capacitance fails loud")
    func zeroCapFailsLoud() async {
        let service = ParasiticBackAnnotationService()
        await #expect(throws: ParasiticBackAnnotationService.BackAnnotationError.noCapacitance) {
            _ = try await service.backAnnotate(ir: ir(totalGroundCapF: 0))
        }
    }
}
