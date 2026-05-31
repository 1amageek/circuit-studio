import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Timing characterization cache")
struct TimingCharacterizationCacheTests {
    @Test("Cell timing cache reuses artifact-backed results", .timeLimit(.minutes(1)))
    func cellTimingCacheReusesArtifactBackedResults() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("timing-characterization-cache-cell-\(UUID().uuidString)", isDirectory: true)
        defer {
            Self.removeTemporaryDirectoryIfPresent(directory)
        }

        let cache = TimingCharacterizationCache(directory: directory)
        let cell = CMOSGateNetlist.inverter(name: "inv")
        let counter = CallCounter()
        let first = try await cache.cellTiming(
            cell: cell,
            model: .sky130Like(),
            inputSlews: [40e-12],
            outputLoads: [1e-15]
        ) {
            let count = await counter.increment()
            return Self.cellTimingFixture(cellName: "inv", value: Double(count) * 10e-12)
        }
        let second = try await cache.cellTiming(
            cell: cell,
            model: .sky130Like(),
            inputSlews: [40e-12],
            outputLoads: [1e-15]
        ) {
            Issue.record("Cell timing cache missed an identical characterization request.")
            return Self.cellTimingFixture(cellName: "inv", value: 999e-12)
        }

        #expect(first == second)
        #expect(await counter.value() == 1)
    }

    @Test("Sequential timing cache reuses artifact-backed reports", .timeLimit(.minutes(1)))
    func sequentialTimingCacheReusesArtifactBackedReports() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("timing-characterization-cache-seq-\(UUID().uuidString)", isDirectory: true)
        defer {
            Self.removeTemporaryDirectoryIfPresent(directory)
        }

        let cache = TimingCharacterizationCache(directory: directory)
        let netlist = Sky130DFFGenerator().netlist(name: "dff")
        let counter = CallCounter()
        let first = try await cache.sequentialReport(
            netlist: netlist,
            cellName: "dff",
            model: .sky130Like(),
            clockSlew: 80e-12,
            dataSlew: 80e-12,
            outputLoads: [1e-15],
            setupHoldSearchWindow: 300e-12,
            setupHoldSearchResolution: 20e-12,
            maxSearchIterations: 4
        ) {
            let count = await counter.increment()
            return try Self.sequentialReportFixture(netlist: netlist, setupTime: Double(count) * 20e-12)
        }
        let second = try await cache.sequentialReport(
            netlist: netlist,
            cellName: "dff",
            model: .sky130Like(),
            clockSlew: 80e-12,
            dataSlew: 80e-12,
            outputLoads: [1e-15],
            setupHoldSearchWindow: 300e-12,
            setupHoldSearchResolution: 20e-12,
            maxSearchIterations: 4
        ) {
            Issue.record("Sequential timing cache missed an identical characterization request.")
            return try Self.sequentialReportFixture(netlist: netlist, setupTime: 999e-12)
        }

        #expect(first == second)
        #expect(await counter.value() == 1)
    }

    @Test("Standard timing builder reuses cache without executing characterizers", .timeLimit(.minutes(1)))
    func standardTimingBuilderReusesCacheWithoutExecutingCharacterizers() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("timing-characterization-cache-builder-\(UUID().uuidString)", isDirectory: true)
        defer {
            Self.removeTemporaryDirectoryIfPresent(directory)
        }

        let cache = TimingCharacterizationCache(directory: directory)
        let inputSlews = [40e-12, 200e-12]
        let outputLoads = [1e-15, 4e-15, 12e-15]
        let cells: [CMOSGateNetlist] = [
            .inverter(name: "inv"),
            .nand(name: "nand2", inputs: ["A", "B"]),
            .nor(name: "nor2", inputs: ["A", "B"]),
        ]
        for (index, cell) in cells.enumerated() {
            _ = try await cache.cellTiming(
                cell: cell,
                model: .sky130Like(),
                inputSlews: inputSlews,
                outputLoads: outputLoads
            ) {
                Self.cellTimingFixture(cell: cell, value: Double(index + 1) * 10e-12)
            }
        }

        let dffNetlist = Sky130DFFGenerator().netlist(name: "dff")
        _ = try await cache.sequentialReport(
            netlist: dffNetlist,
            cellName: "dff",
            model: .sky130Like(),
            clockSlew: 80e-12,
            dataSlew: 80e-12,
            outputLoads: outputLoads,
            setupHoldSearchWindow: 600e-12,
            setupHoldSearchResolution: 5e-12,
            maxSearchIterations: 8
        ) {
            try Self.sequentialReportFixture(
                netlist: dffNetlist,
                setupTime: 20e-12,
                outputLoads: outputLoads,
                setupHoldSearchWindow: 600e-12,
                setupHoldSearchResolution: 5e-12
            )
        }

        let build = try await StandardTimingLibraryBuilder(
            cache: cache,
            executionPolicy: FailingTimingCharacterizationExecutionPolicy()
        ).buildStandardLibrary(runID: "cache-hit")

        #expect(build.library.cells.count == 3)
        #expect(build.library.flipFlop != nil)
        #expect(build.libraryArtifact.runID == "cache-hit")
    }

    @Test("Concurrent waiters observe shared cache persistence failures", .timeLimit(.minutes(1)))
    func concurrentWaitersObserveSharedCachePersistenceFailures() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("timing-characterization-cache-file-\(UUID().uuidString)", isDirectory: false)
        let created = FileManager.default.createFile(atPath: directory.path, contents: Data())
        #expect(created)
        defer {
            Self.removeTemporaryDirectoryIfPresent(directory)
        }

        let cache = TimingCharacterizationCache(directory: directory)
        let cell = CMOSGateNetlist.inverter(name: "inv")
        let gate = AsyncGate()
        let first = Task {
            try await cache.cellTiming(
                cell: cell,
                model: .sky130Like(),
                inputSlews: [40e-12],
                outputLoads: [1e-15]
            ) {
                await gate.wait()
                return Self.cellTimingFixture(cellName: "inv", value: 10e-12)
            }
        }
        let second = Task {
            try await cache.cellTiming(
                cell: cell,
                model: .sky130Like(),
                inputSlews: [40e-12],
                outputLoads: [1e-15]
            ) {
                Issue.record("Second concurrent waiter executed an independent characterization.")
                return Self.cellTimingFixture(cellName: "inv", value: 20e-12)
            }
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        await gate.open()

        let firstResult = await first.result
        let secondResult = await second.result
        #expect(Self.isPersistenceFailure(firstResult))
        #expect(Self.isPersistenceFailure(secondResult))
    }

    private static func cellTimingFixture(cellName: String, value: Double) -> CellTiming {
        cellTimingFixture(inputPins: ["A"], cellName: cellName, value: value)
    }

    private static func cellTimingFixture(cell: CMOSGateNetlist, value: Double) -> CellTiming {
        let inputPins = Set(cell.devices.map(\.gate)).sorted()
        return cellTimingFixture(inputPins: inputPins, cellName: cell.name, value: value)
    }

    private static func cellTimingFixture(
        inputPins: [String],
        cellName: String,
        value: Double
    ) -> CellTiming {
        let lut = TimingLUT.constant(value)
        return CellTiming(
            cellName: cellName,
            inputCapacitance: Dictionary(uniqueKeysWithValues: inputPins.map { ($0, 1e-15) }),
            arcs: inputPins.map {
                TimingArc(
                    inputPin: $0,
                    sense: .negativeUnate,
                    delayRise: lut,
                    delayFall: lut,
                    transitionRise: lut,
                    transitionFall: lut
                )
            }
        )
    }

    private static func sequentialReportFixture(
        netlist: GateLevelNetlist,
        setupTime: Double,
        outputLoads: [Double] = [1e-15],
        setupHoldSearchWindow: Double = 300e-12,
        setupHoldSearchResolution: Double = 20e-12
    ) throws -> SequentialTimingCharacterizationReport {
        let timing = SequentialTiming(
            clkToQRise: try singleSlewLUT(outputLoads: outputLoads, value: 100e-12),
            clkToQFall: try singleSlewLUT(outputLoads: outputLoads, value: 110e-12),
            qTransitionRise: try singleSlewLUT(outputLoads: outputLoads, value: 30e-12),
            qTransitionFall: try singleSlewLUT(outputLoads: outputLoads, value: 35e-12),
            setupTime: setupTime,
            holdTime: 10e-12,
            dataCapacitance: 1e-15,
            clockCapacitance: 2e-15
        )
        let model = Level1DeviceModel.sky130Like()
        return SequentialTimingCharacterizationReport(
            cellName: "dff",
            topologyHash: try TimingTopologyHasher.hash(netlist),
            activeClockEdge: .rising,
            technology: TimingTechnologyContext(
                processName: "sky130-like-level1",
                cornerID: "tt",
                supplyVoltage: model.supplyVoltage,
                deviceModelID: "level1-sky130-like",
                deviceModelHash: try TimingTopologyHasher.hashModel(model)
            ),
            characterizationGrid: SequentialTimingCharacterizationGrid(
                clockSlews: [80e-12],
                dataSlews: [80e-12],
                outputLoads: outputLoads,
                setupHoldSearchResolution: setupHoldSearchResolution,
                setupHoldSearchWindow: setupHoldSearchWindow
            ),
            timing: timing,
            clkToQMeasurements: [],
            qTransitionMeasurements: [],
            setupMeasurements: [],
            holdMeasurements: [],
            status: .passed
        )
    }

    private static func singleSlewLUT(outputLoads: [Double], value: Double) throws -> TimingLUT {
        try TimingLUT(
            inputSlews: [80e-12],
            outputLoads: outputLoads,
            values: [outputLoads.map { _ in value }]
        )
    }

    private static func removeTemporaryDirectoryIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove temporary timing characterization cache directory: \(error)")
        }
    }

    private static func isPersistenceFailure(_ result: Result<CellTiming, Error>) -> Bool {
        guard case .failure(let error) = result,
              let cacheError = error as? TimingCharacterizationCache.CacheError
        else {
            return false
        }
        switch cacheError {
        case .directoryCreationFailed, .writeFailed:
            return true
        case .readFailed:
            return false
        }
    }
}

private enum UnexpectedTimingCharacterizationExecution: Error {
    case executed
}

private struct FailingTimingCharacterizationExecutionPolicy: TimingCharacterizationExecutionPolicy {
    func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        throw UnexpectedTimingCharacterizationExecution.executed
    }
}

private actor CallCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func value() -> Int {
        count
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
