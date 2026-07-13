import Foundation

enum SignoffArtifactKind {
    case drc
    case lvs
    case pex
    case generatedLayoutSignoffCorpus
    case retainedSignoffReport
    case simulationMetric
    case simulationMeasurement
    case postLayoutComparison
}

struct DRCReviewDocument: Decodable {
    let reportURL: URL?
    let manifestURL: URL?
    let summary: DRCReviewSummary
}

struct DRCReviewSummary: Decodable {
    let status: String
    let toolName: String
    let topCell: String
    let passed: Bool
    let activeViolationCount: Int
    let waivedViolationCount: Int
    let violationBuckets: [DRCReviewBucket]
}

struct DRCReviewBucket: Decodable {
    let ruleID: String?
    let kind: String?
    let layer: String?
    let activeCount: Int
    let waivedCount: Int?
    let maxMeasured: Double?
    let required: Double?
    let representativeRegion: DRCReviewRegion?
    let relatedShapeIDs: [String]?
    let relatedNetIDs: [String]?
    let suggestedFixes: [String]
}

struct DRCReviewRegion: Decodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct LVSReviewDocument: Decodable {
    let schemaVersion: Int
    let reportURL: URL?
    let manifestURL: URL?
    let summary: LVSReviewSummary
}

struct LVSReviewSummary: Decodable {
    let executionStatus: String
    let verdict: String
    let readiness: String
    let blockingReasons: [LVSReviewBlockingReason]
    let toolName: String
    let topCell: String
    let layoutInputKind: String?
    let activeMismatchCount: Int
    let waivedMismatchCount: Int
    let mismatchBuckets: [LVSReviewBucket]
    let extractedLayoutNetlistURL: URL?
}

struct LVSReviewBlockingReason: Decodable, Sendable, Hashable {
    let code: String
    let message: String
    let evidenceReferences: [String]
}

struct LVSReviewBucket: Decodable {
    let ruleID: String?
    let category: String?
    let componentSignature: String?
    let parameterName: String?
    let layoutModel: String?
    let schematicModel: String?
    let activeCount: Int
    let waivedCount: Int?
    let layoutCount: Int?
    let schematicCount: Int?
    let layoutPorts: [String]?
    let schematicPorts: [String]?
    let suggestedFixes: [String]
}

struct PEXReviewDocument: Decodable {
    let manifestURL: URL?
    let summary: PEXReviewSummary
}

struct PEXReviewSummary: Decodable {
    let status: String
    let backendID: String
    let corners: [PEXReviewCorner]
}

struct PEXReviewCorner: Decodable {
    let cornerID: String
    let status: String
    let netCount: Int
    let elementCount: Int
    let topNets: [PEXReviewNet]
    let diagnostics: [PEXReviewDiagnostic]
}

struct PEXReviewNet: Decodable {
    let name: String
    let groundCapF: Double
    let couplingCapF: Double
    let resistanceOhm: Double
    let nodeCount: Int
}

struct PEXReviewDiagnostic: Decodable {
    let severity: String
    let code: String
    let message: String
}
