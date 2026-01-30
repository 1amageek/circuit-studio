import Foundation

/// An execution unit capturing the full input snapshot for a simulation run.
public struct Experiment: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public let createdAt: Date
    public var designID: UUID
    public var testbenchID: UUID
    public var cornerSet: CornerSet?
    public var sweepSpec: SweepSpec?
    public var monteCarloSpec: MonteCarloSpec?
    public var tags: [String]
    public var note: String

    public var designHash: String
    public var netlistHash: String
    public var settingsHash: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        designID: UUID,
        testbenchID: UUID,
        cornerSet: CornerSet? = nil,
        sweepSpec: SweepSpec? = nil,
        monteCarloSpec: MonteCarloSpec? = nil,
        tags: [String] = [],
        note: String = "",
        designHash: String = "",
        netlistHash: String = "",
        settingsHash: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.designID = designID
        self.testbenchID = testbenchID
        self.cornerSet = cornerSet
        self.sweepSpec = sweepSpec
        self.monteCarloSpec = monteCarloSpec
        self.tags = tags
        self.note = note
        self.designHash = designHash
        self.netlistHash = netlistHash
        self.settingsHash = settingsHash
    }
}
