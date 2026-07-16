import CircuitStudioCore
import DesignFlowKernel
import Foundation
import LayoutCore

extension RunReviewService {
    private static let visualArtifactReadLimit = 16 * 1024 * 1024
    private static let netlistReadLimit = 2 * 1024 * 1024

    func designEvidenceSignature(bundle: FlowRunReviewBundle) -> String {
        bundle.artifacts
            .filter(isDesignEvidenceArtifact)
            .sorted { $0.path < $1.path }
            .map { artifact in
                [
                    artifact.path,
                    artifact.sha256 ?? "missing-digest",
                    artifact.byteCount.map(String.init) ?? "missing-size",
                    artifact.integrity?.status.rawValue ?? "missing-integrity",
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }

    func loadDesignEvidence(
        runID: String,
        bundle: FlowRunReviewBundle,
        projectRoot: URL
    ) async -> RunReviewDesignEvidence {
        let signature = designEvidenceSignature(bundle: bundle)
        let netlistArtifacts = bundle.artifacts
            .filter { $0.kind == .netlist && $0.format == .spice }
            .sorted(by: designPhaseOrder)
        let designSpecArtifact = bundle.artifacts
            .filter(isDesignSpecArtifact)
            .sorted { $0.path < $1.path }
            .first
        let layoutArtifact = bundle.artifacts
            .filter(isLayoutDocumentArtifact)
            .sorted { $0.path < $1.path }
            .first
        let waveformArtifacts = bundle.artifacts
            .filter { $0.kind == .waveform && $0.format == .csv }
            .sorted(by: designPhaseOrder)

        var issues: [RunReviewDesignEvidence.Issue] = []
        var netlists: [RunReviewDesignEvidence.NetlistEvidence] = []
        for artifact in netlistArtifacts {
            do {
                let data = try loadVerifiedArtifactData(
                    artifact,
                    projectRoot: projectRoot,
                    maxBytes: Self.netlistReadLimit
                )
                guard let text = String(data: data, encoding: .utf8) else {
                    throw RunReviewServiceError.artifactPreviewUnreadable(
                        path: artifact.path,
                        message: "SPICE artifact is not valid UTF-8."
                    )
                }
                netlists.append(RunReviewDesignEvidence.NetlistEvidence(
                    phase: designPhase(for: artifact),
                    text: text,
                    artifact: artifact
                ))
            } catch {
                issues.append(designEvidenceIssue(for: artifact, error: error))
            }
        }

        let schematicResult = await loadSchematicEvidence(
            runID: runID,
            netlists: netlists,
            designSpecArtifact: designSpecArtifact,
            projectRoot: projectRoot
        )
        issues.append(contentsOf: schematicResult.issues)
        let layout = loadLayoutEvidence(
            artifact: layoutArtifact,
            projectRoot: projectRoot,
            issues: &issues
        )
        let waveforms = await loadWaveformEvidence(
            runID: runID,
            artifacts: waveformArtifacts,
            projectRoot: projectRoot,
            issues: &issues
        )

        return RunReviewDesignEvidence(
            runID: runID,
            sourceSignature: signature,
            schematic: schematicResult.evidence,
            layout: layout,
            waveforms: waveforms,
            netlists: netlists,
            issues: issues
        )
    }

    private func loadSchematicEvidence(
        runID: String,
        netlists: [RunReviewDesignEvidence.NetlistEvidence],
        designSpecArtifact: FlowRunReviewArtifact?,
        projectRoot: URL
    ) async -> (
        evidence: RunReviewDesignEvidence.SchematicEvidence?,
        issues: [RunReviewDesignEvidence.Issue]
    ) {
        var issues: [RunReviewDesignEvidence.Issue] = []
        if let netlist = netlists.first(where: { $0.phase == .preLayout }) ?? netlists.first {
            do {
                let imported = try await SPICESchematicImporter().importTopLevel(
                    source: netlist.text,
                    fileName: URL(filePath: netlist.artifact.path).lastPathComponent,
                    topCellName: runID
                )
                guard let cell = imported.cells.first(where: { $0.name == imported.activeCellName })
                    ?? imported.cells.first else {
                    return (nil, issues)
                }
                return (
                    RunReviewDesignEvidence.SchematicEvidence(
                        document: cell.schematic,
                        artifact: netlist.artifact,
                        sourceKind: .spice
                    ),
                    issues
                )
            } catch {
                issues.append(designEvidenceIssue(for: netlist.artifact, error: error))
            }
        }

        guard let designSpecArtifact else {
            return (nil, issues)
        }
        do {
            let data = try loadVerifiedArtifactData(
                designSpecArtifact,
                projectRoot: projectRoot,
                maxBytes: Self.visualArtifactReadLimit
            )
            let spec = try JSONDecoder().decode(DesignFlowDesignSpec.self, from: data)
            return (
                RunReviewDesignEvidence.SchematicEvidence(
                    document: try spec.build().schematic,
                    artifact: designSpecArtifact,
                    sourceKind: .designSpec
                ),
                issues
            )
        } catch {
            issues.append(designEvidenceIssue(for: designSpecArtifact, error: error))
            return (nil, issues)
        }
    }

    private func loadLayoutEvidence(
        artifact: FlowRunReviewArtifact?,
        projectRoot: URL,
        issues: inout [RunReviewDesignEvidence.Issue]
    ) -> RunReviewDesignEvidence.LayoutEvidence? {
        guard let artifact else {
            return nil
        }
        do {
            let data = try loadVerifiedArtifactData(
                artifact,
                projectRoot: projectRoot,
                maxBytes: Self.visualArtifactReadLimit
            )
            return RunReviewDesignEvidence.LayoutEvidence(
                document: try JSONDecoder().decode(LayoutDocument.self, from: data),
                artifact: artifact
            )
        } catch {
            issues.append(designEvidenceIssue(for: artifact, error: error))
            return nil
        }
    }

    private func loadWaveformEvidence(
        runID: String,
        artifacts: [FlowRunReviewArtifact],
        projectRoot: URL,
        issues: inout [RunReviewDesignEvidence.Issue]
    ) async -> [RunReviewDesignEvidence.WaveformEvidence] {
        var evidence: [RunReviewDesignEvidence.WaveformEvidence] = []
        for artifact in artifacts {
            do {
                let maxBytes = min(
                    max(
                        Int(min(
                            artifact.byteCount ?? 0,
                            UInt64(Self.visualArtifactReadLimit)
                        )),
                        4096
                    ),
                    Self.visualArtifactReadLimit
                )
                let preview = try await loadArtifactPreview(
                    runID: runID,
                    artifact: artifact,
                    projectRoot: projectRoot,
                    maxBytes: maxBytes
                )
                guard let waveform = preview.waveformPreview else {
                    issues.append(RunReviewDesignEvidence.Issue(
                        artifactPath: artifact.path,
                        message: preview.parseIssue ?? "Waveform artifact could not be projected."
                    ))
                    continue
                }
                evidence.append(RunReviewDesignEvidence.WaveformEvidence(
                    phase: designPhase(for: artifact),
                    preview: waveform,
                    artifact: artifact
                ))
            } catch {
                issues.append(designEvidenceIssue(for: artifact, error: error))
            }
        }
        return evidence
    }

    private func isDesignEvidenceArtifact(_ artifact: FlowRunReviewArtifact) -> Bool {
        artifact.kind == .netlist
            || artifact.kind == .waveform
            || isDesignSpecArtifact(artifact)
            || isLayoutDocumentArtifact(artifact)
    }

    private func isDesignSpecArtifact(_ artifact: FlowRunReviewArtifact) -> Bool {
        guard artifact.format == .json else { return false }
        let identifier = artifact.artifactID?.lowercased() ?? ""
        let path = artifact.path.lowercased()
        return identifier == "design-spec"
            || identifier.hasPrefix("design-spec-")
            || path.hasSuffix("design-spec.json")
            || path.hasSuffix(".design.json")
    }

    private func isLayoutDocumentArtifact(_ artifact: FlowRunReviewArtifact) -> Bool {
        guard artifact.kind == .layout, artifact.format == .json else { return false }
        let identifier = artifact.artifactID?.lowercased() ?? ""
        let path = artifact.path.lowercased()
        return identifier == "layout-document"
            || identifier.hasPrefix("layout-document-")
            || path.hasSuffix("layout-document.json")
    }

    private func designPhaseOrder(
        _ left: FlowRunReviewArtifact,
        _ right: FlowRunReviewArtifact
    ) -> Bool {
        let leftRank = designPhaseRank(for: left)
        let rightRank = designPhaseRank(for: right)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return left.path < right.path
    }

    private func designPhaseRank(for artifact: FlowRunReviewArtifact) -> Int {
        switch designPhase(for: artifact) {
        case .preLayout: 0
        case .postLayout: 1
        case .other: 2
        }
    }

    private func designPhase(
        for artifact: FlowRunReviewArtifact
    ) -> RunReviewDesignEvidence.WaveformPhase {
        let searchable = "\(artifact.artifactID ?? "") \(artifact.role) \(artifact.path)".lowercased()
        if searchable.contains("pre-layout") || searchable.contains("prelayout") {
            return .preLayout
        }
        if searchable.contains("post-layout") || searchable.contains("postlayout") {
            return .postLayout
        }
        return .other
    }

    private func designEvidenceIssue(
        for artifact: FlowRunReviewArtifact,
        error: Error
    ) -> RunReviewDesignEvidence.Issue {
        RunReviewDesignEvidence.Issue(
            artifactPath: artifact.path,
            message: error.localizedDescription
        )
    }
}
