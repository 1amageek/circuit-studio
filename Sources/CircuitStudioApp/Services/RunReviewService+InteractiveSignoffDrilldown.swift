import DesignFlowKernel
import Foundation

extension RunReviewService {
    public func loadInteractiveSignoffDrilldown(
        runID: String,
        projectRoot: URL
    ) async throws -> RunReviewInteractiveSignoffDrilldown {
        let review = try await loadRun(runID: runID, projectRoot: projectRoot)
        return interactiveSignoffDrilldown(from: review)
    }

    public func interactiveSignoffDrilldown(
        from review: RunReview
    ) -> RunReviewInteractiveSignoffDrilldown {
        let sections = orderedDrilldownSections(
            designDiffSection: designDiffDrilldownSection(review.planning.designDiffSummary),
            signoffSections: signoffDrilldownSections(review.signoff)
        )
        let artifactIndex = drilldownArtifactIndex(sections)
        let failures = drilldownFailures(
            planningDecodeIssues: review.planning.decodeIssues,
            signoffDecodeIssues: review.signoff.decodeIssues,
            artifactIndex: artifactIndex
        )
        return RunReviewInteractiveSignoffDrilldown(
            runID: review.runID,
            sections: sections,
            artifactIndex: artifactIndex,
            failures: failures
        )
    }

    private func orderedDrilldownSections(
        designDiffSection: RunReviewInteractiveSignoffDrilldown.Section?,
        signoffSections: [RunReviewInteractiveSignoffDrilldown.Section]
    ) -> [RunReviewInteractiveSignoffDrilldown.Section] {
        var sections: [RunReviewInteractiveSignoffDrilldown.Section] = []
        if let designDiffSection {
            sections.append(designDiffSection)
        }
        let sectionsByDomain = Dictionary(uniqueKeysWithValues: signoffSections.map { ($0.domain, $0) })
        for domain in RunReviewInteractiveSignoffDrilldown.Domain.allCases where domain != .designDiff {
            guard let section = sectionsByDomain[domain], !section.items.isEmpty else {
                continue
            }
            sections.append(section)
        }
        return sections
    }

    private func signoffDrilldownSections(
        _ signoff: RunReviewSignoffSummary
    ) -> [RunReviewInteractiveSignoffDrilldown.Section] {
        let cardItems = signoff.cards.map(signoffDrilldownItem)
        var sectionsByDomain = Dictionary(grouping: cardItems, by: \.domain).mapValues { items in
            items.sorted { left, right in
                if left.stageID != right.stageID {
                    return (left.stageID ?? "") < (right.stageID ?? "")
                }
                return left.itemID < right.itemID
            }
        }
        let waveformItems = waveformDrilldownItems(signoff.cards)
        if !waveformItems.isEmpty {
            sectionsByDomain[.waveform] = waveformItems
        }
        return sectionsByDomain.keys.sorted { left, right in
            drilldownDomainRank(left) < drilldownDomainRank(right)
        }.compactMap { domain in
            guard let items = sectionsByDomain[domain], !items.isEmpty else {
                return nil
            }
            return RunReviewInteractiveSignoffDrilldown.Section(
                domain: domain,
                title: drilldownDomainTitle(domain),
                items: items
            )
        }
    }

    private func signoffDrilldownItem(
        _ card: RunReviewSignoffCard
    ) -> RunReviewInteractiveSignoffDrilldown.Item {
        let domain = drilldownDomain(for: card)
        let artifacts = drilldownArtifactReferences([card.artifact] + card.relatedArtifacts)
        let issues = card.issues.enumerated().map { index, issue in
            RunReviewInteractiveSignoffDrilldown.Issue(
                issueID: "\(card.artifact.reference.locator.location.value)#issue-\(index)",
                severity: issue.severity,
                label: issue.label,
                count: issue.count,
                message: issue.message,
                suggestedFixes: issue.suggestedFixes,
                repairActionHints: issue.repairActionHints,
                detailRows: issue.detailRows.map(drilldownDetailRow),
                artifactReferences: drilldownArtifactReferences(issue.evidenceArtifacts)
            )
        }
        return RunReviewInteractiveSignoffDrilldown.Item(
            itemID: "signoff:\(domain.rawValue):\(card.artifact.reference.locator.location.value)",
            domain: domain,
            title: card.title,
            status: card.status,
            passed: card.passed,
            stageID: card.stageID,
            interactions: signoffInteractions(card: card),
            artifactReferences: artifacts,
            metrics: card.primaryMetrics.map(drilldownMetric),
            detailGroups: card.detailSections.map(drilldownDetailGroup),
            issues: issues
        )
    }

