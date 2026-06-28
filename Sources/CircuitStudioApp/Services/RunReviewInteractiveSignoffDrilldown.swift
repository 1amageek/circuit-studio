import Foundation

public struct RunReviewInteractiveSignoffDrilldown: Sendable, Hashable {
    public enum Domain: String, Sendable, Hashable, CaseIterable {
        case designDiff = "design-diff"
        case drc
        case lvs
        case pex
        case simulation
        case postLayout = "post-layout"
        case waveform
    }

    public enum Interaction: String, Sendable, Hashable {
        case artifactPreview = "artifact-preview"
        case issueEvidence = "issue-evidence"
        case repairActionSelection = "repair-action-selection"
        case designDiffCanvas = "design-diff-canvas"
        case waveformTraceSelection = "waveform-trace-selection"
        case waveformComparison = "waveform-comparison"
    }

    public let runID: String
    public let sections: [Section]
    public let artifactIndex: [ArtifactReference]
    public let failures: [Failure]

    public init(
        runID: String,
        sections: [Section],
        artifactIndex: [ArtifactReference],
        failures: [Failure]
    ) {
        self.runID = runID
        self.sections = sections
        self.artifactIndex = artifactIndex
        self.failures = failures
    }

    public var hasContent: Bool {
        !sections.isEmpty || !artifactIndex.isEmpty || !failures.isEmpty
    }

    public func section(for domain: Domain) -> Section? {
        sections.first { $0.domain == domain }
    }

    public struct Section: Sendable, Hashable {
        public let domain: Domain
        public let title: String
        public let items: [Item]

        public init(domain: Domain, title: String, items: [Item]) {
            self.domain = domain
            self.title = title
            self.items = items
        }
    }

    public struct Item: Sendable, Hashable {
        public let itemID: String
        public let domain: Domain
        public let title: String
        public let status: String
        public let passed: Bool?
        public let stageID: String?
        public let interactions: [Interaction]
        public let artifactRefs: [ArtifactReference]
        public let metrics: [Metric]
        public let detailGroups: [DetailGroup]
        public let issues: [Issue]

        public init(
            itemID: String,
            domain: Domain,
            title: String,
            status: String,
            passed: Bool?,
            stageID: String?,
            interactions: [Interaction],
            artifactRefs: [ArtifactReference],
            metrics: [Metric] = [],
            detailGroups: [DetailGroup] = [],
            issues: [Issue] = []
        ) {
            self.itemID = itemID
            self.domain = domain
            self.title = title
            self.status = status
            self.passed = passed
            self.stageID = stageID
            self.interactions = interactions
            self.artifactRefs = artifactRefs
            self.metrics = metrics
            self.detailGroups = detailGroups
            self.issues = issues
        }
    }

    public struct Issue: Sendable, Hashable {
        public let issueID: String
        public let severity: String
        public let label: String
        public let count: Int?
        public let message: String
        public let suggestedFixes: [String]
        public let repairActionHints: [RunReviewSignoffRepairActionHint]
        public let detailRows: [DetailRow]
        public let artifactRefs: [ArtifactReference]

        public init(
            issueID: String,
            severity: String,
            label: String,
            count: Int?,
            message: String,
            suggestedFixes: [String],
            repairActionHints: [RunReviewSignoffRepairActionHint],
            detailRows: [DetailRow],
            artifactRefs: [ArtifactReference]
        ) {
            self.issueID = issueID
            self.severity = severity
            self.label = label
            self.count = count
            self.message = message
            self.suggestedFixes = suggestedFixes
            self.repairActionHints = repairActionHints
            self.detailRows = detailRows
            self.artifactRefs = artifactRefs
        }
    }

    public struct DetailGroup: Sendable, Hashable {
        public let title: String
        public let rows: [DetailRow]

        public init(title: String, rows: [DetailRow]) {
            self.title = title
            self.rows = rows
        }
    }

    public struct DetailRow: Sendable, Hashable {
        public let label: String
        public let metrics: [Metric]

        public init(label: String, metrics: [Metric]) {
            self.label = label
            self.metrics = metrics
        }
    }

    public struct Metric: Sendable, Hashable {
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct ArtifactReference: Sendable, Hashable {
        public let refID: String
        public let source: String
        public let role: String
        public let artifactID: String?
        public let stageID: String?
        public let path: String
        public let kind: String
        public let format: String
        public let sha256: String?
        public let byteCount: Int64?
        public let integrityStatus: String?
        public let integrityMessage: String?

        public init(
            refID: String,
            source: String,
            role: String,
            artifactID: String?,
            stageID: String?,
            path: String,
            kind: String,
            format: String,
            sha256: String?,
            byteCount: Int64?,
            integrityStatus: String?,
            integrityMessage: String?
        ) {
            self.refID = refID
            self.source = source
            self.role = role
            self.artifactID = artifactID
            self.stageID = stageID
            self.path = path
            self.kind = kind
            self.format = format
            self.sha256 = sha256
            self.byteCount = byteCount
            self.integrityStatus = integrityStatus
            self.integrityMessage = integrityMessage
        }
    }

    public struct Failure: Sendable, Hashable {
        public let failureID: String
        public let severity: String
        public let message: String
        public let artifactRefs: [ArtifactReference]
        public let suggestedActions: [String]

        public init(
            failureID: String,
            severity: String,
            message: String,
            artifactRefs: [ArtifactReference],
            suggestedActions: [String]
        ) {
            self.failureID = failureID
            self.severity = severity
            self.message = message
            self.artifactRefs = artifactRefs
            self.suggestedActions = suggestedActions
        }
    }
}
