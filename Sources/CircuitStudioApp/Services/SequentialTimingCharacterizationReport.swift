import Foundation

public enum SequentialTimingMetric: String, Sendable, Hashable, Codable {
    case clkToQRise
    case clkToQFall
    case qTransitionRise
    case qTransitionFall
    case setupTime
    case holdTime
}

public enum TimingMeasurementMethod: String, Sendable, Hashable, Codable {
    case thresholdCrossing
    case binarySearch
}

public enum TimingClockEdge: String, Sendable, Hashable, Codable {
    case rising
    case falling
}

public struct SequentialTimingCharacterizationGrid: Sendable, Hashable, Codable {
    public let clockSlews: [Double]
    public let dataSlews: [Double]
    public let outputLoads: [Double]
    public let setupHoldSearchResolution: Double
    public let setupHoldSearchWindow: Double

    public init(
        clockSlews: [Double],
        dataSlews: [Double],
        outputLoads: [Double],
        setupHoldSearchResolution: Double,
        setupHoldSearchWindow: Double
    ) {
        self.clockSlews = clockSlews
        self.dataSlews = dataSlews
        self.outputLoads = outputLoads
        self.setupHoldSearchResolution = setupHoldSearchResolution
        self.setupHoldSearchWindow = setupHoldSearchWindow
    }
}

public struct SequentialTimingMeasurementSummary: Sendable, Hashable, Codable {
    public let id: String
    public let metric: SequentialTimingMetric
    public let clockSlew: Double
    public let dataSlew: Double?
    public let outputLoad: Double?
    public let valueSeconds: Double
    public let method: TimingMeasurementMethod
    public let status: TimingRunStatus
    public let deckArtifactID: String?
    public let waveformArtifactID: String?
    public let passingOffsetSeconds: Double?
    public let failingOffsetSeconds: Double?
    public let capturedValue: Bool?
    public let expectedValue: Bool?

    public init(
        id: String,
        metric: SequentialTimingMetric,
        clockSlew: Double,
        dataSlew: Double? = nil,
        outputLoad: Double? = nil,
        valueSeconds: Double,
        method: TimingMeasurementMethod,
        status: TimingRunStatus,
        deckArtifactID: String? = nil,
        waveformArtifactID: String? = nil,
        passingOffsetSeconds: Double? = nil,
        failingOffsetSeconds: Double? = nil,
        capturedValue: Bool? = nil,
        expectedValue: Bool? = nil
    ) {
        self.id = id
        self.metric = metric
        self.clockSlew = clockSlew
        self.dataSlew = dataSlew
        self.outputLoad = outputLoad
        self.valueSeconds = valueSeconds
        self.method = method
        self.status = status
        self.deckArtifactID = deckArtifactID
        self.waveformArtifactID = waveformArtifactID
        self.passingOffsetSeconds = passingOffsetSeconds
        self.failingOffsetSeconds = failingOffsetSeconds
        self.capturedValue = capturedValue
        self.expectedValue = expectedValue
    }
}

public struct SequentialTimingCharacterizationReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    private static let expectedKind = "sequential-characterization-report"

    public let schemaVersion: Int
    public let kind: String
    public let cellName: String
    public let topologyHash: String
    public let activeClockEdge: TimingClockEdge
    public let technology: TimingTechnologyContext
    public let characterizationGrid: SequentialTimingCharacterizationGrid
    public let timing: SequentialTiming
    public let clkToQMeasurements: [SequentialTimingMeasurementSummary]
    public let qTransitionMeasurements: [SequentialTimingMeasurementSummary]
    public let setupMeasurements: [SequentialTimingMeasurementSummary]
    public let holdMeasurements: [SequentialTimingMeasurementSummary]
    public let measurementLogArtifactID: String?
    public let status: TimingRunStatus
    public let warnings: [String]

    public init(
        cellName: String,
        topologyHash: String,
        activeClockEdge: TimingClockEdge,
        technology: TimingTechnologyContext,
        characterizationGrid: SequentialTimingCharacterizationGrid,
        timing: SequentialTiming,
        clkToQMeasurements: [SequentialTimingMeasurementSummary],
        qTransitionMeasurements: [SequentialTimingMeasurementSummary],
        setupMeasurements: [SequentialTimingMeasurementSummary],
        holdMeasurements: [SequentialTimingMeasurementSummary],
        measurementLogArtifactID: String? = nil,
        status: TimingRunStatus,
        warnings: [String] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.expectedKind
        self.cellName = cellName
        self.topologyHash = topologyHash
        self.activeClockEdge = activeClockEdge
        self.technology = technology
        self.characterizationGrid = characterizationGrid
        self.timing = timing
        self.clkToQMeasurements = clkToQMeasurements
        self.qTransitionMeasurements = qTransitionMeasurements
        self.setupMeasurements = setupMeasurements
        self.holdMeasurements = holdMeasurements
        self.measurementLogArtifactID = measurementLogArtifactID
        self.status = status
        self.warnings = warnings
    }
}

extension SequentialTimingCharacterizationReport {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case cellName
        case topologyHash
        case activeClockEdge
        case technology
        case characterizationGrid
        case timing
        case clkToQMeasurements
        case qTransitionMeasurements
        case setupMeasurements
        case holdMeasurements
        case measurementLogArtifactID
        case status
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported sequential characterization report schema version \(decodedSchemaVersion)."
            )
        }
        let decodedKind = try container.decode(String.self, forKey: .kind)
        guard decodedKind == Self.expectedKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported sequential characterization report kind \(decodedKind)."
            )
        }
        schemaVersion = decodedSchemaVersion
        kind = decodedKind
        cellName = try container.decode(String.self, forKey: .cellName)
        topologyHash = try container.decode(String.self, forKey: .topologyHash)
        activeClockEdge = try container.decode(TimingClockEdge.self, forKey: .activeClockEdge)
        technology = try container.decode(TimingTechnologyContext.self, forKey: .technology)
        characterizationGrid = try container.decode(SequentialTimingCharacterizationGrid.self, forKey: .characterizationGrid)
        timing = try container.decode(SequentialTiming.self, forKey: .timing)
        clkToQMeasurements = try container.decode([SequentialTimingMeasurementSummary].self, forKey: .clkToQMeasurements)
        qTransitionMeasurements = try container.decode([SequentialTimingMeasurementSummary].self, forKey: .qTransitionMeasurements)
        setupMeasurements = try container.decode([SequentialTimingMeasurementSummary].self, forKey: .setupMeasurements)
        holdMeasurements = try container.decode([SequentialTimingMeasurementSummary].self, forKey: .holdMeasurements)
        measurementLogArtifactID = try container.decodeIfPresent(String.self, forKey: .measurementLogArtifactID)
        status = try container.decode(TimingRunStatus.self, forKey: .status)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}
