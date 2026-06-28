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
    case artifactPreviewNotFound(runID: String, artifactPath: String)
    case artifactPreviewEscapesProject(path: String)
    case artifactPreviewInputMissing(path: String)
    case artifactPreviewUnreadable(path: String, message: String)
    case artifactPreviewInvalidLimit(limit: Int)
    case signoffRepairHintNotFound(runID: String)

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
        case .artifactPreviewNotFound(let runID, let artifactPath):
            "Run \(runID) does not expose an artifact for preview: \(artifactPath)"
        case .artifactPreviewEscapesProject(let path):
            "Artifact preview target is outside the project root: \(path)"
        case .artifactPreviewInputMissing(let path):
            "Artifact preview input is missing: \(path)"
        case .artifactPreviewUnreadable(let path, let message):
            "Artifact preview input could not be read at \(path): \(message)"
        case .artifactPreviewInvalidLimit(let limit):
            "Artifact preview byte limit must be positive: \(limit)"
        case .signoffRepairHintNotFound(let runID):
            "Run \(runID) does not expose DRC or LVS repair hint reports for signoff repair planning."
        }
    }
}