    private func waveformDrilldownItems(
        _ cards: [RunReviewSignoffCard]
    ) -> [RunReviewInteractiveSignoffDrilldown.Item] {
        var seenPaths = Set<String>()
        var items: [RunReviewInteractiveSignoffDrilldown.Item] = []
        var waveformArtifacts: [FlowRunReviewArtifact] = []
        for card in cards {
            for artifact in [card.artifact] + card.relatedArtifacts where artifact.reference.locator.kind == .waveform {
                guard seenPaths.insert(artifact.reference.locator.location.value).inserted else {
                    continue
                }
                waveformArtifacts.append(artifact)
            }
        }
        waveformArtifacts.sort { left, right in
            left.reference.id.rawValue < right.reference.id.rawValue
        }

        for artifact in waveformArtifacts {
            items.append(
                RunReviewInteractiveSignoffDrilldown.Item(
                    itemID: "waveform:\(artifact.reference.locator.location.value)",
                    domain: .waveform,
                    title: artifact.reference.id.rawValue,
                    status: artifact.integrity?.status.rawValue ?? "available",
                    passed: artifact.integrity?.status == .verified ? true : nil,
                    stageID: artifact.stageID,
                    interactions: [.artifactPreview, .waveformTraceSelection],
                    artifactReferences: drilldownArtifactReferences([artifact]),
                    metrics: compactDrilldownMetrics([
                        ("Role", artifact.purpose.rawValue),
                        ("Format", artifact.reference.locator.format.rawValue),
                        ("Bytes", String(artifact.reference.byteCount)),
                        ("Integrity", artifact.integrity?.status.rawValue),
                    ])
                )
            )
        }

        for card in cards {
            let comparisonArtifacts = ([card.artifact] + card.relatedArtifacts)
                .filter { $0.reference.locator.kind == .waveform }
            guard comparisonArtifacts.count >= 2 else {
                continue
            }
            items.append(
                RunReviewInteractiveSignoffDrilldown.Item(
                    itemID: "waveform-comparison:\(card.artifact.reference.locator.location.value)",
                    domain: .waveform,
                    title: "\(card.title) waveform comparison",
                    status: card.status,
                    passed: card.passed,
                    stageID: card.stageID,
                    interactions: [.artifactPreview, .waveformComparison],
                    artifactReferences: drilldownArtifactReferences(comparisonArtifacts),
                    metrics: [
                        RunReviewInteractiveSignoffDrilldown.Metric(
                            label: "Sources",
                            value: "\(comparisonArtifacts.count)"
                        ),
                    ]
                )
            )
        }
        return items
    }

    private func designDiffDrilldownSection(
        _ summary: RunReviewDesignDiffSummary?
    ) -> RunReviewInteractiveSignoffDrilldown.Section? {
        guard let summary else {
            return nil
        }
        let summaryArtifacts = drilldownArtifactReferences(
            (summary.baseSnapshot.map { [$0] } ?? [])
                + (summary.proposedSnapshot.map { [$0] } ?? [])
                + summary.changes.flatMap(\.artifacts),
            role: "design-diff-summary"
        )
        var items: [RunReviewInteractiveSignoffDrilldown.Item] = [
            RunReviewInteractiveSignoffDrilldown.Item(
                itemID: "design-diff:summary",
                domain: .designDiff,
                title: summary.title,
                status: summary.reviewState,
                passed: nil,
                stageID: nil,
                interactions: [.artifactPreview, .designDiffCanvas],
                artifactReferences: summaryArtifacts,
                metrics: compactDrilldownMetrics([
                    ("Actor", summary.actor),
                    ("Review", summary.reviewState),
                    ("Changes", "\(summary.changeCount)"),
                    ("Canvases", "\(summary.canvases.count)"),
                ]),
                detailGroups: [
                    drilldownBucketGroup(title: "Domains", buckets: summary.domains),
                    drilldownBucketGroup(title: "Operations", buckets: summary.operations),
                ].filter { !$0.rows.isEmpty }
            ),
        ]

        items.append(contentsOf: summary.changes.map { change in
            RunReviewInteractiveSignoffDrilldown.Item(
                itemID: "design-diff:change:\(change.changeID)",
                domain: .designDiff,
                title: change.summary,
                status: change.operation,
                passed: nil,
                stageID: nil,
                interactions: [.artifactPreview, .designDiffCanvas],
                artifactReferences: drilldownArtifactReferences(change.artifacts, role: "design-diff-change"),
                metrics: compactDrilldownMetrics([
                    ("Domain", change.domain),
                    ("Operation", change.operation),
                    ("Path", change.path),
                    ("From", change.fromPath),
                    ("Artifacts", "\(change.artifactCount)"),
                ]),
                detailGroups: designDiffDetailGroups(change)
            )
        })

        return RunReviewInteractiveSignoffDrilldown.Section(
            domain: .designDiff,
            title: drilldownDomainTitle(.designDiff),
            items: items
        )
    }

