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

public enum GateApprovalTargetPathBase: String, Sendable, Hashable, Codable {
    case runDirectory
    case absolute
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
    public let targetArtifactKind: String?
    public let targetArtifactPathBase: GateApprovalTargetPathBase
    public let targetArtifactPath: String
    public let targetArtifactSHA256: String
    public let policy: String?
    public let waiverIDs: [String]
    public let note: String?
    public let artifactResolutionWarnings: [String]
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
        targetArtifactKind: String? = nil,
        targetArtifactPathBase: GateApprovalTargetPathBase = .absolute,
        targetArtifactPath: String,
        targetArtifactSHA256: String,
        policy: String?,
        waiverIDs: [String],
        note: String?,
        artifactResolutionWarnings: [String] = [],
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
        self.targetArtifactKind = targetArtifactKind
        self.targetArtifactPathBase = targetArtifactPathBase
        self.targetArtifactPath = targetArtifactPath
        self.targetArtifactSHA256 = targetArtifactSHA256
        self.policy = policy
        self.waiverIDs = waiverIDs
        self.note = note
        self.artifactResolutionWarnings = artifactResolutionWarnings
        self.lineage = lineage
    }
}

extension GateApprovalRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case gateID
        case decision
        case reviewer
        case decidedAt
        case runID
        case manifestPath
        case manifestSHA256
        case targetArtifactKind
        case targetArtifactPathBase
        case targetArtifactPath
        case targetArtifactSHA256
        case policy
        case waiverIDs
        case note
        case artifactResolutionWarnings
        case lineage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            gateID: try container.decode(FlowGateID.self, forKey: .gateID),
            decision: try container.decode(GateApprovalDecision.self, forKey: .decision),
            reviewer: try container.decode(String.self, forKey: .reviewer),
            decidedAt: try container.decode(Date.self, forKey: .decidedAt),
            runID: try container.decodeIfPresent(String.self, forKey: .runID),
            manifestPath: try container.decodeIfPresent(String.self, forKey: .manifestPath),
            manifestSHA256: try container.decodeIfPresent(String.self, forKey: .manifestSHA256),
            targetArtifactKind: try container.decodeIfPresent(String.self, forKey: .targetArtifactKind),
            targetArtifactPathBase: try container.decodeIfPresent(
                GateApprovalTargetPathBase.self,
                forKey: .targetArtifactPathBase
            ) ?? .absolute,
            targetArtifactPath: try container.decode(String.self, forKey: .targetArtifactPath),
            targetArtifactSHA256: try container.decode(String.self, forKey: .targetArtifactSHA256),
            policy: try container.decodeIfPresent(String.self, forKey: .policy),
            waiverIDs: try container.decode([String].self, forKey: .waiverIDs),
            note: try container.decodeIfPresent(String.self, forKey: .note),
            artifactResolutionWarnings: try container.decodeIfPresent(
                [String].self,
                forKey: .artifactResolutionWarnings
            ) ?? [],
            lineage: try container.decodeIfPresent(FlowRunLineage.self, forKey: .lineage)
        )
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

