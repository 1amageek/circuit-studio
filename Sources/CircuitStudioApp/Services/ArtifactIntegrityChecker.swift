import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation
import DesignFlowKernel
import Foundation

public enum ArtifactIntegrityError: Error, LocalizedError, Equatable {
    case unavailableArtifact(kind: String, path: String)
    case missingBinding(kind: String, path: String)
    case unsupportedAvailability(logicalID: String)
    case integrityFailure(kind: String, path: String, issues: [ArtifactIntegrityIssue])
    case unreadableArtifact(kind: String, path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unavailableArtifact(let kind, let path):
            return "Artifact is not available: \(kind) at \(path)"
        case .missingBinding(let kind, let path):
            return "Available artifact is missing its identity-to-availability binding: \(kind) at \(path)"
        case .unsupportedAvailability(let logicalID):
            return "Artifact integrity checking requires local availability: \(logicalID)"
        case .integrityFailure(let kind, let path, let issues):
            let codes = issues.map(\.code.rawValue).joined(separator: ", ")
            return "Artifact integrity verification failed: \(kind) at \(path): \(codes)"
        case .unreadableArtifact(let kind, let path, let reason):
            return "Artifact is unreadable: \(kind) at \(path): \(reason)"
        }
    }
}

public struct VerifiedArtifact: Sendable, Hashable {
    public let reference: ArtifactReference
    public let url: URL
    public let data: Data

    public init(reference: ArtifactReference, url: URL, data: Data) {
        self.reference = reference
        self.url = url
        self.data = data
    }
}

public struct ArtifactIntegrityChecker: ArtifactIntegrityChecking {
    public init() {}

    public func verifiedData(
        for record: any ArtifactIntegrityRecord,
        in runDirectory: URL
    ) async throws -> Data {
        try await verifiedArtifact(for: record, in: runDirectory).data
    }

    public func verifiedArtifact(
        for record: any ArtifactIntegrityRecord,
        in runDirectory: URL
    ) async throws -> VerifiedArtifact {
        let descriptor = record.artifactDescriptor
        let kind = descriptor.kind.rawValue
        let path = try record.artifactRelativePath.stringValue
        guard record.artifactIsAvailable else {
            throw ArtifactIntegrityError.unavailableArtifact(kind: kind, path: path)
        }
        guard let binding = record.artifactBinding else {
            throw ArtifactIntegrityError.missingBinding(kind: kind, path: path)
        }
        guard case .local(_, let rootID, let relativePath) = binding.availability else {
            throw ArtifactIntegrityError.unsupportedAvailability(logicalID: binding.logicalID)
        }
        let access: ArtifactRootCapability
        do {
            access = try ArtifactRootCapability(
                rootID: rootID,
                directoryURL: runDirectory,
                digester: SHA256ContentDigester()
            )
        } catch {
            throw ArtifactIntegrityError.unreadableArtifact(
                kind: kind,
                path: path,
                reason: error.localizedDescription
            )
        }
        let data: Data
        do {
            data = try await read(binding: binding, access: access)
            try await access.close().wait()
        } catch let primaryError {
            do {
                try await access.close().wait()
            } catch let closeError {
                throw ArtifactIntegrityError.unreadableArtifact(
                    kind: kind,
                    path: path,
                    reason: "read failed: \(primaryError); access close failed: \(closeError)"
                )
            }
            throw integrityError(
                primaryError,
                kind: kind,
                path: path
            )
        }
        let url = relativePath.segments.reduce(runDirectory.standardizedFileURL) {
            partial, segment in partial.appending(path: segment)
        }
        return VerifiedArtifact(reference: binding.reference, url: url, data: data)
    }

