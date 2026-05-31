import Foundation

public actor TimingCharacterizationCache {
    public enum CacheError: Error, LocalizedError, Equatable {
        case directoryCreationFailed(path: String, reason: String)
        case readFailed(path: String, reason: String)
        case writeFailed(path: String, reason: String)

        public var errorDescription: String? {
            switch self {
            case .directoryCreationFailed(let path, let reason):
                return "Could not create timing characterization cache directory at \(path): \(reason)."
            case .readFailed(let path, let reason):
                return "Could not read timing characterization cache artifact at \(path): \(reason)."
            case .writeFailed(let path, let reason):
                return "Could not write timing characterization cache artifact at \(path): \(reason)."
            }
        }
    }

    public static let shared = TimingCharacterizationCache()

    fileprivate static let schemaVersion = 1
    fileprivate static let cellCharacterizerVersion = 1
    fileprivate static let sequentialCharacterizerVersion = 1

    private let directory: URL
    private var pendingCells: [String: Task<CellTiming, Error>] = [:]
    private var pendingSequentialReports: [String: Task<SequentialTimingCharacterizationReport, Error>] = [:]

    public init(directory: URL = TimingCharacterizationCache.defaultDirectory()) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["CIRCUIT_STUDIO_TIMING_CACHE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        if let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return cachesDirectory
                .appendingPathComponent("CircuitStudio", isDirectory: true)
                .appendingPathComponent("timing-characterization", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        }

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("CircuitStudio", isDirectory: true)
            .appendingPathComponent("timing-characterization", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    public func cellTiming(
        cell: CMOSGateNetlist,
        model: Level1DeviceModel,
        inputSlews: [Double],
        outputLoads: [Double],
        compute: @Sendable @escaping () async throws -> CellTiming
    ) async throws -> CellTiming {
        let key = try CellTimingCacheKey(
            model: model,
            cell: cell,
            inputSlews: inputSlews,
            outputLoads: outputLoads
        )
        let keyHash = try TimingTopologyHasher.hash(key)
        let url = cellURL(keyHash: keyHash)

        if let cached = try Self.readCellTiming(key: key, keyHash: keyHash, url: url) {
            return cached
        }
        if let pending = pendingCells[keyHash] {
            return try await pending.value
        }

        let task = Task {
            let timing = try await compute()
            try Self.writeCellTiming(timing, key: key, keyHash: keyHash, url: url)
            return timing
        }
        pendingCells[keyHash] = task
        do {
            let timing = try await task.value
            pendingCells[keyHash] = nil
            return timing
        } catch {
            pendingCells[keyHash] = nil
            throw error
        }
    }

    public func sequentialReport(
        netlist: GateLevelNetlist,
        cellName: String,
        model: Level1DeviceModel,
        clockSlew: Double,
        dataSlew: Double,
        outputLoads: [Double],
        setupHoldSearchWindow: Double,
        setupHoldSearchResolution: Double,
        maxSearchIterations: Int,
        compute: @Sendable @escaping () async throws -> SequentialTimingCharacterizationReport
    ) async throws -> SequentialTimingCharacterizationReport {
        let key = try SequentialTimingCacheKey(
            model: model,
            netlist: netlist,
            cellName: cellName,
            clockSlew: clockSlew,
            dataSlew: dataSlew,
            outputLoads: outputLoads,
            setupHoldSearchWindow: setupHoldSearchWindow,
            setupHoldSearchResolution: setupHoldSearchResolution,
            maxSearchIterations: maxSearchIterations
        )
        let keyHash = try TimingTopologyHasher.hash(key)
        let url = sequentialURL(keyHash: keyHash)

        if let cached = try Self.readSequentialReport(key: key, keyHash: keyHash, url: url) {
            return cached
        }
        if let pending = pendingSequentialReports[keyHash] {
            return try await pending.value
        }

        let task = Task {
            let report = try await compute()
            try Self.writeSequentialReport(report, key: key, keyHash: keyHash, url: url)
            return report
        }
        pendingSequentialReports[keyHash] = task
        do {
            let report = try await task.value
            pendingSequentialReports[keyHash] = nil
            return report
        } catch {
            pendingSequentialReports[keyHash] = nil
            throw error
        }
    }

    private func cellURL(keyHash: String) -> URL {
        directory
            .appendingPathComponent("cells", isDirectory: true)
            .appendingPathComponent("\(keyHash).json")
    }

    private func sequentialURL(keyHash: String) -> URL {
        directory
            .appendingPathComponent("sequential", isDirectory: true)
            .appendingPathComponent("\(keyHash).json")
    }

    private static func readCellTiming(
        key: CellTimingCacheKey,
        keyHash: String,
        url: URL
    ) throws -> CellTiming? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let envelope = try decoder().decode(CellTimingCacheEnvelope.self, from: data)
            guard envelope.schemaVersion == Self.schemaVersion else {
                throw CacheError.readFailed(path: url.path, reason: "Schema version \(envelope.schemaVersion) is not supported.")
            }
            guard envelope.kind == "cell-timing-characterization-cache" else {
                throw CacheError.readFailed(path: url.path, reason: "Unexpected artifact kind \(envelope.kind).")
            }
            guard envelope.keyHash == keyHash, envelope.key == key else {
                throw CacheError.readFailed(path: url.path, reason: "Cache key does not match requested characterization input.")
            }
            return envelope.value
        } catch let error as CacheError {
            throw error
        } catch {
            throw CacheError.readFailed(path: url.path, reason: String(describing: error))
        }
    }

    private static func writeCellTiming(
        _ timing: CellTiming,
        key: CellTimingCacheKey,
        keyHash: String,
        url: URL
    ) throws {
        let envelope = CellTimingCacheEnvelope(
            schemaVersion: Self.schemaVersion,
            kind: "cell-timing-characterization-cache",
            keyHash: keyHash,
            createdAt: Date(),
            key: key,
            value: timing
        )
        try write(envelope, to: url)
    }

    private static func readSequentialReport(
        key: SequentialTimingCacheKey,
        keyHash: String,
        url: URL
    ) throws -> SequentialTimingCharacterizationReport? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let envelope = try decoder().decode(SequentialTimingCacheEnvelope.self, from: data)
            guard envelope.schemaVersion == Self.schemaVersion else {
                throw CacheError.readFailed(path: url.path, reason: "Schema version \(envelope.schemaVersion) is not supported.")
            }
            guard envelope.kind == "sequential-timing-characterization-cache" else {
                throw CacheError.readFailed(path: url.path, reason: "Unexpected artifact kind \(envelope.kind).")
            }
            guard envelope.keyHash == keyHash, envelope.key == key else {
                throw CacheError.readFailed(path: url.path, reason: "Cache key does not match requested characterization input.")
            }
            return envelope.value
        } catch let error as CacheError {
            throw error
        } catch {
            throw CacheError.readFailed(path: url.path, reason: String(describing: error))
        }
    }

    private static func writeSequentialReport(
        _ report: SequentialTimingCharacterizationReport,
        key: SequentialTimingCacheKey,
        keyHash: String,
        url: URL
    ) throws {
        let envelope = SequentialTimingCacheEnvelope(
            schemaVersion: Self.schemaVersion,
            kind: "sequential-timing-characterization-cache",
            keyHash: keyHash,
            createdAt: Date(),
            key: key,
            value: report
        )
        try write(envelope, to: url)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw CacheError.directoryCreationFailed(path: parent.path, reason: String(describing: error))
        }

        do {
            let data = try encoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            throw CacheError.writeFailed(path: url.path, reason: String(describing: error))
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct CellTimingCacheKey: Sendable, Hashable, Codable {
    let schemaVersion: Int
    let kind: String
    let characterizerVersion: Int
    let deviceModelHash: String
    let topologyHash: String
    let inputSlews: [Double]
    let outputLoads: [Double]

    init(
        model: Level1DeviceModel,
        cell: CMOSGateNetlist,
        inputSlews: [Double],
        outputLoads: [Double]
    ) throws {
        self.schemaVersion = TimingCharacterizationCache.schemaVersion
        self.kind = "cell-timing"
        self.characterizerVersion = TimingCharacterizationCache.cellCharacterizerVersion
        self.deviceModelHash = try TimingTopologyHasher.hashModel(model)
        self.topologyHash = try TimingTopologyHasher.hash(cell)
        self.inputSlews = inputSlews
        self.outputLoads = outputLoads
    }
}

private struct SequentialTimingCacheKey: Sendable, Hashable, Codable {
    let schemaVersion: Int
    let kind: String
    let characterizerVersion: Int
    let deviceModelHash: String
    let topologyHash: String
    let cellName: String
    let clockSlew: Double
    let dataSlew: Double
    let outputLoads: [Double]
    let setupHoldSearchWindow: Double
    let setupHoldSearchResolution: Double
    let maxSearchIterations: Int

    init(
        model: Level1DeviceModel,
        netlist: GateLevelNetlist,
        cellName: String,
        clockSlew: Double,
        dataSlew: Double,
        outputLoads: [Double],
        setupHoldSearchWindow: Double,
        setupHoldSearchResolution: Double,
        maxSearchIterations: Int
    ) throws {
        self.schemaVersion = TimingCharacterizationCache.schemaVersion
        self.kind = "sequential-timing"
        self.characterizerVersion = TimingCharacterizationCache.sequentialCharacterizerVersion
        self.deviceModelHash = try TimingTopologyHasher.hashModel(model)
        self.topologyHash = try TimingTopologyHasher.hash(netlist)
        self.cellName = cellName
        self.clockSlew = clockSlew
        self.dataSlew = dataSlew
        self.outputLoads = outputLoads
        self.setupHoldSearchWindow = setupHoldSearchWindow
        self.setupHoldSearchResolution = setupHoldSearchResolution
        self.maxSearchIterations = maxSearchIterations
    }
}

private struct CellTimingCacheEnvelope: Sendable, Hashable, Codable {
    let schemaVersion: Int
    let kind: String
    let keyHash: String
    let createdAt: Date
    let key: CellTimingCacheKey
    let value: CellTiming
}

private struct SequentialTimingCacheEnvelope: Sendable, Hashable, Codable {
    let schemaVersion: Int
    let kind: String
    let keyHash: String
    let createdAt: Date
    let key: SequentialTimingCacheKey
    let value: SequentialTimingCharacterizationReport
}
