import CoreSpiceIO
import CoreSpiceWaveform
import Foundation

/// Provides bounded waveform data access for presentation and analysis.
public protocol WaveformProviding: Sendable {
    func fetch(
        waveform: WaveformData,
        variables: [String],
        range: ClosedRange<Double>?,
        maxPoints: Int
    ) -> WaveformData

    func listVariables(waveform: WaveformData) -> [VariableDescriptor]
}
