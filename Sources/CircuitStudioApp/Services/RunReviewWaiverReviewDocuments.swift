import Foundation
import CircuiteFoundation
import DesignFlowKernel

enum WaiverArtifactKind {
    case drc
    case lvs
}

struct AppliedWaiverEdit: Sendable, Hashable {
    let targetPath: String
    let beforeData: Data
    let afterData: Data
    let beforeReference: ArtifactReference
    let afterReference: ArtifactReference
}

struct WaiverEditPlanningFeedback: Sendable, Hashable {
    let status: String
    let candidatePlanRef: ArtifactReference
    let planVerificationRef: ArtifactReference
    let rejectedPlansRef: ArtifactReference?
}

struct DRCWaiverReviewDocument: Decodable {
    let summary: DRCWaiverReviewSummary
}

struct DRCWaiverReviewSummary: Decodable {
    let waivedViolationCount: Int
    let violationBuckets: [DRCWaiverReviewBucket]
    let unusedWaiverIDs: [String]
    let waiverSources: [WaiverSourceReferenceDocument]
    let editProposals: [WaiverEditProposalDocument]

    private enum CodingKeys: String, CodingKey {
        case waivedViolationCount
        case violationBuckets
        case unusedWaiverIDs
        case waiverSources
        case sourceReferences
        case waiverEditProposals
        case editProposals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        waivedViolationCount = try container.decodeIfPresent(Int.self, forKey: .waivedViolationCount) ?? 0
        violationBuckets = try container.decodeIfPresent(
            [DRCWaiverReviewBucket].self,
            forKey: .violationBuckets
        ) ?? []
        unusedWaiverIDs = try container.decodeIfPresent([String].self, forKey: .unusedWaiverIDs) ?? []
        waiverSources = try container.decodeIfPresent(
            [WaiverSourceReferenceDocument].self,
            forKey: .waiverSources
        ) ?? container.decodeIfPresent(
            [WaiverSourceReferenceDocument].self,
            forKey: .sourceReferences
        ) ?? []
        editProposals = try container.decodeIfPresent(
            [WaiverEditProposalDocument].self,
            forKey: .waiverEditProposals
        ) ?? container.decodeIfPresent(
            [WaiverEditProposalDocument].self,
            forKey: .editProposals
        ) ?? []
    }
}

struct DRCWaiverReviewBucket: Decodable {
    let ruleID: String?
    let kind: String?
    let layer: String?
    let waivedCount: Int

    private enum CodingKeys: String, CodingKey {
        case ruleID
        case kind
        case layer
        case waivedCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ruleID = try container.decodeIfPresent(String.self, forKey: .ruleID)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        layer = try container.decodeIfPresent(String.self, forKey: .layer)
        waivedCount = try container.decodeIfPresent(Int.self, forKey: .waivedCount) ?? 0
    }
}

struct LVSWaiverReviewDocument: Decodable {
    let summary: LVSWaiverReviewSummary
}

struct LVSWaiverReviewSummary: Decodable {
    let waivedMismatchCount: Int
    let mismatchBuckets: [LVSWaiverReviewBucket]
    let unusedWaiverIDs: [String]
    let waiverSources: [WaiverSourceReferenceDocument]
    let editProposals: [WaiverEditProposalDocument]

    private enum CodingKeys: String, CodingKey {
        case waivedMismatchCount
        case mismatchBuckets
        case unusedWaiverIDs
        case waiverSources
        case sourceReferences
        case waiverEditProposals
        case editProposals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        waivedMismatchCount = try container.decodeIfPresent(Int.self, forKey: .waivedMismatchCount) ?? 0
        mismatchBuckets = try container.decodeIfPresent(
            [LVSWaiverReviewBucket].self,
            forKey: .mismatchBuckets
        ) ?? []
        unusedWaiverIDs = try container.decodeIfPresent([String].self, forKey: .unusedWaiverIDs) ?? []
        waiverSources = try container.decodeIfPresent(
            [WaiverSourceReferenceDocument].self,
            forKey: .waiverSources
        ) ?? container.decodeIfPresent(
            [WaiverSourceReferenceDocument].self,
            forKey: .sourceReferences
        ) ?? []
        editProposals = try container.decodeIfPresent(
            [WaiverEditProposalDocument].self,
            forKey: .waiverEditProposals
        ) ?? container.decodeIfPresent(
            [WaiverEditProposalDocument].self,
            forKey: .editProposals
        ) ?? []
    }
}

struct LVSWaiverReviewBucket: Decodable {
    let ruleID: String?
    let category: String?
    let componentSignature: String?
    let waivedCount: Int

    private enum CodingKeys: String, CodingKey {
        case ruleID
        case category
        case componentSignature
        case waivedCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ruleID = try container.decodeIfPresent(String.self, forKey: .ruleID)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        componentSignature = try container.decodeIfPresent(String.self, forKey: .componentSignature)
        waivedCount = try container.decodeIfPresent(Int.self, forKey: .waivedCount) ?? 0
    }
}

struct WaiverSourceReferenceDocument: Decodable {
    let waiverID: String
    let path: String
    let lineStart: Int?
    let lineEnd: Int?
    let ruleID: String?
    let diagnosticID: String?
    let reason: String

    private enum CodingKeys: String, CodingKey {
        case waiverID
        case path
        case lineStart
        case lineEnd
        case ruleID
        case diagnosticID
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        waiverID = try container.decodeIfPresent(String.self, forKey: .waiverID) ?? "waiver"
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        lineStart = try container.decodeIfPresent(Int.self, forKey: .lineStart)
        lineEnd = try container.decodeIfPresent(Int.self, forKey: .lineEnd)
        ruleID = try container.decodeIfPresent(String.self, forKey: .ruleID)
        diagnosticID = try container.decodeIfPresent(String.self, forKey: .diagnosticID)
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }

    var reviewSourceReference: RunReviewWaiverSourceReference {
        RunReviewWaiverSourceReference(
            waiverID: waiverID,
            path: path,
            lineStart: lineStart,
            lineEnd: lineEnd,
            ruleID: ruleID,
            diagnosticID: diagnosticID,
            reason: reason
        )
    }
}

struct WaiverEditProposalDocument: Decodable {
    let proposalID: String
    let waiverID: String?
    let kind: String
    let status: String
    let targetPath: String
    let operation: String
    let summary: String
    let replacementText: String?
    let risk: String

    private enum CodingKeys: String, CodingKey {
        case proposalID
        case waiverID
        case kind
        case status
        case targetPath
        case operation
        case summary
        case replacementText
        case risk
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proposalID = try container.decodeIfPresent(String.self, forKey: .proposalID) ?? UUID().uuidString
        waiverID = try container.decodeIfPresent(String.self, forKey: .waiverID)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "waiver-edit"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "proposed"
        targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath) ?? ""
        operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "review"
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        replacementText = try container.decodeIfPresent(String.self, forKey: .replacementText)
        risk = try container.decodeIfPresent(String.self, forKey: .risk) ?? "medium"
    }

    var reviewEditProposal: RunReviewWaiverEditProposal {
        RunReviewWaiverEditProposal(
            proposalID: proposalID,
            waiverID: waiverID,
            kind: kind,
            status: status,
            targetPath: targetPath,
            operation: operation,
            summary: summary,
            replacementText: replacementText,
            risk: risk
        )
    }
}
