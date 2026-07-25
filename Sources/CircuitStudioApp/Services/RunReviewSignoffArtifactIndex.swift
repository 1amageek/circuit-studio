import DesignFlowKernel

struct RunReviewSignoffArtifactIndex {
    let indexedArtifactCount: Int

    private let relatedByKind: [SignoffArtifactKind: [FlowRunReviewArtifact]]
    private let stageResultsByStageID: [String: [FlowRunReviewArtifact]]

    init(artifacts: [FlowRunReviewArtifact]) {
        var relatedByKind: [SignoffArtifactKind: [FlowRunReviewArtifact]] = [:]
        var stageResultsByStageID: [String: [FlowRunReviewArtifact]] = [:]

        for artifact in artifacts {
            if artifact.purpose == .stageResult, let stageID = artifact.stageID {
                stageResultsByStageID[stageID, default: []].append(artifact)
            }

            let searchable = [
                artifact.reference.id.rawValue,
                artifact.purpose.rawValue,
                artifact.reference.locator.location.value,
                artifact.reference.locator.kind.rawValue,
                artifact.reference.locator.format.rawValue,
            ]
            .map { $0.lowercased() }
            .joined(separator: " ")

            for kind in SignoffArtifactKind.allCases where Self.matches(searchable, kind: kind) {
                relatedByKind[kind, default: []].append(artifact)
            }
        }

        self.indexedArtifactCount = artifacts.count
        self.relatedByKind = relatedByKind
        self.stageResultsByStageID = stageResultsByStageID
    }

    func relatedArtifacts(
        for artifact: FlowRunReviewArtifact,
        artifactKind: SignoffArtifactKind?
    ) -> [FlowRunReviewArtifact] {
        var candidates: [FlowRunReviewArtifact] = []
        if let stageID = artifact.stageID {
            candidates.append(contentsOf: stageResultsByStageID[stageID, default: []])
        }
        if let artifactKind {
            candidates.append(contentsOf: relatedByKind[artifactKind, default: []])
        }

        var seenPaths = Set<String>()
        return candidates
            .filter { candidate in
                let path = candidate.reference.locator.location.value
                return path != artifact.reference.locator.location.value
                    && seenPaths.insert(path).inserted
            }
            .sorted { left, right in
                if left.purpose != right.purpose {
                    return left.purpose.rawValue < right.purpose.rawValue
                }
                return left.reference.locator.location.value
                    < right.reference.locator.location.value
            }
    }

    private static func matches(_ searchable: String, kind: SignoffArtifactKind) -> Bool {
        switch kind {
        case .drc:
            searchable.contains("drc")
        case .lvs:
            searchable.contains("lvs")
        case .pex:
            searchable.contains("pex") || searchable.contains("spef")
        case .generatedLayoutSignoffCorpus:
            searchable.contains("generated-layout-signoff")
                || searchable.contains("oracle")
                || searchable.contains("corpus")
                || searchable.contains("retained-signoff")
        case .retainedSignoffReport:
            searchable.contains("retained-signoff")
                || searchable.contains("oracle")
                || searchable.contains("generated-layout-signoff")
        case .simulationMetric, .simulationMeasurement:
            searchable.contains("simulation")
                || searchable.contains("measurement")
                || searchable.contains("waveform")
        case .postLayoutComparison:
            searchable.contains("comparison")
                || searchable.contains("pre-layout")
                || searchable.contains("post-layout")
                || searchable.contains("waveform")
        case .signoffBundle:
            searchable.contains("signoff")
                || searchable.contains("evidence")
                || searchable.contains("qualification")
                || searchable.contains("waiver")
        case .releaseAuthorization:
            searchable.contains("authorization")
                || searchable.contains("approval")
                || searchable.contains("signoff")
        case .tapeoutResult, .foundryHandoff:
            searchable.contains("tapeout")
                || searchable.contains("handoff")
                || searchable.contains("stream")
                || searchable.contains("xor")
                || searchable.contains("authorization")
                || searchable.contains("signoff")
        }
    }
}

private extension SignoffArtifactKind {
    static let allCases: [SignoffArtifactKind] = [
        .drc,
        .lvs,
        .pex,
        .generatedLayoutSignoffCorpus,
        .retainedSignoffReport,
        .simulationMetric,
        .simulationMeasurement,
        .postLayoutComparison,
        .signoffBundle,
        .releaseAuthorization,
        .tapeoutResult,
        .foundryHandoff,
    ]
}
