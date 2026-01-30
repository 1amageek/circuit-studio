import SwiftUI
import CoreSpiceWaveform

/// Factory for creating WaveformViewModel instances with sample data for SwiftUI Previews.
@MainActor
enum WaveformPreview {

    /// ViewModel with no data loaded.
    static func emptyViewModel() -> WaveformViewModel {
        WaveformViewModel()
    }

    /// ViewModel loaded with a sample transient waveform (RC step response).
    static func transientViewModel() -> WaveformViewModel {
        let vm = WaveformViewModel()
        vm.load(waveform: sampleTransientWaveform())
        return vm
    }

    /// ViewModel loaded with a sample operating point result (single-point data).
    static func opViewModel() -> WaveformViewModel {
        let vm = WaveformViewModel()
        vm.load(waveform: sampleOPWaveform())
        return vm
    }

    /// ViewModel loaded with sample AC magnitude data.
    static func acViewModel() -> WaveformViewModel {
        let vm = WaveformViewModel()
        vm.load(waveform: sampleACWaveform())
        return vm
    }

    // MARK: - Sample Waveform Data

    /// Generates a sample OP waveform (voltage divider: V1=5V, R1=R2=1k).
    static func sampleOPWaveform() -> WaveformData {
        let variables = [
            VariableDescriptor.voltage(node: "in", index: 0),
            VariableDescriptor.voltage(node: "out", index: 1),
            VariableDescriptor.current(device: "V1", index: 2),
        ]

        let metadata = SimulationMetadata(
            title: "Operating Point",
            analysisType: .operatingPoint,
            pointCount: 1,
            variableCount: 3
        )

        return WaveformData(
            metadata: metadata,
            sweepVariable: VariableDescriptor(name: "point", unit: .dimensionless, type: .voltage, index: 0),
            sweepValues: [0.0],
            variables: variables,
            realData: [[5.0, 2.5, -2.5e-3]]
        )
    }

    /// Generates a sample transient waveform resembling an RC step response.
    static func sampleTransientWaveform() -> WaveformData {
        let pointCount = 200
        let stopTime = 20e-6
        let tau = 1e-6  // RC time constant

        var sweepValues: [Double] = []
        var realData: [[Double]] = []

        let variables = [
            VariableDescriptor.voltage(node: "in", index: 0),
            VariableDescriptor.voltage(node: "out", index: 1),
        ]

        for i in 0..<pointCount {
            let t = stopTime * Double(i) / Double(pointCount - 1)
            sweepValues.append(t)

            let vIn = t < 5e-6 ? 0.0 : 5.0
            let vOut: Double
            if t < 5e-6 {
                vOut = 0.0
            } else {
                let elapsed = t - 5e-6
                vOut = 5.0 * (1.0 - exp(-elapsed / tau))
            }
            realData.append([vIn, vOut])
        }

        let metadata = SimulationMetadata(
            title: "RC Step Response",
            analysisType: .transient,
            pointCount: pointCount,
            variableCount: 2
        )

        return WaveformData(
            metadata: metadata,
            sweepVariable: .time(),
            sweepValues: sweepValues,
            variables: variables,
            realData: realData
        )
    }

    /// Generates a sample AC magnitude waveform (lowpass filter).
    static func sampleACWaveform() -> WaveformData {
        let pointCount = 100
        let startFreq = 1.0
        let stopFreq = 1e9
        let fc = 159155.0  // 1/(2*pi*1k*1n)

        var sweepValues: [Double] = []
        var realData: [[Double]] = []

        let variables = [
            VariableDescriptor.voltage(node: "out", index: 0),
        ]

        for i in 0..<pointCount {
            let logF = log10(startFreq) + Double(i) / Double(pointCount - 1) * (log10(stopFreq) - log10(startFreq))
            let f = pow(10.0, logF)
            sweepValues.append(f)

            let ratio = f / fc
            let magnitude = 1.0 / sqrt(1.0 + ratio * ratio)
            let dB = 20.0 * log10(magnitude)
            realData.append([dB])
        }

        let metadata = SimulationMetadata(
            title: "AC Lowpass",
            analysisType: .ac,
            pointCount: pointCount,
            variableCount: 1
        )

        return WaveformData(
            metadata: metadata,
            sweepVariable: .frequency(),
            sweepValues: sweepValues,
            variables: variables,
            realData: realData
        )
    }
}