    private func designDiffDetailGroups(
        _ change: RunReviewDesignDiffChangeSummary
    ) -> [RunReviewInteractiveSignoffDrilldown.DetailGroup] {
        var groups: [RunReviewInteractiveSignoffDrilldown.DetailGroup] = []
        if let context = change.pathContext {
            groups.append(
                RunReviewInteractiveSignoffDrilldown.DetailGroup(
                    title: "Path Context",
                    rows: [
                        RunReviewInteractiveSignoffDrilldown.DetailRow(
                            label: context.displayName,
                            metrics: compactDrilldownMetrics([
                                ("Scope", context.scope),
                                ("Cell", context.cellID),
                                ("Collection", context.collection),
                                ("Layer", context.layerID),
                                ("Entity", context.entityID),
                                ("Property", context.propertyPath),
                            ])
                        ),
                    ]
                )
            )
        }
        if let focus = change.visualFocus {
            groups.append(
                RunReviewInteractiveSignoffDrilldown.DetailGroup(
                    title: "Visual Focus",
                    rows: [
                        RunReviewInteractiveSignoffDrilldown.DetailRow(
                            label: focus.title,
                            metrics: compactDrilldownMetrics([
                                ("Kind", focus.kind),
                                ("Subtitle", focus.subtitle),
                                ("Emphasis", focus.emphasis),
                                ("Fields", focus.changedFields.isEmpty ? nil : focus.changedFields.joined(separator: ", ")),
                            ])
                        ),
                    ]
                )
            )
        }
        if !change.valueChanges.isEmpty {
            groups.append(
                RunReviewInteractiveSignoffDrilldown.DetailGroup(
                    title: "Value Changes",
                    rows: change.valueChanges.map { valueChange in
                        RunReviewInteractiveSignoffDrilldown.DetailRow(
                            label: valueChange.path,
                            metrics: compactDrilldownMetrics([
                                ("State", valueChange.state),
                                ("Before", valueChange.beforePreview),
                                ("After", valueChange.afterPreview),
                            ])
                        )
                    }
                )
            )
        }
        return groups
    }

    private func drilldownFailures(
        planningDecodeIssues: [PlanningArtifactDecodeIssue],
        signoffDecodeIssues: [RunReviewArtifactDecodeIssue],
        artifactIndex: [RunReviewInteractiveSignoffDrilldown.ArtifactSummary]
    ) -> [RunReviewInteractiveSignoffDrilldown.Failure] {
        let planningFailures = planningDecodeIssues.map { issue in
            RunReviewInteractiveSignoffDrilldown.Failure(
                failureID: "planning-decode:\(issue.artifactPath)",
                severity: "warning",
                message: issue.message,
                artifactReferences: [
                    drilldownArtifactReference(
                        path: issue.artifactPath,
                        role: issue.artifactRole,
                        source: "run-ledger"
                    ),
                ],
                suggestedActions: ["inspect-artifact-preview", "validate-artifact-schema"]
            )
        }
        let signoffFailures = signoffDecodeIssues.map { issue in
            RunReviewInteractiveSignoffDrilldown.Failure(
                failureID: "signoff-decode:\(issue.artifactPath)",
                severity: "error",
                message: issue.message,
                artifactReferences: [
                    drilldownArtifactReference(
                        path: issue.artifactPath,
                        role: issue.artifactRole,
                        source: "run-ledger"
                    ),
                ],
                suggestedActions: ["inspect-artifact-preview", "regenerate-signoff-report"]
            )
        }
        var integrityFailures: [RunReviewInteractiveSignoffDrilldown.Failure] = []
        for artifact in artifactIndex {
            guard let status = artifact.integrityStatus, status != "verified" else {
                continue
            }
            integrityFailures.append(
                RunReviewInteractiveSignoffDrilldown.Failure(
                    failureID: "artifact-integrity:\(artifact.path)",
                    severity: status == "missingDigest" || status == "missingByteCount" ? "warning" : "error",
                    message: artifact.integrityMessage ?? status,
                    artifactReferences: [artifact],
                    suggestedActions: ["inspect-ledger-artifact-ref", "rerun-artifact-integrity-gate"]
                )
            )
        }
        return planningFailures + signoffFailures + integrityFailures
    }

