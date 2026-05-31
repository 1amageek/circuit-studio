import CircuitStudioCore
import Foundation
@testable import CircuitStudioApp

struct CachedStandardTimingLibraryBuilder: TimingLibraryBuilding {
    func buildStandardLibrary(runID: String?) async throws -> StandardTimingLibraryBuildResult {
        try await TimingCharacterizationTestCache.shared.standardBuild(runID: runID)
    }
}

struct CachedTimingPathValidator: TimingPathValidating {
    func validate(
        path: TimingPath,
        in netlist: SequentialNetlist,
        toleranceFraction: Double
    ) async throws -> STAvsSPICEValidator.Result {
        try await TimingCharacterizationTestCache.shared.validatePath(
            path,
            in: netlist,
            toleranceFraction: toleranceFraction
        )
    }
}

enum TimingCharacterizationTestSupport {
    static func withExclusiveSpiceSlot<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await NgspiceConcurrencyGate.shared.acquireExclusive()
        do {
            let result = try await operation()
            await NgspiceConcurrencyGate.shared.releaseExclusive()
            return result
        } catch {
            await NgspiceConcurrencyGate.shared.releaseExclusive()
            throw error
        }
    }
}

actor TimingCharacterizationTestCache {
    static let shared = TimingCharacterizationTestCache()

    private struct CellKey: Hashable {
        let cell: CMOSGateNetlist
        let inputSlews: [Double]
        let outputLoads: [Double]
    }

    private struct ValidationKey: Hashable {
        let path: TimingPath
        let netlist: SequentialNetlist
        let toleranceFraction: Double
    }

    private var cellTimings: [CellKey: CellTiming] = [:]
    private var pendingCellTimings: [CellKey: Task<CellTiming, Error>] = [:]
    private var sizedLibrary: TimingLibrary?
    private var pendingSizedLibrary: Task<TimingLibrary, Error>?
    private var flipFlopReport: SequentialTimingCharacterizationReport?
    private var pendingFlipFlopReport: Task<SequentialTimingCharacterizationReport, Error>?
    private var standardBuild: StandardTimingLibraryBuildResult?
    private var pendingStandardBuild: Task<StandardTimingLibraryBuildResult, Error>?
    private var validations: [ValidationKey: STAvsSPICEValidator.Result] = [:]
    private var pendingValidations: [ValidationKey: Task<STAvsSPICEValidator.Result, Error>] = [:]

    func characterizeCell(
        _ cell: CMOSGateNetlist,
        inputSlews: [Double],
        outputLoads: [Double]
    ) async throws -> CellTiming {
        let key = CellKey(cell: cell, inputSlews: inputSlews, outputLoads: outputLoads)
        if let cached = cellTimings[key] { return cached }
        if let pending = pendingCellTimings[key] {
            return try await pending.value
        }

        let task = Task {
            try await TimingCharacterizationTestSupport.withExclusiveSpiceSlot {
                try await CellTimingCharacterizer(
                    inputSlews: inputSlews,
                    outputLoads: outputLoads
                ).characterize(cell)
            }
        }
        pendingCellTimings[key] = task
        do {
            let timing = try await task.value
            cellTimings[key] = timing
            pendingCellTimings[key] = nil
            return timing
        } catch {
            pendingCellTimings[key] = nil
            throw error
        }
    }

    func characterizedFlipFlopReport() async throws -> SequentialTimingCharacterizationReport {
        if let cached = flipFlopReport { return cached }
        if let pending = pendingFlipFlopReport {
            return try await pending.value
        }

        let task = Task {
            try await TimingCharacterizationTestSupport.withExclusiveSpiceSlot {
                try await SequentialTimingCharacterizer(
                    outputLoads: [1e-15],
                    setupHoldSearchWindow: 300e-12,
                    setupHoldSearchResolution: 20e-12,
                    maxSearchIterations: 4
                ).characterizeFlipFlop(
                    Sky130DFFGenerator().netlist(name: "dff"),
                    cellName: "dff"
                )
            }
        }
        pendingFlipFlopReport = task
        do {
            let report = try await task.value
            flipFlopReport = report
            pendingFlipFlopReport = nil
            return report
        } catch {
            pendingFlipFlopReport = nil
            throw error
        }
    }

    func standardBuild(runID: String?) async throws -> StandardTimingLibraryBuildResult {
        if let cached = standardBuild {
            return copy(cached, runID: runID)
        }
        if let pending = pendingStandardBuild {
            return copy(try await pending.value, runID: runID)
        }

        let task = Task {
            try await TimingCharacterizationTestSupport.withExclusiveSpiceSlot {
                try await StandardTimingLibraryBuilder().buildStandardLibrary(runID: nil)
            }
        }
        pendingStandardBuild = task
        do {
            let build = try await task.value
            standardBuild = build
            pendingStandardBuild = nil
            return copy(build, runID: runID)
        } catch {
            pendingStandardBuild = nil
            throw error
        }
    }

    func sizedClosureLibrary() async throws -> TimingLibrary {
        if let cached = sizedLibrary { return cached }
        if let pending = pendingSizedLibrary {
            return try await pending.value
        }

        let characterizedFlipFlop = try await characterizedFlipFlopReport().timing
        let task = Task {
            try await TimingCharacterizationTestSupport.withExclusiveSpiceSlot {
                let inputSlews = [40e-12, 200e-12]
                let outputLoads = [1e-15, 4e-15, 12e-15]
                let characterizer = CellTimingCharacterizer(inputSlews: inputSlews, outputLoads: outputLoads)
                var library = TimingLibrary()
                let bases: [CMOSGateNetlist] = [
                    .inverter(name: "inv"),
                    .nand(name: "nand2", inputs: ["A", "B"]),
                    .nor(name: "nor2", inputs: ["A", "B"]),
                ]
                for base in bases {
                    for variant in CellSizing.variants(of: base) {
                        library.add(try await characterizer.characterize(variant))
                    }
                }
                library.flipFlop = characterizedFlipFlop
                return library
            }
        }
        pendingSizedLibrary = task
        do {
            let library = try await task.value
            sizedLibrary = library
            pendingSizedLibrary = nil
            return library
        } catch {
            pendingSizedLibrary = nil
            throw error
        }
    }

    func validatePath(
        _ path: TimingPath,
        in netlist: SequentialNetlist,
        toleranceFraction: Double
    ) async throws -> STAvsSPICEValidator.Result {
        let key = ValidationKey(path: path, netlist: netlist, toleranceFraction: toleranceFraction)
        if let cached = validations[key] { return cached }
        if let pending = pendingValidations[key] {
            return try await pending.value
        }

        let task = Task {
            try await TimingCharacterizationTestSupport.withExclusiveSpiceSlot {
                try await STAvsSPICEValidator().validate(
                    path: path,
                    in: netlist,
                    toleranceFraction: toleranceFraction
                )
            }
        }
        pendingValidations[key] = task
        do {
            let result = try await task.value
            validations[key] = result
            pendingValidations[key] = nil
            return result
        } catch {
            pendingValidations[key] = nil
            throw error
        }
    }

    private func copy(
        _ build: StandardTimingLibraryBuildResult,
        runID: String?
    ) -> StandardTimingLibraryBuildResult {
        let libraryArtifact = TimingLibraryArtifact(
            schemaVersion: build.libraryArtifact.schemaVersion,
            kind: build.libraryArtifact.kind,
            runID: runID,
            createdAt: build.libraryArtifact.createdAt,
            technology: build.libraryArtifact.technology,
            library: build.libraryArtifact.library,
            modelSources: build.libraryArtifact.modelSources,
            warnings: build.libraryArtifact.warnings
        )
        return StandardTimingLibraryBuildResult(
            library: build.library,
            libraryArtifact: libraryArtifact,
            combinationalReport: build.combinationalReport,
            sequentialReport: build.sequentialReport
        )
    }
}
