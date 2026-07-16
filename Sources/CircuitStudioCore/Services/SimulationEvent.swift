import CoreSpiceWaveform

/// Events emitted during simulation.
public enum SimulationEvent: Sendable {
    case started
    case progress(Double, String)
    case waveformUpdate(WaveformData)
    case completed
    case failed(String)
    case cancelled
}
