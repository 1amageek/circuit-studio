import Foundation
import Testing
@testable import CircuitStudioCore

/// Live ngspice-oracle cross-check: the SAME post-layout deck (level-1 devices +
/// parasitics, in CoreSpice's envelope) is run in CoreSpice and ngspice and the
/// waveforms must agree. Gated on an ngspice install; the loud-failure guard runs
/// everywhere.
@Suite("Post-layout ngspice oracle")
struct PostLayoutOracleServiceTests {

    static let available = PostLayoutOracleService.ngspiceAvailable()

    @Test("CoreSpice agrees with ngspice on a level-1 inverter + parasitics deck",
          .enabled(if: PostLayoutOracleServiceTests.available), .timeLimit(.minutes(6)))
    func crossCheckAgrees() async throws {
        // A loaded gate with gentle input edges: a realistic post-layout RC-smoothed
        // response where a raw max|ΔV| comparison is robust (sharp logic edges put a
        // large instantaneous ΔV at the transition for any sub-ps cross-tool skew).
        let deck = """
        * oracle: level-1 inverter + extracted-style parasitics (loaded)
        VDD vdd 0 dc 1.8
        VIN in 0 PULSE(0 1.8 2n 1n 1n 8n 16n)
        MN out in 0 0 NM W=2u L=0.15u
        MP out in vdd vdd PM W=4u L=0.15u
        CL out 0 30f
        CC in out 2f
        .model NM NMOS level=1 vto=0.45 kp=120u lambda=0.1 gamma=0.4 phi=0.65
        .model PM PMOS level=1 vto=-0.45 kp=40u lambda=0.1 gamma=0.4 phi=0.65
        """
        let oracle = PostLayoutOracleService()
        let agreement = try await oracle.crossCheck(
            deck: deck,
            command: .tran(TranSpec(stopTime: 32e-9, stepTime: 0.05e-9)),
            probes: ["out"],
            toleranceV: 0.05
        )
        #expect(agreement.isConsistent,
                "CoreSpice vs ngspice max ΔV(out) = \(agreement.maxDivergenceV) V (tol \(agreement.toleranceV))")
        #expect(agreement.probes.first?.probe == "out")
        #expect((agreement.probes.first?.sampleCount ?? 0) > 0)
    }

    @Test("An empty probe set fails loud (no silent pass)")
    func emptyProbesFailLoud() async throws {
        let oracle = PostLayoutOracleService()
        await #expect(throws: PostLayoutOracleService.OracleError.noProbes) {
            _ = try await oracle.crossCheck(
                deck: "* empty\n",
                command: .tran(TranSpec(stopTime: 1e-9, stepTime: 1e-12)),
                probes: []
            )
        }
    }

    @Test("Oracle agreement rejects invalid numerical states")
    func invalidAgreementStatesFailClosed() async throws {
        #expect(throws: PostLayoutOracleAgreementError.self) {
            _ = try PostLayoutProbeAgreement(
                probe: "out",
                maxAbsoluteDeltaV: .infinity,
                sampleCount: 1
            )
        }
        #expect(throws: PostLayoutOracleAgreementError.self) {
            _ = try PostLayoutProbeAgreement(
                probe: "out",
                maxAbsoluteDeltaV: 0,
                sampleCount: 0
            )
        }
        #expect(throws: PostLayoutOracleAgreementError.self) {
            _ = try PostLayoutOracleAgreement(probes: [], toleranceV: 0.1)
        }
        await #expect(throws: PostLayoutOracleAgreementError.self) {
            _ = try await PostLayoutOracleService().crossCheck(
                deck: "* tolerance validation must precede execution\n",
                command: .tran(TranSpec(stopTime: 1e-9, stepTime: 1e-12)),
                probes: ["out"],
                toleranceV: .nan
            )
        }
    }

    @Test("Probe identity rejects case-insensitive duplicates before execution")
    func caseInsensitiveDuplicateProbesFailBeforeExecution() async throws {
        let lowercase = try PostLayoutProbeAgreement(
            probe: "out",
            maxAbsoluteDeltaV: 0,
            sampleCount: 1
        )
        let uppercase = try PostLayoutProbeAgreement(
            probe: "OUT",
            maxAbsoluteDeltaV: 0,
            sampleCount: 1
        )
        #expect(throws: PostLayoutOracleAgreementError.self) {
            _ = try PostLayoutOracleAgreement(
                probes: [lowercase, uppercase],
                toleranceV: 0.1
            )
        }
        await #expect(throws: PostLayoutOracleAgreementError.self) {
            _ = try await PostLayoutOracleService().crossCheck(
                deck: "* duplicate probes must fail before simulation\n",
                command: .tran(TranSpec(stopTime: 1e-9, stepTime: 1e-12)),
                probes: ["out", "OUT"],
                toleranceV: 0.1
            )
        }
    }

    @Test("A deck outside CoreSpice's envelope is refused (no false ngspice-vs-ngspice agreement)")
    func outOfEnvelopeDeckRefused() async throws {
        // A BSIM-class device routes CoreSpice's own runAnalysis to ngspice; without
        // the guard the cross-check would compare ngspice against itself and "agree".
        let deck = """
        * out-of-envelope deck
        V1 in 0 dc 1
        M1 out in 0 0 NCH w=1u l=0.15u
        .model NCH nmos level=72
        """
        let oracle = PostLayoutOracleService()
        await #expect(throws: PostLayoutOracleService.OracleError.deckRequiresExternalModels) {
            _ = try await oracle.crossCheck(
                deck: deck,
                command: .tran(TranSpec(stopTime: 1e-9, stepTime: 1e-12)),
                probes: ["out"]
            )
        }
    }
}