    private func drilldownArtifactIndex(
        _ sections: [RunReviewInteractiveSignoffDrilldown.Section]
    ) -> [RunReviewInteractiveSignoffDrilldown.ArtifactSummary] {
        var refsByPath: [String: RunReviewInteractiveSignoffDrilldown.ArtifactSummary] = [:]
        let refs = sections.flatMap { section in
            section.items.flatMap { item in
                item.artifactReferences
                    + item.issues.flatMap(\.artifactReferences)
            }
        }
        for ref in refs {
            if let existing = refsByPath[ref.path] {
                refsByPath[ref.path] = preferredDrilldownArtifactReference(existing, ref)
            } else {
                refsByPath[ref.path] = ref
            }
        }
        return refsByPath.values.sorted { left, right in
            if left.role != right.role {
                return left.role < right.role
            }
            return left.path < right.path
        }
    }

    private func preferredDrilldownArtifactReference(
        _ current: RunReviewInteractiveSignoffDrilldown.ArtifactSummary,
        _ candidate: RunReviewInteractiveSignoffDrilldown.ArtifactSummary
    ) -> RunReviewInteractiveSignoffDrilldown.ArtifactSummary {
        let currentScore = drilldownArtifactReferenceEvidenceScore(current)
        let candidateScore = drilldownArtifactReferenceEvidenceScore(candidate)
        if candidateScore != currentScore {
            return candidateScore > currentScore ? candidate : current
        }
        return current
    }

    private func drilldownArtifactReferenceEvidenceScore(
        _ ref: RunReviewInteractiveSignoffDrilldown.ArtifactSummary
    ) -> Int {
        var score = 0
        if ref.source == "run-ledger" {
            score += 8
        }
        if ref.integrityStatus != nil {
            score += 4
        }
        if ref.sha256 != nil {
            score += 2
        }
        if ref.byteCount != nil {
            score += 1
        }
        return score
    }

    private func signoffInteractions(
        card: RunReviewSignoffCard
    ) -> [RunReviewInteractiveSignoffDrilldown.Interaction] {
        var interactions: [RunReviewInteractiveSignoffDrilldown.Interaction] = [.artifactPreview]
        if !card.issues.isEmpty {
            interactions.append(.issueEvidence)
        }
        if card.issues.contains(where: { !$0.repairActionHints.isEmpty }) {
            interactions.append(.repairActionSelection)
        }
        if ([card.artifact] + card.relatedArtifacts).filter({ $0.reference.locator.kind == .waveform }).count >= 2 {
            interactions.append(.waveformComparison)
        }
        return interactions
    }

    private func drilldownDomain(
        for card: RunReviewSignoffCard
    ) -> RunReviewInteractiveSignoffDrilldown.Domain {
        switch card.domain {
        case "DRC":
            return .drc
        case "LVS":
            return .lvs
        case "PEX":
            return .pex
        case "Oracle":
            return .oracle
        case "Post-layout":
            return .postLayout
        default:
            return .simulation
        }
    }

    private func drilldownDomainTitle(
        _ domain: RunReviewInteractiveSignoffDrilldown.Domain
    ) -> String {
        switch domain {
        case .designDiff:
            return "Design Diff"
        case .drc:
            return "DRC"
        case .lvs:
            return "LVS"
        case .pex:
            return "PEX"
        case .oracle:
            return "Oracle"
        case .simulation:
            return "Simulation"
        case .postLayout:
            return "Post-layout"
        case .waveform:
            return "Waveforms"
        }
    }

    private func drilldownDomainRank(
        _ domain: RunReviewInteractiveSignoffDrilldown.Domain
    ) -> Int {
        switch domain {
        case .designDiff:
            return 0
        case .drc:
            return 1
        case .lvs:
            return 2
        case .pex:
            return 3
        case .oracle:
            return 4
        case .simulation:
            return 5
        case .postLayout:
            return 6
        case .waveform:
            return 7
        }
    }

