import LayoutCore
import LayoutEditor
import LayoutTech
import SwiftUI

@MainActor
struct RunReviewLayoutEvidenceView: View {
    let evidence: RunReviewDesignEvidence.LayoutEvidence

    @State private var viewModel: LayoutEditorViewModel
    @State private var panOrigin: CGPoint?
    @State private var magnificationOrigin: CGFloat?

    init(evidence: RunReviewDesignEvidence.LayoutEvidence) {
        self.evidence = evidence
        let viewModel = LayoutEditorViewModel(
            document: evidence.document,
            tech: .standard()
        )
        viewModel.drdMode = .off
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                LayoutCanvasView(viewModel: viewModel)
                    .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .simultaneousGesture(magnifyGesture)
            }
            .overlay(alignment: .topTrailing) {
                zoomControls
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                Text("\(evidence.document.cells.count) cells · \(shapeCount) shapes · \(netCount) nets")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(8)
            }
            .onAppear { viewModel.fitAll() }

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text(evidence.artifact.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var shapeCount: Int {
        evidence.document.cells.reduce(0) { $0 + $1.shapes.count }
    }

    private var netCount: Int {
        evidence.document.cells.reduce(0) { $0 + $1.nets.count }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if panOrigin == nil {
                    panOrigin = viewModel.offset
                }
                guard let panOrigin else { return }
                viewModel.offset = CGPoint(
                    x: panOrigin.x + value.translation.width,
                    y: panOrigin.y + value.translation.height
                )
            }
            .onEnded { _ in panOrigin = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if magnificationOrigin == nil {
                    magnificationOrigin = viewModel.zoom
                }
                guard let magnificationOrigin else { return }
                viewModel.zoom = min(max(magnificationOrigin * value.magnification, 0.01), 100)
            }
            .onEnded { _ in magnificationOrigin = nil }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                viewModel.zoomOutStep()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")

            Button {
                viewModel.fitAll()
            } label: {
                Image(systemName: "viewfinder")
            }
            .help("Fit layout")

            Button {
                viewModel.zoomInStep()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
    }
}
