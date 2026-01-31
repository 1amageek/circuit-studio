import SwiftUI
import CircuitStudioCore

/// Main schematic editor canvas with full gesture support.
public struct SchematicCanvas: View {
    @Bindable var viewModel: SchematicViewModel
    @State private var wireStart: CGPoint?
    @State private var wireEnd: CGPoint?
    @State private var dragMode: DragMode?
    @State private var panStartOffset: CGPoint?
    @State private var selectionRect: CGRect?
    @State private var selectionRectStart: CGPoint?
    @State private var selectionRectLeftToRight: Bool = true
    @State private var hoverPoint: CGPoint?

    /// Minimum screen-space movement to distinguish drag from tap.
    private let dragThreshold: CGFloat = 3

    public init(viewModel: SchematicViewModel) {
        self.viewModel = viewModel
    }

    /// Tracks what a drag gesture is doing once determined at the start.
    private enum DragMode {
        case movingComponent
        case panningCanvas
        case drawingWire
        case selectingRange
    }

    public var body: some View {
        Canvas { context, size in
            GridRenderer.render(
                in: &context,
                size: size,
                gridSize: viewModel.gridSize,
                zoom: viewModel.zoom,
                offset: viewModel.offset
            )

            context.translateBy(x: viewModel.offset.x, y: viewModel.offset.y)
            context.scaleBy(x: viewModel.zoom, y: viewModel.zoom)

            // Wires
            for wire in viewModel.document.wires {
                let selected = viewModel.document.selection.contains(wire.id)
                WireRenderer.render(wire, in: &context, selected: selected)
            }

            // Junctions
            for junction in viewModel.document.junctions {
                let selected = viewModel.document.selection.contains(junction.id)
                JunctionRenderer.render(junction, in: &context, selected: selected)
            }

            // In-progress wire (drag)
            if let start = wireStart, let end = wireEnd {
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(.green.opacity(0.5)), lineWidth: 1.5)
            }

            // Pending wire preview (two-click mode)
            if let start = viewModel.pendingWireStart, let hover = hoverPoint {
                let canvasHover = screenToCanvas(hover)
                let snapped = viewModel.snapToGrid(canvasHover)
                var path = Path()
                path.move(to: start)
                path.addLine(to: snapped)
                context.stroke(
                    path,
                    with: .color(.green.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )
                // Start point marker
                let markerRect = CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: markerRect), with: .color(.green))
            }

            // Components
            for component in viewModel.document.components {
                let selected = viewModel.document.selection.contains(component.id)
                if let kind = viewModel.catalog.device(for: component.deviceKindID) {
                    SymbolRenderer.render(
                        kind,
                        in: &context,
                        at: component.position,
                        rotation: component.rotation,
                        mirrorX: component.mirrorX,
                        mirrorY: component.mirrorY,
                        selected: selected
                    )
                }

                let label = Text(component.name).font(.caption)
                context.draw(
                    context.resolve(label),
                    at: CGPoint(x: component.position.x + 20, y: component.position.y),
                    anchor: .leading
                )
            }

            // Net labels
            for label in viewModel.document.labels {
                let text = Text(label.name).font(.caption2).bold()
                context.draw(context.resolve(text), at: label.position, anchor: .leading)
            }

            // Undo zoom/offset transform before drawing selection rect (screen space)
            context.scaleBy(x: 1 / viewModel.zoom, y: 1 / viewModel.zoom)
            context.translateBy(x: -viewModel.offset.x, y: -viewModel.offset.y)