private struct GateApprovalTarget: Sendable, Hashable {
    let url: URL
    let recordPath: String
    let pathBase: GateApprovalTargetPathBase
    let artifactKind: String?
    let warnings: [String]
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
    case missingApprovalRunDirectory
    case invalidRunID(String)
    case invalidArtifactPath(String)

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
        case .missingApprovalRunDirectory:
            return "Gate approval with an explicit target requires a manifest URL or project root and run ID."
        case .invalidRunID(let runID):
            return "Invalid run ID for gate approval: \(runID)"
        case .invalidArtifactPath(let message):
            return "Invalid gate approval artifact path: \(message)"
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
        let resolvedRunID = request.runID ?? manifest?.runID
        if let resolvedRunID {
            try validateRunID(resolvedRunID)
        }
        let target = try approvalTarget(
            gateID: request.gateID,
            explicitTargetURL: request.targetArtifactURL,
            manifest: manifest,
            manifestURL: request.manifestURL,
            projectRoot: request.projectRoot,
            runID: resolvedRunID
        )
        let targetURL = target.url
        guard FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) else {
            throw FlowRunGovernanceError.missingArtifact(targetURL)
        }

        let manifestHash = try request.manifestURL.map { try sha256(of: $0) }
        let targetHash = try sha256(of: targetURL)
        let record = GateApprovalRecord(
            gateID: request.gateID,
            decision: request.decision,
            reviewer: reviewer,
            decidedAt: request.decidedAt,
            runID: resolvedRunID,
            manifestPath: request.manifestURL?.path(percentEncoded: false),
            manifestSHA256: manifestHash,
            targetArtifactKind: target.artifactKind,
            targetArtifactPathBase: target.pathBase,
            targetArtifactPath: target.recordPath,
            targetArtifactSHA256: targetHash,
            policy: request.policy,
            waiverIDs: request.waiverIDs,
            note: request.note,
            artifactResolutionWarnings: target.warnings,
            lineage: request.lineage ?? lineage(
                from: manifest,
                manifestURL: request.manifestURL,
                manifestSHA256: manifestHash
            )
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

    public func approvalRecords(forProjectAt projectRoot: URL, runID: String) throws -> [GateApprovalRecord] {
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

    private func approvalTarget(
        gateID: FlowGateID,
        explicitTargetURL: URL?,
        manifest: HeadlessRoundTripService.Manifest?,
        manifestURL: URL?,
        projectRoot: URL?,
        runID: String?
    ) throws -> GateApprovalTarget {
        if let explicitTargetURL {
            guard let runDirectory = approvalRunDirectory(
                manifestURL: manifestURL,
                projectRoot: projectRoot,
                runID: runID
            ) else {
                throw FlowRunGovernanceError.missingApprovalRunDirectory
            }
            do {
                let resolver = RoundTripArtifactResolver(runDirectory: runDirectory)
                return GateApprovalTarget(
                    url: explicitTargetURL,
                    recordPath: try resolver.relativePath(for: explicitTargetURL),
                    pathBase: .runDirectory,
                    artifactKind: nil,
                    warnings: []
                )
            } catch {
                throw FlowRunGovernanceError.invalidArtifactPath(error.localizedDescription)
            }
        }
        guard let manifest else {
            throw FlowRunGovernanceError.missingApprovalTarget
        }
        guard let manifestURL else {
            throw FlowRunGovernanceError.missingApprovalTarget
        }
        let targetKinds = artifactKinds(for: gateID)
        guard let artifact = manifest.artifacts.first(where: { targetKinds.contains($0.kind) }) else {
            throw FlowRunGovernanceError.missingArtifactForGate(gateID)
        }
        do {
            let resolver = RoundTripArtifactResolver(manifestURL: manifestURL)
            let resolution = try resolver.resolve(artifact)
            return GateApprovalTarget(
                url: resolution.url,
                recordPath: try resolver.relativePath(for: resolution.url),
                pathBase: .runDirectory,
                artifactKind: artifact.kind,
                warnings: resolution.warnings
            )
        } catch {
            throw FlowRunGovernanceError.invalidArtifactPath(error.localizedDescription)
        }
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

    private func approvalRunDirectory(
        manifestURL: URL?,
        projectRoot: URL?,
        runID: String?
    ) -> URL? {
        if let manifestURL {
            return manifestURL.deletingLastPathComponent()
        }
        guard let projectRoot, let runID else {
            return nil
        }
        do {
            return try RoundTripRunDirectory.runDirectory(
                projectRoot: projectRoot,
                runID: runID
            )
        } catch {
            return nil
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

    private func lineage(
        from manifest: HeadlessRoundTripService.Manifest?,
        manifestURL: URL?,
        manifestSHA256: String?
    ) -> FlowRunLineage? {
        guard let manifest, let manifestURL else {
            return nil
        }
        return FlowRunLineage(
            parentRunID: manifest.runID,
            parentManifestPath: manifestURL.path(percentEncoded: false),
            parentManifestSHA256: manifestSHA256
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
        try RoundTripArtifactDigest.compute(url: url).sha256
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
