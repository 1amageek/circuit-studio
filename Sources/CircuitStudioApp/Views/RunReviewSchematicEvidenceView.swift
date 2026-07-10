import CircuitStudioCore
import SchematicEditor
import SwiftUI

@MainActor
struct RunReviewSchematicEvidenceView: View {
    let evidence: RunReviewDesignEvidence.SchematicEvidence

    @State private var viewModel: SchematicViewModel
    @State private var panOrigin: CGPoint?
    @State private var magnificationOrigin: CGFloat?

    init(evidence: RunReviewDesignEvidence.SchematicEvidence) {
        self.evidence = evidence
        let viewModel = SchematicViewModel()
        viewModel.document = evidence.document
        viewModel.showsGrid = false
        viewModel.snapsToGrid = false
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack {
                    SchematicCanvas(viewModel: viewModel)
                        .allowsHitTesting(false)

                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(panGesture)
                        .simultaneousGesture(magnifyGesture)
                }
                .overlay(alignment: .topTrailing) {
                    zoomControls(canvasSize: geometry.size)
                        .padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    Text("\(evidence.document.components.count) components · \(netCount) nets")
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
                .onAppear {
                    viewModel.fitAll(canvasSize: geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    viewModel.fitAll(canvasSize: newSize)
                }
            }
            sourceLine
        }
    }

    private var netCount: Int {
        Set(evidence.document.wires.compactMap(\.netName)).count
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
                viewModel.zoom = min(max(magnificationOrigin * value.magnification, 0.1), 8)
            }
            .onEnded { _ in magnificationOrigin = nil }
    }

    private func zoomControls(canvasSize: CGSize) -> some View {
        HStack(spacing: 2) {
            Button {
                viewModel.zoom = max(viewModel.zoom / 1.25, 0.1)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out")

            Button {
                viewModel.fitAll(canvasSize: canvasSize)
            } label: {
                Image(systemName: "viewfinder")
            }
            .help("Fit circuit")

            Button {
                viewModel.zoom = min(viewModel.zoom * 1.25, 8)
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

    private var sourceLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
            Text(evidence.sourceKind.rawValue)
                .font(.caption2.weight(.semibold))
            Text(evidence.artifact.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
