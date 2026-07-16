import Foundation

public enum RunReviewServiceError: Error, LocalizedError, Equatable {
    case nextActionNotFound(actionID: String)
    case suggestedCommandNotFound(actionID: String, commandID: String)
    case waiverReviewNotFound(waiverReviewID: String)
    case waiverEditProposalNotFound(waiverReviewID: String, proposalID: String)
    case unsafeWaiverEditTargetPath(path: String)
    case waiverEditTargetMissing(path: String)
    case waiverEditUnsupportedOperation(operation: String)
    case waiverEditMissingReplacementText(proposalID: String)
    case waiverEditMissingWaiverID(proposalID: String)
    case waiverEditNoChange(proposalID: String)
    case waiverEditApplicationNotFound(waiverReviewID: String, proposalID: String)
    case waiverEditVerificationArtifactEscapesProject(path: String)
    case waiverEditVerificationDesignSpecNotFound(runID: String)
    case waiverEditVerificationLayoutDocumentNotFound(runID: String)
    case waiverEditVerificationInputMissing(path: String)
    case waiverArtifactIntegrityUnverified(path: String, status: String, message: String)
    case artifactPreviewNotFound(runID: String, artifactPath: String)
    case artifactPreviewEscapesProject(path: String)
    case artifactPreviewInputMissing(path: String)
    case artifactPreviewUnreadable(path: String, message: String)
    case artifactPreviewTooLarge(path: String, byteCount: UInt64, limit: Int)
    case artifactPreviewInvalidLimit(limit: Int)
    case artifactPreviewIntegrityUnverified(path: String, status: String, message: String)
    case artifactResourceNotFound(runID: String, artifactPath: String)
    case artifactResourceEscapesProject(path: String)
    case artifactResourceInputMissing(path: String)
    case artifactResourceUnreadable(path: String, message: String)
    case artifactResourceIntegrityUnverified(path: String, status: String, message: String)
    case planningArtifactIntegrityUnverified(path: String, status: String, message: String)
    case signoffArtifactIntegrityUnverified(path: String, status: String, message: String)
    case signoffRepairHintNotFound(runID: String)
    case signoffRepairHintIntegrityUnverified(path: String, status: String, message: String)
    case artifactEvaluationEnvelopeIntegrityUnverified(path: String, status: String, message: String)
    case invalidArtifactReference(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .nextActionNotFound(let actionID):
            "Next action was not found in the shared review bundle: \(actionID)"
        case .suggestedCommandNotFound(let actionID, let commandID):
            "Suggested command was not found for next action \(actionID): \(commandID)"
        case .waiverReviewNotFound(let waiverReviewID):
            "Waiver review item was not found in the shared review bundle: \(waiverReviewID)"
        case .waiverEditProposalNotFound(let waiverReviewID, let proposalID):
            "Waiver edit proposal was not found in review \(waiverReviewID): \(proposalID)"
        case .unsafeWaiverEditTargetPath(let path):
            "Waiver edit target path is unsafe or escapes the project root: \(path)"
        case .waiverEditTargetMissing(let path):
            "Waiver edit target file is missing: \(path)"
        case .waiverEditUnsupportedOperation(let operation):
            "Waiver edit operation is not supported for audited application: \(operation)"
        case .waiverEditMissingReplacementText(let proposalID):
            "Waiver edit proposal requires replacement text: \(proposalID)"
        case .waiverEditMissingWaiverID(let proposalID):
            "Waiver edit proposal requires a waiver ID: \(proposalID)"
        case .waiverEditNoChange(let proposalID):
            "Waiver edit proposal did not change the target file: \(proposalID)"
        case .waiverEditApplicationNotFound(let waiverReviewID, let proposalID):
            "Waiver edit proposal has not been applied in review \(waiverReviewID): \(proposalID)"
        case .waiverEditVerificationArtifactEscapesProject(let path):
            "Waiver edit verification artifact is outside the project root: \(path)"
        case .waiverEditVerificationDesignSpecNotFound(let runID):
            "Run \(runID) does not expose a design-spec artifact for post-waiver edit verification."
        case .waiverEditVerificationLayoutDocumentNotFound(let runID):
            "Run \(runID) does not expose a JSON layout-document artifact for post-waiver edit verification."
        case .waiverEditVerificationInputMissing(let path):
            "Post-waiver edit verification input artifact is missing: \(path)"
        case .waiverArtifactIntegrityUnverified(let path, let status, let message):
            "Waiver artifact integrity requires verified artifact integrity before review: \(path) status=\(status) \(message)"
        case .artifactPreviewNotFound(let runID, let artifactPath):
            "Run \(runID) does not expose an artifact for preview: \(artifactPath)"
        case .artifactPreviewEscapesProject(let path):
            "Artifact preview target is outside the project root: \(path)"
        case .artifactPreviewInputMissing(let path):
            "Artifact preview input is missing: \(path)"
        case .artifactPreviewUnreadable(let path, let message):
            "Artifact preview input could not be read at \(path): \(message)"
        case .artifactPreviewTooLarge(let path, let byteCount, let limit):
            "Artifact preview input exceeds the bounded read limit at \(path): \(byteCount) bytes, limit=\(limit)"
        case .artifactPreviewInvalidLimit(let limit):
            "Artifact preview byte limit must be positive: \(limit)"
        case .artifactPreviewIntegrityUnverified(let path, let status, let message):
            "Artifact preview requires verified artifact integrity: \(path) status=\(status) \(message)"
        case .artifactResourceNotFound(let runID, let artifactPath):
            "Run \(runID) does not expose the requested artifact: \(artifactPath)"
        case .artifactResourceEscapesProject(let path):
            "Artifact is outside the project root: \(path)"
        case .artifactResourceInputMissing(let path):
            "Artifact is missing or is not a regular file: \(path)"
        case .artifactResourceUnreadable(let path, let message):
            "Artifact could not be verified at \(path): \(message)"
        case .artifactResourceIntegrityUnverified(let path, let status, let message):
            "Artifact rendering requires current verified integrity: \(path) status=\(status) \(message)"
        case .planningArtifactIntegrityUnverified(let path, let status, let message):
            "Planning artifact integrity requires verified artifact integrity before projection: \(path) status=\(status) \(message)"
        case .signoffArtifactIntegrityUnverified(let path, let status, let message):
            "Signoff artifact integrity must be verified before projection: \(path) status=\(status) \(message)"
        case .signoffRepairHintNotFound(let runID):
            "Run \(runID) does not expose DRC or LVS repair hint reports for signoff repair planning."
        case .signoffRepairHintIntegrityUnverified(let path, let status, let message):
            "Signoff repair hint requires verified artifact integrity before planning: \(path) status=\(status) \(message)"
        case .artifactEvaluationEnvelopeIntegrityUnverified(let path, let status, let message):
            "Artifact evaluation envelope requires verified artifact integrity: \(path) status=\(status) \(message)"
        case .invalidArtifactReference(let path, let message):
            "Run manifest contains an invalid canonical artifact reference: \(path) \(message)"
        }
    }
}
