import Foundation

public struct CombinationalTimingCharacterizationReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    private static let expectedKind = "combinational-characterization-report"

    public struct Cell: Sendable, Hashable, Codable {
        public let cellName: String
        public let topologyHash: String
        public let timing: CellTiming
        public let measurementIDs: [String]
        public let status: TimingRunStatus

        public init(
            cellName: String,
            topologyHash: String,
            timing: CellTiming,
            measurementIDs: [String],
            status: TimingRunStatus
        ) {
            self.cellName = cellName
            self.topologyHash = topologyHash
            self.timing = timing
            self.measurementIDs = measurementIDs
            self.status = status
        }
    }

    public let schemaVersion: Int
    public let kind: String
    public let technology: TimingTechnologyContext
    public let inputSlews: [Double]
    public let outputLoads: [Double]
    public let cells: [Cell]
    public let measurementLogArtifactID: String?
    public let status: TimingRunStatus
    public let warnings: [String]

    public init(
        technology: TimingTechnologyContext,
        inputSlews: [Double],
        outputLoads: [Double],
        cells: [Cell],
        measurementLogArtifactID: String? = nil,
        status: TimingRunStatus,
        warnings: [String] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.expectedKind
        self.technology = technology
        self.inputSlews = inputSlews
        self.outputLoads = outputLoads
        self.cells = cells
        self.measurementLogArtifactID = measurementLogArtifactID
        self.status = status
        self.warnings = warnings
    }
}

extension CombinationalTimingCharacterizationReport {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case technology
        case inputSlews
        case outputLoads
        case cells
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
                debugDescription: "Unsupported combinational characterization report schema version \(decodedSchemaVersion)."
            )
        }
        let decodedKind = try container.decode(String.self, forKey: .kind)
        guard decodedKind == Self.expectedKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported combinational characterization report kind \(decodedKind)."
            )
        }
        schemaVersion = decodedSchemaVersion
        kind = decodedKind
        technology = try container.decode(TimingTechnologyContext.self, forKey: .technology)
        inputSlews = try container.decode([Double].self, forKey: .inputSlews)
        outputLoads = try container.decode([Double].self, forKey: .outputLoads)
        cells = try container.decode([Cell].self, forKey: .cells)
        measurementLogArtifactID = try container.decodeIfPresent(String.self, forKey: .measurementLogArtifactID)
        status = try container.decode(TimingRunStatus.self, forKey: .status)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}
