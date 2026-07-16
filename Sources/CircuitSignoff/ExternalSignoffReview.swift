import Foundation

public struct ExternalSignoffReview: Sendable, Hashable, Codable {
    public enum ApprovalKind: String, Sendable, Hashable, Codable {
        case human
        case automated
    }

    public let reports: [ExternalSignoffToolReport]
    public let approvedBy: String?
    public let approvedAt: Date?
    public let approvalKind: ApprovalKind?
    public let waiverIDs: [String]

    public init(
        reports: [ExternalSignoffToolReport],
        approvedBy: String? = nil,
        approvedAt: Date? = nil,
        approvalKind: ApprovalKind? = nil,
        waiverIDs: [String] = []
    ) {
        self.reports = reports
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.approvalKind = approvalKind
        self.waiverIDs = waiverIDs
    }

    public var passed: Bool {
        !reports.isEmpty && reports.allSatisfy(\.passed)
    }

    public var isApproved: Bool {
        approvedBy?.isEmpty == false && approvedAt != nil
    }

    public var isReadyForPEX: Bool {
        passed && isApproved
    }

    public func approving(
        by reviewer: String,
        at date: Date,
        approvalKind: ApprovalKind = .human,
        waiverIDs: [String]? = nil
    ) -> ExternalSignoffReview {
        ExternalSignoffReview(
            reports: reports,
            approvedBy: reviewer,
            approvedAt: date,
            approvalKind: approvalKind,
            waiverIDs: waiverIDs ?? self.waiverIDs
        )
    }
}