    private func drilldownArtifactReferences(
        _ artifacts: [FlowRunReviewArtifact]
    ) -> [RunReviewInteractiveSignoffDrilldown.ArtifactSummary] {
        var seenPaths = Set<String>()
        return artifacts.filter { artifact in
            seenPaths.insert(artifact.reference.locator.location.value).inserted
        }.map(drilldownArtifactReference)
    }

    private func drilldownArtifactReferences(
        _ artifacts: [RunReviewDesignDiffArtifactSummary],
        role: String
    ) -> [RunReviewInteractiveSignoffDrilldown.ArtifactSummary] {
        var seenPaths = Set<String>()
        return artifacts.filter { artifact in
            seenPaths.insert(artifact.path).inserted
        }.map { artifact in
            RunReviewInteractiveSignoffDrilldown.ArtifactSummary(
                refID: artifact.artifactID ?? artifact.path,
                source: "design-diff",
                role: role,
                artifactID: artifact.artifactID,
                stageID: nil,
                path: artifact.path,
                kind: "design-diff-ref",
                format: "unknown",
                sha256: artifact.sha256,
                byteCount: artifact.byteCount,
                integrityStatus: nil,
                integrityMessage: nil
            )
        }
    }

    private func drilldownArtifactReference(
        _ artifact: FlowRunReviewArtifact
    ) -> RunReviewInteractiveSignoffDrilldown.ArtifactSummary {
        RunReviewInteractiveSignoffDrilldown.ArtifactSummary(
            refID: artifact.reference.id.rawValue,
            source: "run-ledger",
            role: artifact.purpose.rawValue,
            artifactID: artifact.reference.id.rawValue,
            stageID: artifact.stageID,
            path: artifact.reference.locator.location.value,
            kind: artifact.reference.locator.kind.rawValue,
            format: artifact.reference.locator.format.rawValue,
            sha256: artifact.reference.digest.hexadecimalValue,
            byteCount: artifact.reference.byteCount,
            integrityStatus: artifact.integrity?.status.rawValue,
            integrityMessage: artifact.integrity?.message
        )
    }

    private func drilldownArtifactReference(
        path: String,
        role: String,
        source: String
    ) -> RunReviewInteractiveSignoffDrilldown.ArtifactSummary {
        RunReviewInteractiveSignoffDrilldown.ArtifactSummary(
            refID: path,
            source: source,
            role: role,
            artifactID: nil,
            stageID: nil,
            path: path,
            kind: "unknown",
            format: "unknown",
            sha256: nil,
            byteCount: nil,
            integrityStatus: nil,
            integrityMessage: nil
        )
    }

    private func drilldownDetailGroup(
        _ section: RunReviewSignoffDetailSection
    ) -> RunReviewInteractiveSignoffDrilldown.DetailGroup {
        RunReviewInteractiveSignoffDrilldown.DetailGroup(
            title: section.title,
            rows: section.rows.map(drilldownDetailRow)
        )
    }

    private func drilldownDetailRow(
        _ row: RunReviewSignoffDetailRow
    ) -> RunReviewInteractiveSignoffDrilldown.DetailRow {
        RunReviewInteractiveSignoffDrilldown.DetailRow(
            label: row.label,
            metrics: row.metrics.map(drilldownMetric)
        )
    }

    private func drilldownMetric(
        _ metric: RunReviewSignoffMetric
    ) -> RunReviewInteractiveSignoffDrilldown.Metric {
        RunReviewInteractiveSignoffDrilldown.Metric(
            label: metric.label,
            value: metric.value
        )
    }

    private func drilldownBucketGroup(
        title: String,
        buckets: [RunReviewDesignDiffBucket]
    ) -> RunReviewInteractiveSignoffDrilldown.DetailGroup {
        RunReviewInteractiveSignoffDrilldown.DetailGroup(
            title: title,
            rows: buckets.map { bucket in
                RunReviewInteractiveSignoffDrilldown.DetailRow(
                    label: bucket.label,
                    metrics: [
                        RunReviewInteractiveSignoffDrilldown.Metric(
                            label: "Count",
                            value: "\(bucket.count)"
                        ),
                    ]
                )
            }
        )
    }

    private func compactDrilldownMetrics(
        _ pairs: [(label: String, value: String?)]
    ) -> [RunReviewInteractiveSignoffDrilldown.Metric] {
        pairs.compactMap { pair in
            guard let value = pair.value, !value.isEmpty else {
                return nil
            }
            return RunReviewInteractiveSignoffDrilldown.Metric(label: pair.label, value: value)
        }
    }
}
