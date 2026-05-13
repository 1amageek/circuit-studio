import CryptoKit
import Foundation

public enum FlowGateID: String, Sendable, Hashable, Codable {
    case externalSignoff = "external-signoff"
    case prePEXVerification = "pre-pex-verification"
    case postLayoutComparison = "post-layout-comparison"
    case physicalVerification = "physical-verification"
}

public enum GateApprovalDecision: String, Sendable, Hashable, Codable {
    case approved
    case rejected
}

public struct FlowRunLineage: Sendable, Hashable, Codable {
    public let parentRunID: String?
    public let parentManifestPath: String?
    public let parentManifestSHA256: String?
    public let appliedActionLogPaths: [String]
    public let approvalRecordPaths: [String]

    public init(
        parentRunID: String? = nil,
        parentManifestPath: String? = nil,
        parentManifestSHA256: String? = nil,
        appliedActionLogPaths: [String] = [],
        approvalRecordPaths: [String] = []
    ) {
        self.parentRunID = parentRunID
        self.parentManifestPath = parentManifestPath
        self.parentManifestSHA256 = parentManifestSHA256
        self.appliedActionLogPaths = appliedActionLogPaths
        self.approvalRecordPaths = approvalRecordPaths
    }
}

public struct GateApprovalRecord: Sendable, Hashable, Codable {
    public let id: UUID
    public let gateID: FlowGateID
    public let decision: GateApprovalDecision
    public let reviewer: String
    public let decidedAt: Date
    public let runID: String?
    public let manifestPath: String?
    public let manifestSHA256: String?
    public let targetArtifactPath: String
    public let targetArtifactSHA256: String
    public let policy: String?
    public let waiverIDs: [String]
    public let note: String?
    public let lineage: FlowRunLineage?

    public init(
        id: UUID = UUID(),
        gateID: FlowGateID,
        decision: GateApprovalDecision,
        reviewer: String,
        decidedAt: Date,
        runID: String?,
        manifestPath: String?,
        manifestSHA256: String?,
        targetArtifactPath: String,
        targetArtifactSHA256: String,
        policy: String?,
        waiverIDs: [String],
        note: String?,
        lineage: FlowRunLineage?
    ) {
        self.id = id
        self.gateID = gateID
        self.decision = decision
        self.reviewer = reviewer
        self.decidedAt = decidedAt
        self.runID = runID
        self.manifestPath = manifestPath
        self.manifestSHA256 = manifestSHA256
        self.targetArtifactPath = targetArtifactPath
        self.targetArtifactSHA256 = targetArtifactSHA256
        self.policy = policy
        self.waiverIDs = waiverIDs
        self.note = note
        self.lineage = lineage
    }
}

public struct GateApprovalResult: Sendable, Hashable, Codable {
    public let record: GateApprovalRecord
    public let recordPath: String

    public init(record: GateApprovalRecord, recordPath: String) {
        self.record = record
        self.recordPath = recordPath
    }
}

public struct GateApprovalRequest: Sendable, Hashable {
    public let gateID: FlowGateID
    public let decision: GateApprovalDecision
    public let reviewer: String
    public let decidedAt: Date
    public let projectRoot: URL?
    public let runID: String?
    public let manifestURL: URL?
    public let targetArtifactURL: URL?
    public let policy: String?
    public let waiverIDs: [String]
    public let note: String?
    public let lineage: FlowRunLineage?

    public init(
        gateID: FlowGateID,
        decision: GateApprovalDecision = .approved,
        reviewer: String,
        decidedAt: Date = Date(),
        projectRoot: URL? = nil,
        runID: String? = nil,
        manifestURL: URL? = nil,
        targetArtifactURL: URL? = nil,
        policy: String? = nil,
        waiverIDs: [String] = [],
        note: String? = nil,
        lineage: FlowRunLineage? = nil
    ) {
        self.gateID = gateID
        self.decision = decision
        self.reviewer = reviewer
        self.decidedAt = decidedAt
        self.projectRoot = projectRoot
        self.runID = runID
        self.manifestURL = manifestURL
        self.targetArtifactURL = targetArtifactURL
        self.policy = policy
        self.waiverIDs = waiverIDs
        self.note = note
        self.lineage = lineage
    }
}

public enum FlowRunGovernanceError: Error, LocalizedError, Equatable {
    case missingReviewer
    case missingApprovalTarget
    case missingArtifactForGate(FlowGateID)
    case missingArtifact(URL)
    case invalidRunID(String)

    public var errorDescription: String? {
        switch self {
        case .missingReviewer:
            return "Gate approval requires a reviewer."
        case .missingApprovalTarget:
            return "Gate approval requires a manifest path or target artifact path."
        case .missingArtifactForGate(let gateID):
            return "Manifest does not contain a target artifact for gate '\(gateID.rawValue)'."
        case .missingArtifact(let url):
            return "Gate approval target artifact does not exist: \(url.path(percentEncoded: false))"
        case .invalidRunID(let runID):
            return "Invalid run ID for gate approval: \(runID)"
        }
    }
}

public struct FlowRunGovernanceService: Sendable {
    public init() {}