    public func decodeVerifiedJSON<T: Decodable>(
        _ type: T.Type,
        for record: any ArtifactIntegrityRecord,
        in runDirectory: URL
    ) async throws -> T {
        let data = try await verifiedData(for: record, in: runDirectory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(type, from: data)
        if let validating = decoded as? any ArtifactPayloadValidating {
            try validating.validateForPersistence()
        }
        return decoded
    }

    private func read(
        binding: FlowArtifactBinding,
        access: ArtifactRootCapability
    ) async throws -> Data {
        guard binding.reference.byteCount <= UInt64(Int.max) else {
            throw ArtifactAccessError.totalByteLimitExceeded(
                limit: UInt64(Int.max),
                requested: binding.reference.byteCount
            )
        }
        let budget = try readBudget(for: binding.reference)
        let intent = try ArtifactAccessIntent(
            expectedReference: binding.reference,
            availability: binding.availability,
            operation: .read,
            budget: budget
        )
        let session = try await access.open(intent)
        do {
            var data = Data()
            data.reserveCapacity(Int(binding.reference.byteCount))
            var offset: UInt64 = 0
            var terminalReceipt: ArtifactAccessReceipt?
            while terminalReceipt == nil {
                let page = try await session.readPage(
                    ArtifactReadPageRequest(
                        offset: offset,
                        maximumByteCount: budget.maximumPageByteCount
                    )
                )
                page.bytes.withUnsafeBytes { bytes in
                    data.append(contentsOf: bytes)
                }
                offset = page.cumulativeByteCount
                terminalReceipt = page.finalReceipt
            }
            guard terminalReceipt?.observedArtifactID == binding.reference.id,
                  terminalReceipt?.totalByteCount == binding.reference.byteCount else {
                throw ArtifactAccessError.contentIdentityMismatch(
                    expected: binding.reference.id,
                    actual: terminalReceipt?.observedArtifactID ?? binding.reference.id
                )
            }
            let termination = try await session.close().wait()
            guard termination.didReachTerminalPage else {
                throw ArtifactAccessError.truncatedResource
            }
            return data
        } catch let primaryError {
            do {
                _ = try await session.close().wait()
            } catch let closeError {
                throw ArtifactAccessError.cleanupFailed(
                    primary: String(describing: primaryError),
                    closeReason: String(describing: closeError)
                )
            }
            throw primaryError
        }
    }

    private func readBudget(
        for reference: ArtifactReference
    ) throws -> ArtifactAccessBudget {
        let maximumTotalByteCount = max(reference.byteCount, 1)
        let maximumPageByteCount = min(maximumTotalByteCount, 1_048_576)
        let pageCount = reference.byteCount == 0
            ? 1
            : (reference.byteCount - 1) / maximumPageByteCount + 1
        let (maximumWorkUnitCount, overflow) = pageCount.multipliedReportingOverflow(by: 2)
        guard !overflow else {
            throw ArtifactAccessError.workLimitExceeded(
                limit: UInt64.max,
                requested: UInt64.max
            )
        }
        return try ArtifactAccessBudget(
            maximumPageByteCount: maximumPageByteCount,
            maximumTotalByteCount: maximumTotalByteCount,
            maximumPageCount: pageCount,
            maximumWorkUnitCount: max(maximumWorkUnitCount, 1),
            maximumDurationNanoseconds: 30_000_000_000
        )
    }

    private func integrityError(
        _ error: any Error,
        kind: String,
        path: String
    ) -> ArtifactIntegrityError {
        switch error {
        case ArtifactAccessError.byteCountMismatch(let expected, let actual):
            .integrityFailure(
                kind: kind,
                path: path,
                issues: [.byteCountMismatch(expected: expected, actual: actual)]
            )
        case ArtifactAccessError.contentDigestMismatch(let expected, let actual):
            .integrityFailure(
                kind: kind,
                path: path,
                issues: [.digestMismatch(expected: expected, actual: actual)]
            )
        case ArtifactAccessError.nonRegularResource:
            .integrityFailure(
                kind: kind,
                path: path,
                issues: [.notRegularFile(path)]
            )
        default:
            .unreadableArtifact(
                kind: kind,
                path: path,
                reason: String(describing: error)
            )
        }
    }
}
