import SwiftUI
import CoreSpiceWaveform
import CircuitStudioCore

// MARK: - SPICE Netlists

/// Standard SPICE netlists for preview simulation, validated by end-to-end tests.
public enum SPICENetlists {

    /// Voltage divider: V(out) = 2.5V (J1)
    public static let voltageDividerOP = """
    Voltage divider
    V1 in 0 5
    R1 in out 1k
    R2 out 0 1k
    .op
    .end
    """

    /// RC step response with PULSE source: tau = RC = 1kΩ × 1nF = 1μs (J5)
    public static let rcPulseTransient = """
    RC step response
    V1 in 0 PULSE(0 5 1u 0.1u 0.1u 10u 20u)
    R1 in out 1k
    C1 out 0 1n
    .tran 0.1u 20u
    .end
    """

    /// RC lowpass AC sweep: fc = 1/(2π × 1kΩ × 1μF) ≈ 159 Hz (J7)
    public static let rcLowpassAC = """
    AC lowpass
    V1 in 0 AC 1
    R1 in out 1k
    C1 out 0 1u
    .ac dec 20 1 1e6
    .end
    """

    /// Diode forward bias: V(anode) ≈ 0.6–0.7V (J2)
    public static let diodeOP = """
    Diode bias
    V1 in 0 5
    R1 in anode 1k
    D1 anode 0 DMOD
    .model DMOD D IS=1e-14 N=1.0
    .op
    .end
    """

    /// VCVS gain stage: V(out) = 10V (J8)
    public static let vcvsOP = """
    VCVS gain
    V1 in 0 1
    R1 in 0 1k
    E1 out 0 in 0 10
    R2 out 0 1k
    .op
    .end
    """

    /// RLC damped oscillation: R=50Ω, L=1μH, C=100pF, f₀≈15.9MHz, Q=2
    public static let rlcDampedTransient = """
    RLC damped oscillation
    V1 in 0 PULSE(0 5 0 0.1n 0.1n 250n 500n)
    R1 in mid 50
    L1 mid out 1u
    C1 out 0 100p
    .tran 0.5n 500n
    .end
    """

    /// 3-stage CMOS ring oscillator: requires .ic for symmetry breaking
    public static let ringOscillator3Stage = """
    Ring oscillator 3-stage
    VDD vdd 0 dc 3.3
    MP1 b a vdd vdd PMOD W=20u L=1u
    MN1 b a 0 0 NMOD W=10u L=1u
    C1 b 0 50f
    MP2 c b vdd vdd PMOD W=20u L=1u
    MN2 c b 0 0 NMOD W=10u L=1u
    C2 c 0 50f
    MP3 a c vdd vdd PMOD W=20u L=1u
    MN3 a c 0 0 NMOD W=10u L=1u
    C3 a 0 50f
    RKICK a akick 1Meg
    VKICK akick 0 PULSE(0.1 0 0 0.1n 0 0 1)
    .model PMOD PMOS level=1 vto=-0.7 kp=50e-6
    .model NMOD NMOS level=1 vto=0.7 kp=110e-6
    .tran 0.01n 50n
    .end
    """

    /// BJT astable multivibrator: period ≈ 2×0.693×RB×CC ≈ 13.9μs
    public static let astableMultivibrator = """
    Astable multivibrator
    VCC vcc 0 dc 5
    RC1 vcc c1 1k
    RC2 vcc c2 1k
    RB1 vcc b1 10k
    RB2 vcc b2 10k
    CC1 c1 b2 1n
    CC2 c2 b1 1n
    Q1 c1 b1 0 QMOD
    Q2 c2 b2 0 QMOD
    RB3 b1 0 100k
    .model QMOD NPN bf=100 is=1e-14
    .tran 0.1u 200u
    .end
    """
}

// MARK: - Preview View

/// Runs actual SPICE simulation and displays the result.
/// Use this in `#Preview` to verify real engine output.
public struct SimulationPreviewView: View {
    public let spiceSource: String
    @State private var viewModel = WaveformViewModel()
    @State private var error: String?
    @State private var isRunning = true

    public init(spiceSource: String) {
        self.spiceSource = spiceSource
    }

    public var body: some View {
        Group {
            if let error {
                ContentUnavailableView(
                    "Simulation Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if isRunning {
                ProgressView("Running SPICE simulation...")
            } else {
                WaveformResultView(viewModel: viewModel)
            }
        }
        .task {
            let service = SimulationService()
            do {
                let result = try await service.runSPICE(source: spiceSource, fileName: nil)
                if let waveform = result.waveform {
                    viewModel.load(waveform: waveform)
                }
            } catch {
                self.error = error.localizedDescription
            }
            isRunning = false
        }
    }
}

// MARK: - Empty ViewModel

@MainActor
enum WaveformPreview {

    /// ViewModel with no data loaded (for empty-state UI testing).
    static func emptyViewModel() -> WaveformViewModel {
        WaveformViewModel()
    }
}