    public func approve(_ request: GateApprovalRequest) throws -> GateApprovalResult {
        let reviewer = request.reviewer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reviewer.isEmpty else {
            throw FlowRunGovernanceError.missingReviewer
        }
        if let runID = request.runID {
            try validateRunID(runID)
        }

        let manifest = try request.manifestURL.map { try loadManifest($0) }
        let targetURL = try approvalTargetURL(
            gateID: request.gateID,
            explicitTargetURL: request.targetArtifactURL,
            manifest: manifest,
            manifestURL: request.manifestURL
        )
        guard FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) else {
            throw FlowRunGovernanceError.missingArtifact(targetURL)
        }

        let manifestHash = try request.manifestURL.map { try sha256(of: $0) }
        let targetHash = try sha256(of: targetURL)
        let resolvedRunID = request.runID ?? manifest?.runID
        if let resolvedRunID {
            try validateRunID(resolvedRunID)
        }
        let record = GateApprovalRecord(
            gateID: request.gateID,
            decision: request.decision,
            reviewer: reviewer,
            decidedAt: request.decidedAt,
            runID: resolvedRunID,
            manifestPath: request.manifestURL?.path(percentEncoded: false),
            manifestSHA256: manifestHash,
            targetArtifactPath: targetURL.path(percentEncoded: false),
            targetArtifactSHA256: targetHash,
            policy: request.policy,
            waiverIDs: request.waiverIDs,
            note: request.note,
            lineage: request.lineage ?? lineage(from: manifest, manifestURL: request.manifestURL)
        )
        let recordURL = approvalRecordURL(
            request: request,
            runID: resolvedRunID,
            manifestURL: request.manifestURL,
            record: record
        )
        try writeJSON(record, to: recordURL)
        return GateApprovalResult(
            record: record,
            recordPath: recordURL.path(percentEncoded: false)
        )
    }

    public func approvalRecords(projectRoot: URL, runID: String) throws -> [GateApprovalRecord] {
        try validateRunID(runID)
        let directory = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "approvals")
            .appending(path: runID)
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return []
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map { try readJSON(GateApprovalRecord.self, from: $0) }
    }

    private func approvalTargetURL(
        gateID: FlowGateID,
        explicitTargetURL: URL?,
        manifest: HeadlessRoundTripService.Manifest?,
        manifestURL: URL?
    ) throws -> URL {
        if let explicitTargetURL {
            return explicitTargetURL
        }
        guard let manifest else {
            throw FlowRunGovernanceError.missingApprovalTarget
        }
        let targetKinds = artifactKinds(for: gateID)
        guard let artifact = manifest.artifacts.first(where: { targetKinds.contains($0.kind) }) else {
            throw FlowRunGovernanceError.missingArtifactForGate(gateID)
        }
        return resolvedArtifactURL(artifact, manifestURL: manifestURL)
    }

    private func artifactKinds(for gateID: FlowGateID) -> [String] {
        switch gateID {
        case .externalSignoff:
            return ["external-signoff-review"]
        case .postLayoutComparison:
            return ["post-layout-comparison"]
        case .physicalVerification:
            return ["physical-verification-report", "physical-verification"]
        case .prePEXVerification:
            return ["physical-verification-report", "pre-pex-verification", "physical-verification"]
        }
    }

    private func approvalRecordURL(
        request: GateApprovalRequest,
        runID: String?,
        manifestURL: URL?,
        record: GateApprovalRecord
    ) -> URL {
        let root = request.projectRoot
            ?? projectRoot(fromManifestURL: manifestURL)
            ?? URL(filePath: FileManager.default.currentDirectoryPath)
        let runDirectoryName = runID ?? "unbound"
        let fileName = "\(record.gateID.rawValue)-\(record.id.uuidString).json"
        return root
            .appending(path: ".xcircuite")
            .appending(path: "approvals")
            .appending(path: runDirectoryName)
            .appending(path: fileName)
    }

    private func projectRoot(fromManifestURL url: URL?) -> URL? {
        guard let url else {
            return nil
        }
        let flowRunsDirectory = url.deletingLastPathComponent().deletingLastPathComponent()
        let configDirectory = flowRunsDirectory.deletingLastPathComponent()
        guard configDirectory.lastPathComponent == ".xcircuite" else {
            return nil
        }
        return configDirectory.deletingLastPathComponent()
    }

    private func resolvedArtifactURL(
        _ artifact: HeadlessRoundTripService.Artifact,
        manifestURL: URL?
    ) -> URL {
        if artifact.path.hasPrefix("/") {
            return URL(filePath: artifact.path)
        }
        guard let manifestURL else {
            return URL(filePath: artifact.path)
        }
        return manifestURL.deletingLastPathComponent().appending(path: artifact.path)
    }

    private func lineage(
        from manifest: HeadlessRoundTripService.Manifest?,
        manifestURL: URL?
    ) -> FlowRunLineage? {
        guard let manifest, let manifestURL else {
            return nil
        }
        let hash: String?
        do {
            hash = try sha256(of: manifestURL)
        } catch {
            hash = nil
        }
        return FlowRunLineage(
            parentRunID: manifest.runID,
            parentManifestPath: manifestURL.path(percentEncoded: false),
            parentManifestSHA256: hash
        )
    }

    private func loadManifest(_ url: URL) throws -> HeadlessRoundTripService.Manifest {
        try readJSON(HeadlessRoundTripService.Manifest.self, from: url)
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func validateRunID(_ runID: String) throws {
        let allowedScalars = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        let isValid = !runID.isEmpty
            && runID != "."
            && runID != ".."
            && runID.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
        guard isValid else {
            throw FlowRunGovernanceError.invalidRunID(runID)
        }
    }
}