            // Selection rectangle overlay (drawn in screen space)
            if let rect = selectionRect {
                let screenRect = canvasRectToScreen(rect)

                let fillColor: Color = selectionRectLeftToRight ? .accentColor : .green
                context.fill(Path(screenRect), with: .color(fillColor.opacity(0.1)))

                if selectionRectLeftToRight {
                    context.stroke(Path(screenRect), with: .color(fillColor.opacity(0.5)), lineWidth: 1)
                } else {
                    let dashStyle = StrokeStyle(lineWidth: 1, dash: [4, 4])
                    context.stroke(Path(screenRect), with: .color(fillColor.opacity(0.5)), style: dashStyle)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .background(GeometryReader { geo in
            Color.clear.onChange(of: geo.size, initial: true) { _, newSize in
                viewModel.canvasSize = newSize
            }
        })
        .gesture(unifiedDragGesture)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverPoint = location
            case .ended:
                hoverPoint = nil
            }
        }
        .background(scrollEventOverlay)
        .onKeyPress(phases: .down) { keyPress in
            handleKeyPress(keyPress)
        }
    }

    // MARK: - Translation helpers

    /// Whether the drag has moved far enough from its start to count as a real drag.
    private func isDrag(_ value: DragGesture.Value) -> Bool {
        let dx = value.translation.width
        let dy = value.translation.height
        return hypot(dx, dy) >= dragThreshold
    }

    // MARK: - Keyboard Handling

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let hasCmd = keyPress.modifiers.contains(.command)
        let hasShift = keyPress.modifiers.contains(.shift)

        if hasCmd {
            switch keyPress.characters.lowercased() {
            case "z":
                if hasShift {
                    viewModel.redo()
                } else {
                    viewModel.undo()
                }
                return .handled
            case "c":
                viewModel.copySelection()
                return .handled
            case "v":
                viewModel.recordForUndo()
                viewModel.paste(at: nil)
                return .handled
            case "x":
                viewModel.recordForUndo()
                viewModel.cutSelection()
                return .handled
            case "d":
                viewModel.recordForUndo()
                viewModel.duplicate()
                return .handled
            case "a":
                viewModel.selectAll()
                return .handled
            case "=", "+":
                let center = CGPoint(x: viewModel.canvasSize.width / 2, y: viewModel.canvasSize.height / 2)
                zoomToward(center, factor: 1.25)
                return .handled
            case "-":
                let center = CGPoint(x: viewModel.canvasSize.width / 2, y: viewModel.canvasSize.height / 2)
                zoomToward(center, factor: 0.8)
                return .handled
            case "0":
                viewModel.fitAll(canvasSize: viewModel.canvasSize)
                return .handled
            default:
                break
            }
        }

        // Non-modified keys
        switch keyPress.key {
        case .delete, .deleteForward:
            viewModel.recordForUndo()
            viewModel.deleteSelection()
            return .handled
        case .escape:
            viewModel.cancelPendingWire()
            viewModel.tool = .select
            viewModel.clearSelection()
            return .handled
        case .space:
            viewModel.fitAll(canvasSize: viewModel.canvasSize)
            return .handled
        default:
            break
        }

        // Character-based shortcuts (only without command modifier)
        guard !hasCmd else { return .ignored }

        switch keyPress.characters {
        case "r":
            viewModel.recordForUndo()
            viewModel.rotateSelection()
            return .handled
        case "x":
            viewModel.recordForUndo()
            viewModel.mirrorSelectionX()
            return .handled
        case "y":
            viewModel.recordForUndo()
            viewModel.mirrorSelectionY()
            return .handled
        case "w":
            viewModel.tool = .wire
            return .handled
        case "l":
            viewModel.tool = .label
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: - Unified Gesture

    /// A single `DragGesture(minimumDistance: 0)` that handles both taps and drags.
    /// Using separate `.onTapGesture` + `DragGesture(minimumDistance: 2)` causes
    /// gesture-recognition conflicts on macOS — the TapGesture can consume mouse
    /// events before the DragGesture fires.
    private var unifiedDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Ignore micro-movements until the user crosses the drag threshold.
                guard isDrag(value) else { return }

                switch viewModel.tool {
                case .select:
                    handleDragSelect(value: value)
                case .place:
                    break
                case .wire:
                    let canvasStart = screenToCanvas(value.startLocation)
                    let canvasCurrent = screenToCanvas(value.location)
                    handleDragWire(start: canvasStart, current: canvasCurrent)
                case .label:
                    break
                }
            }
            .onEnded { value in
                if isDrag(value) {
                    // Real drag — finish it normally.
                    switch viewModel.tool {
                    case .select:
                        finishDragSelect(value: value)
                    case .place:
                        break
                    case .wire:
                        finishDragWire(value: value)
                    case .label:
                        break
                    }
                } else {
                    // Short movement — treat as a tap.
                    handleTap(at: value.startLocation)
                    // Make sure any partially-started state is cleaned up.
                    resetDragState()
                }
            }
    }

    // MARK: - Scroll & Zoom

    private var scrollEventOverlay: some View {
        ScrollEventOverlay(
            onScroll: { deltaX, deltaY in
                viewModel.offset.x += deltaX
                viewModel.offset.y += deltaY
            },
            onZoom: { magnification, cursorLocation in
                zoomToward(cursorLocation, factor: 1 + magnification)
            }
        )
    }

    private func zoomToward(_ screenPoint: CGPoint, factor: CGFloat) {
        let oldZoom = viewModel.zoom
        let newZoom = max(0.1, min(10.0, oldZoom * factor))
        let scale = newZoom / oldZoom
        viewModel.offset = CGPoint(
            x: screenPoint.x - (screenPoint.x - viewModel.offset.x) * scale,
            y: screenPoint.y - (screenPoint.y - viewModel.offset.y) * scale
        )
        viewModel.zoom = newZoom
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        let canvasPoint = screenToCanvas(location)
        let shiftHeld = NSEvent.modifierFlags.contains(.shift)

        switch viewModel.tool {
        case .select:
            let hit = viewModel.hitTest(at: canvasPoint)
            switch hit {
            case .component(let id), .wire(let id), .label(let id), .junction(let id):
                if shiftHeld {
                    viewModel.toggleSelection(id)
                } else {
                    viewModel.select(id)
                }
            case .pin(let componentID, _):
                if shiftHeld {
                    viewModel.toggleSelection(componentID)
                } else {
                    viewModel.select(componentID)
                }
            case .none:
                if !shiftHeld {
                    viewModel.clearSelection()
                }
            }

        case .place(let deviceKindID):
            viewModel.recordForUndo()
            viewModel.placeComponent(deviceKindID: deviceKindID, at: canvasPoint)
            if let placed = viewModel.document.components.last {
                viewModel.select(placed.id)
            }
            viewModel.tool = .select

        case .wire:
            if let start = viewModel.pendingWireStart {
                let snappedEnd = viewModel.snapToGrid(canvasPoint)
                let dx = abs(snappedEnd.x - start.x)
                let dy = abs(snappedEnd.y - start.y)
                if dx > viewModel.gridSize || dy > viewModel.gridSize {
                    viewModel.recordForUndo()
                    viewModel.addWire(from: start, to: snappedEnd)
                }
                viewModel.pendingWireStart = nil
            } else {
                viewModel.pendingWireStart = viewModel.snapToGrid(canvasPoint)
            }

        case .label:
            viewModel.recordForUndo()
            viewModel.addLabel(name: "net", at: canvasPoint)
            if let placed = viewModel.document.labels.last {
                viewModel.select(placed.id)
            }
            viewModel.tool = .select
        }
    }

    // MARK: - Drag Select / Pan / Range Select

    private func handleDragSelect(value: DragGesture.Value) {
        if dragMode == nil {
            let canvasStart = screenToCanvas(value.startLocation)
            let hit = viewModel.hitTest(at: canvasStart)
            switch hit {
            case .component(let id), .wire(let id), .label(let id), .junction(let id):
                if !viewModel.document.selection.contains(id) {
                    viewModel.select(id)
                }
                dragMode = .movingComponent
            case .pin(let componentID, let portID):
                // Dragging from a pin starts wire drawing
                dragMode = .drawingWire
                if let component = viewModel.document.components.first(where: { $0.id == componentID }),
                   let kind = viewModel.catalog.device(for: component.deviceKindID),
                   let port = kind.portDefinitions.first(where: { $0.id == portID }) {
                    wireStart = viewModel.pinWorldPosition(port: port, component: component)
                } else {
                    wireStart = viewModel.snapToGrid(canvasStart)
                }
                wireEnd = wireStart
            case .none:
                if NSEvent.modifierFlags.contains(.option) {
                    dragMode = .panningCanvas
                    panStartOffset = viewModel.offset
                } else {
                    dragMode = .selectingRange
                    selectionRectStart = screenToCanvas(value.startLocation)
                }
            }
        }

        switch dragMode {
        case .movingComponent:
            viewModel.moveSelection(by: CGSize(
                width: value.translation.width / viewModel.zoom,
                height: value.translation.height / viewModel.zoom
            ))
        case .panningCanvas:
            if let startOffset = panStartOffset {
                viewModel.offset = CGPoint(
                    x: startOffset.x + value.translation.width,
                    y: startOffset.y + value.translation.height
                )
            }
        case .selectingRange:
            if let start = selectionRectStart {
                let current = screenToCanvas(value.location)
                selectionRectLeftToRight = current.x >= start.x
                selectionRect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(current.x - start.x),
                    height: abs(current.y - start.y)
                )
            }
        case .drawingWire:
            wireEnd = viewModel.snapToGrid(screenToCanvas(value.location))
        default:
            break
        }
    }

    private func finishDragSelect(value: DragGesture.Value) {
        if dragMode == .drawingWire, let start = wireStart {
            let snappedEnd = viewModel.snapToGrid(screenToCanvas(value.location))
            let dx = abs(snappedEnd.x - start.x)
            let dy = abs(snappedEnd.y - start.y)
            if dx > viewModel.gridSize || dy > viewModel.gridSize {
                viewModel.recordForUndo()
                viewModel.addWire(from: start, to: snappedEnd)
            }
            wireStart = nil
            wireEnd = nil
        } else if dragMode == .selectingRange, let rect = selectionRect, let start = selectionRectStart {
            let end = screenToCanvas(value.location)
            let enclosedOnly = end.x >= start.x  // left→right = enclosed only
            viewModel.selectInRect(rect, enclosedOnly: enclosedOnly)
        }

        viewModel.commitMove()
        resetDragState()
    }

    private func resetDragState() {
        dragMode = nil
        panStartOffset = nil
        selectionRect = nil
        selectionRectStart = nil
        selectionRectLeftToRight = true
    }

    // MARK: - Wire Drawing

    private func handleDragWire(start: CGPoint, current: CGPoint) {
        wireStart = viewModel.snapToGrid(start)
        wireEnd = viewModel.snapToGrid(current)
    }

    private func finishDragWire(value: DragGesture.Value) {
        let snappedStart = viewModel.snapToGrid(screenToCanvas(value.startLocation))
        let snappedEnd = viewModel.snapToGrid(screenToCanvas(value.location))
        let dx = abs(snappedEnd.x - snappedStart.x)
        let dy = abs(snappedEnd.y - snappedStart.y)
        if dx > viewModel.gridSize || dy > viewModel.gridSize {
            viewModel.recordForUndo()
            viewModel.addWire(from: snappedStart, to: snappedEnd)
        }
        wireStart = nil
        wireEnd = nil
    }

    // MARK: - Coordinate Conversion

    private func screenToCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - viewModel.offset.x) / viewModel.zoom,
            y: (point.y - viewModel.offset.y) / viewModel.zoom
        )
    }

    private func canvasRectToScreen(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * viewModel.zoom + viewModel.offset.x,
            y: rect.origin.y * viewModel.zoom + viewModel.offset.y,
            width: rect.width * viewModel.zoom,
            height: rect.height * viewModel.zoom
        )
    }
}

#Preview("Empty Canvas") {
    SchematicCanvas(viewModel: SchematicPreview.emptyViewModel())
        .frame(width: 600, height: 400)
}

#Preview("Voltage Divider") {
    SchematicCanvas(viewModel: SchematicPreview.voltageDividerViewModel())
        .frame(width: 600, height: 400)
}
