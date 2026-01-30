import Foundation

/// Defines analysis commands, stimuli, and measurements for simulation.
public struct Testbench: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var analysisCommands: [AnalysisCommand]
    public var stimuli: [Stimulus]
    public var measurements: [Measurement]

    public init(
        id: UUID = UUID(),
        name: String,
        analysisCommands: [AnalysisCommand] = [],
        stimuli: [Stimulus] = [],
        measurements: [Measurement] = []
    ) {
        self.id = id
        self.name = name
        self.analysisCommands = analysisCommands
        self.stimuli = stimuli
        self.measurements = measurements
    }
}

/// An analysis command to execute.
public enum AnalysisCommand: Sendable, Codable, Hashable {
    case op
    case ac(ACSpec)
    case tran(TranSpec)
    case dcSweep(DCSweepSpec)
    case noise(NoiseSpec)
    case tf(TFSpec)
    case pz(PZSpec)
}

/// AC analysis specification.
public struct ACSpec: Sendable, Codable, Hashable {
    public var scaleType: ACScale
    public var numberOfPoints: Int
    public var startFrequency: Double
    public var stopFrequency: Double

    public init(scaleType: ACScale, numberOfPoints: Int, startFrequency: Double, stopFrequency: Double) {
        self.scaleType = scaleType
        self.numberOfPoints = numberOfPoints
        self.startFrequency = startFrequency
        self.stopFrequency = stopFrequency
    }
}

public enum ACScale: String, Sendable, Codable, Hashable {
    case decade = "dec"
    case octave = "oct"
    case linear = "lin"
}

/// Transient analysis specification.
public struct TranSpec: Sendable, Codable, Hashable {
    public var stopTime: Double
    public var stepTime: Double?
    public var startTime: Double?
    public var maxStep: Double?

    public init(stopTime: Double, stepTime: Double? = nil, startTime: Double? = nil, maxStep: Double? = nil) {
        self.stopTime = stopTime
        self.stepTime = stepTime
        self.startTime = startTime
        self.maxStep = maxStep
    }
}

/// DC sweep analysis specification.
public struct DCSweepSpec: Sendable, Codable, Hashable {
    public var source: String
    public var startValue: Double
    public var stopValue: Double
    public var stepValue: Double

    public init(source: String, startValue: Double, stopValue: Double, stepValue: Double) {
        self.source = source
        self.startValue = startValue
        self.stopValue = stopValue
        self.stepValue = stepValue
    }
}

/// Noise analysis specification.
public struct NoiseSpec: Sendable, Codable, Hashable {
    public var outputNode: String
    public var referenceNode: String?
    public var inputSource: String
    public var scaleType: ACScale
    public var numberOfPoints: Int
    public var startFrequency: Double
    public var stopFrequency: Double

    public init(
        outputNode: String,
        referenceNode: String? = nil,
        inputSource: String,
        scaleType: ACScale,
        numberOfPoints: Int,
        startFrequency: Double,
        stopFrequency: Double
    ) {
        self.outputNode = outputNode
        self.referenceNode = referenceNode
        self.inputSource = inputSource
        self.scaleType = scaleType
        self.numberOfPoints = numberOfPoints
        self.startFrequency = startFrequency
        self.stopFrequency = stopFrequency
    }
}

/// Transfer function specification.
public struct TFSpec: Sendable, Codable, Hashable {
    public var output: String
    public var input: String

    public init(output: String, input: String) {
        self.output = output
        self.input = input
    }
}

/// Pole-zero analysis specification.
public struct PZSpec: Sendable, Codable, Hashable {
    public var inputNode: String
    public var inputReference: String
    public var outputNode: String
    public var outputReference: String

    public init(inputNode: String, inputReference: String, outputNode: String, outputReference: String) {
        self.inputNode = inputNode
        self.inputReference = inputReference
        self.outputNode = outputNode
        self.outputReference = outputReference
    }
}

/// An input stimulus definition.
public struct Stimulus: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var sourceName: String
    public var waveform: WaveformType

    public init(id: UUID = UUID(), sourceName: String, waveform: WaveformType) {
        self.id = id
        self.sourceName = sourceName
        self.waveform = waveform
    }
}

/// Waveform type for stimuli.
public enum WaveformType: Sendable, Codable, Hashable {
    case dc(Double)
    case pulse(PulseSpec)
    case sin(SinSpec)
    case ac(magnitude: Double, phase: Double)
}

/// Pulse waveform parameters.
public struct PulseSpec: Sendable, Codable, Hashable {
    public var v1: Double
    public var v2: Double
    public var delay: Double
    public var riseTime: Double
    public var fallTime: Double
    public var pulseWidth: Double
    public var period: Double

    public init(v1: Double, v2: Double, delay: Double = 0, riseTime: Double = 0, fallTime: Double = 0, pulseWidth: Double, period: Double) {
        self.v1 = v1
        self.v2 = v2
        self.delay = delay
        self.riseTime = riseTime
        self.fallTime = fallTime
        self.pulseWidth = pulseWidth
        self.period = period
    }
}

/// Sinusoidal waveform parameters.
public struct SinSpec: Sendable, Codable, Hashable {
    public var offset: Double
    public var amplitude: Double
    public var frequency: Double
    public var delay: Double
    public var damping: Double

    public init(offset: Double = 0, amplitude: Double, frequency: Double, delay: Double = 0, damping: Double = 0) {
        self.offset = offset
        self.amplitude = amplitude
        self.frequency = frequency
        self.delay = delay
        self.damping = damping
    }
}

/// A measurement point definition.
public struct Measurement: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var expression: String

    public init(id: UUID = UUID(), name: String, expression: String) {
        self.id = id
        self.name = name
        self.expression = expression
    }
}
