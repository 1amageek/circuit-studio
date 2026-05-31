import Foundation

public struct StandardTimingLibraryBuildResult: Sendable, Hashable {
    public let library: TimingLibrary
    public let libraryArtifact: TimingLibraryArtifact
    public let combinationalReport: CombinationalTimingCharacterizationReport
    public let sequentialReport: SequentialTimingCharacterizationReport

    public init(
        library: TimingLibrary,
        libraryArtifact: TimingLibraryArtifact,
        combinationalReport: CombinationalTimingCharacterizationReport,
        sequentialReport: SequentialTimingCharacterizationReport
    ) {
        self.library = library
        self.libraryArtifact = libraryArtifact
        self.combinationalReport = combinationalReport
        self.sequentialReport = sequentialReport
    }
}

public protocol TimingLibraryBuilding: Sendable {
    func buildStandardLibrary(runID: String?) async throws -> StandardTimingLibraryBuildResult
}

public struct StandardTimingLibraryBuilder: TimingLibraryBuilding {
    public enum BuilderError: Error, LocalizedError, Equatable {
        case technologyMismatch(expectedModelHash: String, actualModelHash: String?)

        public var errorDescription: String? {
            switch self {
            case .technologyMismatch(let expected, let actual):
                return "Sequential timing report used device model hash \(actual ?? "nil"), expected \(expected)."
            }
        }
    }

    private let model: Level1DeviceModel
    private let cellCharacterizer: CellTimingCharacterizer
    private let sequentialCharacterizer: SequentialTimingCharacterizing
    private let inputSlews: [Double]
    private let outputLoads: [Double]

    public init(
        model: Level1DeviceModel = .sky130Like(),
        inputSlews: [Double] = [40e-12, 200e-12],
        outputLoads: [Double] = [1e-15, 4e-15, 12e-15],
        cellCharacterizer: CellTimingCharacterizer? = nil,
        sequentialCharacterizer: SequentialTimingCharacterizing? = nil
    ) {
        self.model = model
        self.inputSlews = inputSlews
        self.outputLoads = outputLoads
        self.cellCharacterizer = cellCharacterizer ?? CellTimingCharacterizer(
            model: model,
            inputSlews: inputSlews,
            outputLoads: outputLoads
        )
        self.sequentialCharacterizer = sequentialCharacterizer ?? SequentialTimingCharacterizer(
            model: model,
            outputLoads: outputLoads
        )
    }

    public func buildStandardLibrary(runID: String? = nil) async throws -> StandardTimingLibraryBuildResult {
        let cells: [CMOSGateNetlist] = [
            .inverter(name: "inv"),
            .nand(name: "nand2", inputs: ["A", "B"]),
            .nor(name: "nor2", inputs: ["A", "B"]),
        ]
        var library = TimingLibrary()
        var reportCells: [CombinationalTimingCharacterizationReport.Cell] = []
        for cell in cells {
            let timing = try await cellCharacterizer.characterize(cell)
            library.add(timing)
            reportCells.append(.init(
                cellName: cell.name,
                topologyHash: try TimingTopologyHasher.hash(cell),
                timing: timing,
                measurementIDs: [],
                status: .passed
            ))
        }

        let sequentialReport = try await sequentialCharacterizer.characterizeFlipFlop(
            Sky130DFFGenerator().netlist(name: "dff"),
            cellName: "dff"
        )
        let expectedModelHash = try TimingTopologyHasher.hashModel(model)
        guard sequentialReport.technology.deviceModelHash == expectedModelHash else {
            throw BuilderError.technologyMismatch(
                expectedModelHash: expectedModelHash,
                actualModelHash: sequentialReport.technology.deviceModelHash
            )
        }
        library.flipFlop = sequentialReport.timing

        let technology = sequentialReport.technology
        let combinationalReport = CombinationalTimingCharacterizationReport(
            technology: technology,
            inputSlews: inputSlews,
            outputLoads: outputLoads,
            cells: reportCells.sorted { $0.cellName < $1.cellName },
            status: .passed
        )
        var sources = reportCells.map {
            TimingModelSource(
                modelID: $0.cellName,
                modelKind: .combinationalCell,
                sourceType: .characterized,
                artifactIDs: ["combinational-characterization"]
            )
        }
        sources.append(TimingModelSource(
            modelID: sequentialReport.cellName,
            modelKind: .sequentialCell,
            sourceType: .characterized,
            artifactIDs: ["sequential-dff-characterization"]
        ))
        let libraryArtifact = TimingLibraryArtifact(
            runID: runID,
            technology: technology,
            library: library,
            modelSources: sources.sorted { $0.modelID < $1.modelID }
        )

        return StandardTimingLibraryBuildResult(
            library: library,
            libraryArtifact: libraryArtifact,
            combinationalReport: combinationalReport,
            sequentialReport: sequentialReport
        )
    }
}
