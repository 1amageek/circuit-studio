import DesignFlowKernel
import Foundation
import XcircuitePackage

struct RunReviewArtifactEvaluationProjection: Sendable, Hashable {
    let evidence: [RunReviewArtifactEvaluationEvidence]
    let detailSections: [RunReviewSignoffDetailSection]
}

extension RunReviewService {
    func artifactEvaluationProjection(
        for artifact: FlowRunReviewArtifact,
        relatedArtifacts: [FlowRunReviewArtifact],
        projectRoot: URL,
        decodeIssues: inout [RunReviewArtifactDecodeIssue]
    ) -> RunReviewArtifactEvaluationProjection {
        var evidence: [RunReviewArtifactEvaluationEvidence] = []
        var sections: [RunReviewSignoffDetailSection] = []
        let envelopeArtifacts = relatedArtifacts.filter(isArtifactEvaluationEnvelope)

        for envelopeArtifact in envelopeArtifacts {
            do {
                let envelope = try loadArtifactEvaluationEnvelope(
                    envelopeArtifact,
                    projectRoot: projectRoot
                )
                guard artifactEvaluationEnvelope(envelope, references: artifact) else {
                    continue
                }
                evidence.append(
                    artifactEvaluationEvidence(
                        envelope: envelope,
                        envelopeArtifact: envelopeArtifact
                    )
                )
                sections.append(contentsOf: artifactEvaluationDetailSections(envelope))
            } catch {
                decodeIssues.append(
                    RunReviewArtifactDecodeIssue(
                        artifactRole: envelopeArtifact.role,
                        artifactPath: envelopeArtifact.path,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return RunReviewArtifactEvaluationProjection(
            evidence: evidence,
            detailSections: sections
        )
    }

    private func isArtifactEvaluationEnvelope(_ artifact: FlowRunReviewArtifact) -> Bool {
        guard artifact.format == .json else {
            return false
        }
        let searchable = [
            artifact.artifactID,
            artifact.role,
            artifact.path,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        return searchable.contains("envelope")
            || artifact.path.lowercased().contains("/evidence/")
    }

    private func loadArtifactEvaluationEnvelope(
        _ artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) throws -> XcircuiteArtifactEnvelope {
        try validateArtifactEvaluationEnvelopeIntegrity(artifact)
        let data = try Data(contentsOf: artifactEvaluationURL(for: artifact, projectRoot: projectRoot))
        let envelope = try JSONDecoder().decode(XcircuiteArtifactEnvelope.self, from: data)
        try XcircuiteArtifactEnvelopeValidator().validate(envelope)
        return envelope
    }

    private func validateArtifactEvaluationEnvelopeIntegrity(
        _ artifact: FlowRunReviewArtifact
    ) throws {
        guard let integrity = artifact.integrity else {
            throw RunReviewServiceError.artifactEvaluationEnvelopeIntegrityUnverified(
                path: artifact.path,
                status: "missing",
                message: "No recorded artifact integrity state is available."
            )
        }
        guard integrity.status == .verified else {
            throw RunReviewServiceError.artifactEvaluationEnvelopeIntegrityUnverified(
                path: artifact.path,
                status: integrity.status.rawValue,
                message: integrity.message
            )
        }
    }

    private func artifactEvaluationURL(
        for artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) -> URL {
        if artifact.path.hasPrefix("/") {
            return URL(filePath: artifact.path)
        }
        return projectRoot.appending(path: artifact.path)
    }

    private func artifactEvaluationEnvelope(
        _ envelope: XcircuiteArtifactEnvelope,
        references artifact: FlowRunReviewArtifact
    ) -> Bool {
        if envelope.reference.path == artifact.path {
            return true
        }
        guard let artifactID = artifact.artifactID else {
            return false
        }
        return envelope.artifactID == artifactID
            || envelope.reference.artifactID == artifactID
    }

    private func artifactEvaluationEvidence(
        envelope: XcircuiteArtifactEnvelope,
        envelopeArtifact: FlowRunReviewArtifact
    ) -> RunReviewArtifactEvaluationEvidence {
        let observationSet = envelope.observationSet
        let failedChannelIDs = observationSet?.channels
            .filter { $0.status == .failed }
            .map(\.channelID) ?? []
        return RunReviewArtifactEvaluationEvidence(
            envelopeArtifact: envelopeArtifact,
            artifactID: envelope.artifactID,
            role: envelope.role,
            evaluationStatus: envelope.evaluationResult?.status.rawValue,
            evaluationSummary: envelope.evaluationResult?.summary,
            observedChannelCount: observationSet?.observedChannelIDs.count ?? 0,
            missingChannelIDs: observationSet?.missingChannelIDs ?? [],
            uncalibratedChannelIDs: observationSet?.uncalibratedChannelIDs ?? [],
            failedChannelIDs: failedChannelIDs,
            feedbackSignals: envelope.evaluationResult?.feedbackSignals.map { signal in
                RunReviewArtifactEvaluationFeedbackSignal(
                    signalID: signal.signalID,
                    severity: signal.severity.rawValue,
                    routingLevel: signal.routingLevel.rawValue,
                    channelID: signal.channelID,
                    summary: signal.summary,
                    suggestedActions: signal.suggestedActions
                )
            } ?? []
        )
    }

    private func artifactEvaluationDetailSections(
        _ envelope: XcircuiteArtifactEnvelope
    ) -> [RunReviewSignoffDetailSection] {
        var sections: [RunReviewSignoffDetailSection] = []
        if let summarySection = artifactEvaluationSummarySection(envelope) {
            sections.append(summarySection)
        }
        if let criteriaSection = artifactEvaluationCriteriaSection(envelope.evaluationSpec) {
            sections.append(criteriaSection)
        }
        if let channelsSection = artifactEvaluationChannelsSection(envelope.observationSet) {
            sections.append(channelsSection)
        }
        if let feedbackSection = artifactEvaluationFeedbackSection(envelope.evaluationResult) {
            sections.append(feedbackSection)
        }
        return sections
    }

    private func artifactEvaluationSummarySection(
        _ envelope: XcircuiteArtifactEnvelope
    ) -> RunReviewSignoffDetailSection? {
        guard envelope.evaluationSpec != nil
            || envelope.observationSet != nil
            || envelope.evaluationResult != nil
        else {
            return nil
        }

        let observationSet = envelope.observationSet
        let evaluation = envelope.evaluationResult
        let failedChannelCount = observationSet?.channels.filter { $0.status == .failed }.count ?? 0
        let observedChannelCount = observationSet.map { String($0.observedChannelIDs.count) }
        let missingChannelCount = observationSet.map { String($0.missingChannelIDs.count) }
        let uncalibratedChannelCount = observationSet.map { String($0.uncalibratedChannelIDs.count) }
        let failedChannelCountValue = observationSet.map { _ in String(failedChannelCount) }
        let feedbackSignalCount = evaluation.map { String($0.feedbackSignals.count) }
        let likelihoodValue = evaluation?.likelihood.map(formatArtifactEvaluationNumber)
        let residualValue = evaluation?.residual.map(formatArtifactEvaluationNumber)
        let confidence = displayArtifactEvaluationConfidence(evaluation?.confidence ?? observationSet?.confidence)
        let metrics = compactArtifactEvaluationMetrics([
            ("Artifact", envelope.artifactID),
            ("Role", envelope.role),
            ("Status", evaluation?.status.rawValue),
            ("Spec", envelope.evaluationSpec?.specID),
            ("Observed", observedChannelCount),
            ("Missing", missingChannelCount),
            ("Uncalibrated", uncalibratedChannelCount),
            ("Failed", failedChannelCountValue),
            ("Feedback", feedbackSignalCount),
            ("Likelihood", likelihoodValue),
            ("Residual", residualValue),
            ("Confidence", confidence),
        ])

        var rows = [
            RunReviewSignoffDetailRow(
                label: "Evaluation",
                metrics: metrics
            ),
        ]
        if let summary = evaluation?.summary, !summary.isEmpty {
            rows.append(
                RunReviewSignoffDetailRow(
                    label: "Summary",
                    metrics: [
                        RunReviewSignoffMetric(label: "Text", value: summary),
                    ]
                )
            )
        }
        return RunReviewSignoffDetailSection(
            title: "Artifact Evaluation",
            rows: rows
        )
    }

    private func artifactEvaluationCriteriaSection(
        _ spec: XcircuiteEvaluationSpec?
    ) -> RunReviewSignoffDetailSection? {
        guard let spec, !spec.criteria.isEmpty else {
            return nil
        }
        let rows = spec.criteria.prefix(10).map { criterion in
            RunReviewSignoffDetailRow(
                label: criterion.criterionID,
                metrics: compactArtifactEvaluationMetrics([
                    ("Channel", criterion.channelID),
                    ("Comparator", criterion.comparator.rawValue),
                    ("Target", displayArtifactEvaluationValue(criterion.target)),
                    ("Tolerance", criterion.tolerance.map(formatArtifactEvaluationNumber)),
                    ("Required", criterion.required ? "true" : "false"),
                    ("Weight", formatArtifactEvaluationNumber(criterion.weight)),
                ])
            )
        }
        return RunReviewSignoffDetailSection(
            title: "Evaluation Criteria",
            rows: rows
        )
    }

    private func artifactEvaluationChannelsSection(
        _ observationSet: XcircuiteObservationSet?
    ) -> RunReviewSignoffDetailSection? {
        guard let observationSet, !observationSet.channels.isEmpty else {
            return nil
        }
        let rows = prioritizedArtifactEvaluationChannels(observationSet.channels)
            .prefix(12)
            .map { channel in
                RunReviewSignoffDetailRow(
                    label: channel.label ?? channel.channelID,
                    metrics: compactArtifactEvaluationMetrics([
                        ("ID", channel.channelID),
                        ("Status", channel.status.rawValue),
                        ("Value", displayArtifactEvaluationValue(channel.value)),
                        ("Unit", channel.unit),
                        ("Confidence", displayArtifactEvaluationConfidence(channel.confidence)),
                        ("Sources", joinedArtifactEvaluationValues(channel.sourceArtifactIDs)),
                    ])
                )
            }
        return RunReviewSignoffDetailSection(
            title: "Evaluation Channels",
            rows: rows
        )
    }

    private func artifactEvaluationFeedbackSection(
        _ evaluation: XcircuiteEvaluationResult?
    ) -> RunReviewSignoffDetailSection? {
        guard let evaluation, !evaluation.feedbackSignals.isEmpty else {
            return nil
        }
        let rows = evaluation.feedbackSignals.prefix(10).map { signal in
            RunReviewSignoffDetailRow(
                label: signal.signalID,
                metrics: compactArtifactEvaluationMetrics([
                    ("Severity", signal.severity.rawValue),
                    ("Routing", signal.routingLevel.rawValue),
                    ("Channel", signal.channelID),
                    ("Residual", signal.residual.map(formatArtifactEvaluationNumber)),
                    ("Actions", joinedArtifactEvaluationValues(signal.suggestedActions)),
                    ("Affected artifacts", joinedArtifactEvaluationValues(signal.affectedArtifactIDs)),
                    ("Affected paths", joinedArtifactEvaluationValues(signal.affectedPaths)),
                    ("Summary", signal.summary),
                ])
            )
        }
        return RunReviewSignoffDetailSection(
            title: "Feedback Signals",
            rows: rows
        )
    }

    private func prioritizedArtifactEvaluationChannels(
        _ channels: [XcircuiteObservationChannel]
    ) -> [XcircuiteObservationChannel] {
        channels.sorted { left, right in
            let leftRank = artifactEvaluationChannelRank(left.status)
            let rightRank = artifactEvaluationChannelRank(right.status)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return left.channelID < right.channelID
        }
    }

    private func artifactEvaluationChannelRank(
        _ status: XcircuiteObservationChannelStatus
    ) -> Int {
        switch status {
        case .failed:
            0
        case .missing:
            1
        case .uncalibrated:
            2
        case .observed:
            3
        case .derived:
            4
        }
    }

    private func compactArtifactEvaluationMetrics(
        _ pairs: [(label: String, value: String?)]
    ) -> [RunReviewSignoffMetric] {
        pairs.compactMap { pair in
            guard let value = pair.value, !value.isEmpty else {
                return nil
            }
            return RunReviewSignoffMetric(label: pair.label, value: value)
        }
    }

    private func displayArtifactEvaluationValue(
        _ value: XcircuiteJSONValue?
    ) -> String? {
        guard let value else {
            return nil
        }
        switch value {
        case .null:
            return "null"
        case .bool(let bool):
            return bool ? "true" : "false"
        case .number(let number):
            return formatArtifactEvaluationNumber(number)
        case .string(let string):
            return string
        case .array(let values):
            let renderedValues = values.prefix(4).compactMap(displayArtifactEvaluationValue)
            let suffix = values.count > renderedValues.count ? ", ..." : ""
            return "[\(renderedValues.joined(separator: ", "))\(suffix)]"
        case .object(let object):
            return "{\(object.keys.sorted().prefix(6).joined(separator: ", "))}"
        }
    }

    private func displayArtifactEvaluationConfidence(
        _ confidence: XcircuiteEvidenceConfidence?
    ) -> String? {
        guard let confidence else {
            return nil
        }
        var parts: [String] = []
        if let value = confidence.value {
            parts.append(formatArtifactEvaluationNumber(value))
        }
        parts.append(confidence.calibrated ? "calibrated" : "uncalibrated")
        if let variance = confidence.posteriorVariance {
            parts.append("var=\(formatArtifactEvaluationNumber(variance))")
        }
        if let coefficient = confidence.calibrationCoefficient {
            parts.append("coef=\(formatArtifactEvaluationNumber(coefficient))")
        }
        return parts.joined(separator: " ")
    }

    private func joinedArtifactEvaluationValues(_ values: [String]) -> String? {
        guard !values.isEmpty else {
            return nil
        }
        return values.prefix(6).joined(separator: ", ")
    }

    private func formatArtifactEvaluationNumber(_ value: Double) -> String {
        guard value.isFinite else {
            return "\(value)"
        }
        let rounded = value.rounded()
        if rounded == value && abs(value) < 9_000_000_000_000_000 {
            return "\(Int64(rounded))"
        }
        return String(format: "%.6g", value)
    }
}
