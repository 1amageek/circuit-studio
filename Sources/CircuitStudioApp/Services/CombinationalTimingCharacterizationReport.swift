import Foundation

public struct CombinationalTimingCharacterizationReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

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
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: String = "combinational-characterization-report",
        technology: TimingTechnologyContext,
        inputSlews: [Double],
        outputLoads: [Double],
        cells: [Cell],
        measurementLogArtifactID: String? = nil,
        status: TimingRunStatus,
        warnings: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.technology = technology
        self.inputSlews = inputSlews
        self.outputLoads = outputLoads
        self.cells = cells
        self.measurementLogArtifactID = measurementLogArtifactID
        self.status = status
        self.warnings = warnings
    }
}
