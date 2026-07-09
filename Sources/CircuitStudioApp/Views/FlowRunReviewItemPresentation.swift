import SwiftUI
import DesignFlowKernel

extension FlowRunReviewItem {
    var reviewSystemImage: String {
        kind.reviewSystemImage
    }

    var reviewForegroundColor: Color {
        severity.reviewForegroundColor
    }
}

extension FlowRunReviewItemKind {
    var reviewSystemImage: String {
        switch self {
        case .designDiff:
            return "doc.text.magnifyingglass"
        case .approvalGate:
            return "checkmark.seal"
        case .toolTrust:
            return "wrench.and.screwdriver"
        case .stageFailure:
            return "xmark.octagon"
        case .stageBlocker:
            return "pause.circle"
        case .diagnosticReview:
            return "exclamationmark.triangle"
        case .artifactIntegrity:
            return "checkmark.shield"
        case .artifactCoverage:
            return "rectangle.stack.badge.exclamationmark"
        case .planningCorrectness:
            return "checklist"
        case .retainedHistory:
            return "chart.line.uptrend.xyaxis"
        case .runGuard:
            return "shield.lefthalf.filled"
        case .crossArtifactEvaluation:
            return "arrow.triangle.branch"
        case .archiveOrContinue:
            return "archivebox"
        case .cancellation:
            return "stop.circle"
        }
    }
}

extension FlowDiagnosticSeverity {
    var reviewForegroundColor: Color {
        switch self {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
