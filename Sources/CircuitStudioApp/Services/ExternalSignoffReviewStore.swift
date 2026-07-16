import CircuitSignoff
import Foundation
import CircuitStudioCore

public struct ExternalSignoffReviewStore: Sendable {
    private static let configDir = ".xcircuite"
    private static let signoffDir = "signoff"
    private static let reviewFileName = "external-signoff-review.json"

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func artifactDirectory(forProjectAt projectRoot: URL) -> URL {
        projectRoot
            .appending(path: Self.configDir)
            .appending(path: Self.signoffDir)
    }

    public func reviewURL(forProjectAt projectRoot: URL) -> URL {
        artifactDirectory(forProjectAt: projectRoot)
            .appending(path: Self.reviewFileName)
    }

    @discardableResult
    public func save(_ review: ExternalSignoffReview, forProjectAt projectRoot: URL) throws -> URL {
        let directory = artifactDirectory(forProjectAt: projectRoot)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to create external signoff directory: \(error.localizedDescription)"
            )
        }

        let url = reviewURL(forProjectAt: projectRoot)
        let data: Data
        do {
            data = try encoder.encode(review)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to encode external signoff review: \(error.localizedDescription)"
            )
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw StudioError.projectSaveFailed(
                "Failed to save external signoff review: \(error.localizedDescription)"
            )
        }
        return url
    }

    public func load(forProjectAt projectRoot: URL) throws -> ExternalSignoffReview {
        let url = reviewURL(forProjectAt: projectRoot)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StudioError.projectLoadFailed(
                "Failed to read external signoff review: \(error.localizedDescription)"
            )
        }

        do {
            return try decoder.decode(ExternalSignoffReview.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed(
                "Failed to decode external signoff review: \(error.localizedDescription)"
            )
        }
    }

    @discardableResult
    public func approve(
        forProjectAt projectRoot: URL,
        approvedBy reviewer: String,
        approvedAt date: Date,
        approvalKind: ExternalSignoffReview.ApprovalKind = .human,
        waiverIDs: [String]? = nil
    ) throws -> ExternalSignoffReview {
        let review = try load(forProjectAt: projectRoot)
        let approved = review.approving(
            by: reviewer,
            at: date,
            approvalKind: approvalKind,
            waiverIDs: waiverIDs
        )
        try save(approved, forProjectAt: projectRoot)
        return approved
    }
}
