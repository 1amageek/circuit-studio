import CircuitStudioCore
import DesignFlowKernel
import Foundation
import LayoutCore

struct RunReviewDesignEvidence: Sendable {
    enum SchematicSourceKind: String, Sendable {
        case spice = "SPICE"
        case designSpec = "Design Spec"
    }

    enum WaveformPhase: String, Sendable, CaseIterable {
        case preLayout = "Pre-layout"
        case postLayout = "Post-layout"
        case other = "Waveform"
    }

    struct SchematicEvidence: Sendable {
        let document: SchematicDocument
        let artifact: FlowRunReviewArtifact
        let sourceKind: SchematicSourceKind
    }

    struct LayoutEvidence: Sendable {
        let document: LayoutDocument
        let artifact: FlowRunReviewArtifact
    }

    struct WaveformEvidence: Sendable, Hashable {
        let phase: WaveformPhase
        let preview: RunReviewWaveformPreview
        let artifact: FlowRunReviewArtifact
    }

    struct NetlistEvidence: Sendable, Hashable {
        let phase: WaveformPhase
        let text: String
        let artifact: FlowRunReviewArtifact
    }

    struct Issue: Sendable, Hashable {
        let artifactPath: String?
        let message: String
    }

    let runID: String
    let sourceSignature: String
    let schematic: SchematicEvidence?
    let layout: LayoutEvidence?
    let waveforms: [WaveformEvidence]
    let netlists: [NetlistEvidence]
    let issues: [Issue]

    var hasContent: Bool {
        schematic != nil || layout != nil || !waveforms.isEmpty || !netlists.isEmpty
    }
}
