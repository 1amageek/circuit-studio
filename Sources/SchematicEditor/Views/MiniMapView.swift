import SwiftUI
import CircuitStudioCore

/// A miniature overview of the schematic, showing all content and the current viewport.
/// Click or drag on the minimap to navigate the main canvas.
///
/// The world rect shown always includes both the content bounds and the current viewport,
/// so the viewport rectangle never escapes the minimap edges.
struct MiniMapView: View {
    @Bindable var viewModel: SchematicViewModel

    private let miniMapSize = CGSize(width: 180, height: 120)
    private let padding: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let viewport = currentViewport
            let worldRect = computeWorldRect(viewport: viewport)
            let projection = MiniMapProjection(
                miniMapSize: size,
                worldRect: worldRect,
                padding: padding
            )

            let hasContent = !viewModel.document.components.isEmpty
                || !viewModel.document.wires.isEmpty
                || !viewModel.document.labels.isEmpty

            if hasContent {
                drawWires(in: &context, projection: projection)
                drawComponents(in: &context, projection: projection)
                drawLabels(in: &context, projection: projection)
            } else {
                drawEmptyCrosshair(in: &context, size: size)
            }

            drawViewport(in: &context, viewport: viewport, projection: projection)
        }
        .frame(width: miniMapSize.width, height: miniMapSize.height)
        .gesture(navigationGesture)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    // MARK: - World Rect

    /// The viewport rectangle in canvas (world) coordinates.
    private var currentViewport: CGRect {
        let canvasSize = viewModel.canvasSize
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 400, height: 300)
        }
        return CGRect(
            x: -viewModel.offset.x / viewModel.zoom,
            y: -viewModel.offset.y / viewModel.zoom,
            width: canvasSize.width / viewModel.zoom,
            height: canvasSize.height / viewModel.zoom
        )
    }

    /// Compute the world rect that the minimap displays: union of content bounds and viewport,
    /// expanded by 15% margin to provide breathing room.
    private func computeWorldRect(viewport: CGRect) -> CGRect {
        let base: CGRect
        if let contentBounds = viewModel.contentBounds() {
            base = contentBounds.union(viewport)
        } else {
            base = viewport
        }

        let marginX = base.width * 0.15
        let marginY = base.height * 0.15
        return base.insetBy(dx: -marginX, dy: -marginY)
    }

    // MARK: - Drawing: Wires

    private func drawWires(in context: inout GraphicsContext, projection: MiniMapProjection) {
        let lineWidth = 1.0 / projection.scale
        for wire in viewModel.document.wires {
            let selected = viewModel.document.selection.contains(wire.id)
            let start = projection.worldToMiniMap(wire.startPoint)
            let end = projection.worldToMiniMap(wire.endPoint)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            let color: Color = selected ? .accentColor : .green
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }

    // MARK: - Drawing: Components

    private func drawComponents(in context: inout GraphicsContext, projection: MiniMapProjection) {
        let strokeWidth = 1.0 / projection.scale
        for component in viewModel.document.components {
            let symbolSize = viewModel.catalog.device(for: component.deviceKindID)?.symbol.size
                ?? CGSize(width: 40, height: 40)
            let selected = viewModel.document.selection.contains(component.id)

            // Build oriented rectangle path: mirror → rotate → translate (matches SymbolRenderer)
            let rect = CGRect(
                x: -symbolSize.width / 2,
                y: -symbolSize.height / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            let worldTransform = CGAffineTransform.identity
                .scaledBy(x: component.mirrorY ? -1 : 1, y: component.mirrorX ? -1 : 1)
                .rotated(by: component.rotation * .pi / 180)
                .translatedBy(x: component.position.x, y: component.position.y)

            // Map the 4 corners through world transform → minimap projection
            let worldCorners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ].map { $0.applying(worldTransform) }

            let miniMapCorners = worldCorners.map { projection.worldToMiniMap($0) }

            var path = Path()
            path.move(to: miniMapCorners[0])
            for i in 1..<miniMapCorners.count {
                path.addLine(to: miniMapCorners[i])
            }
            path.closeSubpath()

            let fillColor: Color = selected ? .accentColor.opacity(0.4) : .primary.opacity(0.2)
            let borderColor: Color = selected ? .accentColor : .primary.opacity(0.5)
            context.fill(path, with: .color(fillColor))
            context.stroke(path, with: .color(borderColor), lineWidth: strokeWidth)
        }
    }

    // MARK: - Drawing: Labels

    private func drawLabels(in context: inout GraphicsContext, projection: MiniMapProjection) {
        let markerSize: CGFloat = 3.0
        for label in viewModel.document.labels {
            let center = projection.worldToMiniMap(label.position)
            // Diamond marker
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: center.y - markerSize))
            path.addLine(to: CGPoint(x: center.x + markerSize, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + markerSize))
            path.addLine(to: CGPoint(x: center.x - markerSize, y: center.y))
            path.closeSubpath()
            context.fill(path, with: .color(.orange))
        }
    }

    // MARK: - Drawing: Viewport

    private func drawViewport(
        in context: inout GraphicsContext,
        viewport: CGRect,
        projection: MiniMapProjection
    ) {
        let vpMinimap = projection.worldRectToMiniMap(viewport)
        context.fill(Path(vpMinimap), with: .color(.accentColor.opacity(0.1)))
        context.stroke(
            Path(vpMinimap),
            with: .color(.accentColor.opacity(0.7)),
            lineWidth: 1.5
        )
    }

    // MARK: - Drawing: Empty State

    private func drawEmptyCrosshair(in context: inout GraphicsContext, size: CGSize) {
        let cx = size.width / 2
        let cy = size.height / 2
        let armLength: CGFloat = 10

        var horizontal = Path()
        horizontal.move(to: CGPoint(x: cx - armLength, y: cy))
        horizontal.addLine(to: CGPoint(x: cx + armLength, y: cy))

        var vertical = Path()
        vertical.move(to: CGPoint(x: cx, y: cy - armLength))
        vertical.addLine(to: CGPoint(x: cx, y: cy + armLength))

        let color: Color = .primary.opacity(0.3)
        context.stroke(horizontal, with: .color(color), lineWidth: 1)
        context.stroke(vertical, with: .color(color), lineWidth: 1)
    }

    // MARK: - Navigation Gesture

    private var navigationGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                navigateTo(miniMapPoint: value.location)
            }
    }

    private func navigateTo(miniMapPoint: CGPoint) {
        let viewport = currentViewport
        let worldRect = computeWorldRect(viewport: viewport)
        let projection = MiniMapProjection(
            miniMapSize: miniMapSize,
            worldRect: worldRect,
            padding: padding
        )

        let worldPoint = projection.miniMapToWorld(miniMapPoint)
        let canvasSize = viewModel.canvasSize
        viewModel.offset = CGPoint(
            x: canvasSize.width / 2 - worldPoint.x * viewModel.zoom,
            y: canvasSize.height / 2 - worldPoint.y * viewModel.zoom
        )
    }
}

#Preview("MiniMap") {
    MiniMapView(viewModel: SchematicPreview.voltageDividerViewModel())
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
}
