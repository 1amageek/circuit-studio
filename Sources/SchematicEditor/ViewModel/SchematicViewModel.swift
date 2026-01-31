import SwiftUI
import CircuitStudioCore

/// Editing tool mode.
public enum EditTool: Sendable {
    case select
    /// Place a device by its catalog ID.
    case place(String)
    case wire
    case label
    case probe
}

/// Result of hit-testing on the canvas.
public enum HitResult: Sendable {
    case component(UUID)
    case wire(UUID)
    case label(UUID)
    case junction(UUID)
    case pin(componentID: UUID, portID: String)
    case probe(UUID)
    case none
}

/// ViewModel for the schematic canvas.
@Observable
@MainActor
public final class SchematicViewModel {
    public var document: SchematicDocument = SchematicDocument()
    public let catalog: DeviceCatalog
    public var zoom: CGFloat = 1.0
    public var offset: CGPoint = .zero
    public var tool: EditTool = .select
    public var gridSize: CGFloat = 10
    public var canvasSize: CGSize = .zero

    /// First click point for two-click wire placement. nil = not started.
    public var pendingWireStart: CGPoint?

    /// First click PinReference for two-click differential probe. nil = not started.
    public var pendingDifferentialProbeStart: PinReference?

    /// Computed terminal objects, rebuilt when document structure changes.
    public var terminals: [Terminal] = []

    private var componentCounters: [String: Int] = [:]
    private var dragStartPositions: [UUID: CGPoint] = [:]
    private var wireEndOffsets: [UUID: CGSize] = [:]
    private var undoStack = UndoStack()
    private var clipboard: ClipboardContent?
    private var probeColorIndex: Int = 0

    public var diagnostics: [Diagnostic] = []

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }

    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }

    public init(catalog: DeviceCatalog = .standard()) {
        self.catalog = catalog
    }

    // MARK: - Validation

    public func validateDocument() {
        let service = DesignService(catalog: catalog)
        diagnostics = service.validate(document)
    }

    // MARK: - Component Name Generation

    public func nextComponentName(for deviceKindID: String) -> String {
        let prefix = catalog.device(for: deviceKindID)?.spicePrefix ?? "X"
        let count = (componentCounters[prefix] ?? 0) + 1
        componentCounters[prefix] = count
        return "\(prefix)\(count)"
    }

    // MARK: - Hit Testing

    public func hitTest(at point: CGPoint) -> HitResult {
        // Check pins first (more specific)
        for component in document.components {
            guard let kind = catalog.device(for: component.deviceKindID) else { continue }
            for port in kind.portDefinitions {
                let pinWorld = pinWorldPosition(port: port, component: component)
                let dist = hypot(point.x - pinWorld.x, point.y - pinWorld.y)
                if dist < gridSize * 0.8 {
                    return .pin(componentID: component.id, portID: port.id)
                }
            }
        }

        // Check probes (icon positioned near terminal)
        for probe in document.probes {
            if let pos = probeIconPosition(for: probe) {
                let dist = hypot(point.x - pos.x, point.y - pos.y)
                if dist < gridSize * 1.0 {
                    return .probe(probe.id)
                }
            }
        }

        // Check components
        let hitRadius: CGFloat = 20
        for component in document.components {
            let dx = point.x - component.position.x
            let dy = point.y - component.position.y
            if abs(dx) < hitRadius, abs(dy) < hitRadius * 2 {
                return .component(component.id)
            }
        }

        // Check wires
        for wire in document.wires {
            if distanceToSegment(point: point, start: wire.startPoint, end: wire.endPoint) < 5 {
                return .wire(wire.id)
            }
        }

        // Check junctions
        for junction in document.junctions {
            let dist = hypot(point.x - junction.position.x, point.y - junction.position.y)
            if dist < gridSize * 0.5 {
                return .junction(junction.id)
            }
        }

        // Check labels
        for label in document.labels {
            let dx = point.x - label.position.x
            let dy = point.y - label.position.y
            if abs(dx) < 30, abs(dy) < 10 {
                return .label(label.id)
            }
        }

        return .none
    }

    // MARK: - Selection

    public func select(_ id: UUID) {
        document.selection = [id]
    }

    public func clearSelection() {
        document.selection.removeAll()
    }

    /// Cancel an in-progress two-click wire placement.
    public func cancelPendingWire() {
        pendingWireStart = nil
    }

    /// Cancel an in-progress differential probe placement.
    public func cancelPendingProbe() {
        pendingDifferentialProbeStart = nil
    }

    /// Toggle membership of an id in the selection set (Shift+click).
    public func toggleSelection(_ id: UUID) {
        if document.selection.contains(id) {
            document.selection.remove(id)
        } else {
            document.selection.insert(id)
        }
    }

    /// Select every component, wire, label, junction, and probe.
    public func selectAll() {
        var ids = Set<UUID>()
        for c in document.components { ids.insert(c.id) }
        for w in document.wires { ids.insert(w.id) }
        for l in document.labels { ids.insert(l.id) }
        for j in document.junctions { ids.insert(j.id) }
        for p in document.probes { ids.insert(p.id) }
        document.selection = ids
    }

    /// Select objects inside or touching a rectangle.
    ///
    /// - Parameter enclosedOnly: When `true`, only objects fully inside the rect
    ///   are selected. When `false`, objects that merely intersect are included.
    public func selectInRect(_ rect: CGRect, enclosedOnly: Bool) {
        var ids = Set<UUID>()

        for component in document.components {
            guard let kind = catalog.device(for: component.deviceKindID) else { continue }
            let symbolSize = kind.symbol.size
            let componentRect = CGRect(
                x: component.position.x - symbolSize.width / 2,
                y: component.position.y - symbolSize.height / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            if enclosedOnly {
                if rect.contains(componentRect) { ids.insert(component.id) }
            } else {
                if rect.intersects(componentRect) { ids.insert(component.id) }
            }
        }

        for wire in document.wires {
            // Ensure at least 1pt in each dimension so intersects works for axis-aligned wires
            let w = max(abs(wire.endPoint.x - wire.startPoint.x), 1)
            let h = max(abs(wire.endPoint.y - wire.startPoint.y), 1)
            let wireRect = CGRect(
                x: min(wire.startPoint.x, wire.endPoint.x),
                y: min(wire.startPoint.y, wire.endPoint.y),
                width: w,
                height: h
            )
            if enclosedOnly {
                if rect.contains(wireRect) { ids.insert(wire.id) }
            } else {
                if rect.intersects(wireRect) { ids.insert(wire.id) }
            }
        }

        for label in document.labels {
            let labelRect = CGRect(
                x: label.position.x - 30,
                y: label.position.y - 10,
                width: 60,
                height: 20
            )
            if enclosedOnly {
                if rect.contains(labelRect) { ids.insert(label.id) }
            } else {
                if rect.intersects(labelRect) { ids.insert(label.id) }
            }
        }

        for junction in document.junctions {
            if rect.contains(junction.position) { ids.insert(junction.id) }
        }

        document.selection = ids
    }

    // MARK: - Undo / Redo

    /// Record the current document state before mutating it.
    /// Callers (canvas key handlers, gesture handlers) invoke this **before** performing the action.
    public func recordForUndo() {
        undoStack.record(document)
    }

    public func undo() {
        if let previous = undoStack.undo(current: document) {
            document = previous
        }
    }

    public func redo() {
        if let next = undoStack.redo(current: document) {
            document = next
        }
    }

    // MARK: - Copy / Paste

    public func copySelection() {
        let selectedIDs = document.selection
        guard !selectedIDs.isEmpty else { return }

        let components = document.components.filter { selectedIDs.contains($0.id) }
        let wires = document.wires.filter { selectedIDs.contains($0.id) }
        let labels = document.labels.filter { selectedIDs.contains($0.id) }
        let probes = document.probes.filter { selectedIDs.contains($0.id) }

        let anchor = selectionCenter(components: components, wires: wires, labels: labels)

        clipboard = ClipboardContent(
            components: components,
            wires: wires,
            labels: labels,
            probes: probes,
            anchorPoint: anchor
        )
    }

    /// Paste clipboard contents at the given canvas point (or with a small offset from the anchor).
    public func paste(at point: CGPoint?) {
        guard let clip = clipboard else { return }

        let target = point ?? CGPoint(
            x: clip.anchorPoint.x + 20,
            y: clip.anchorPoint.y + 20
        )
        let dx = target.x - clip.anchorPoint.x
        let dy = target.y - clip.anchorPoint.y

        // Build ID remap for components
        var idMap: [UUID: UUID] = [:]
        var newComponents: [PlacedComponent] = []
        for var comp in clip.components {
            let newID = UUID()
            idMap[comp.id] = newID
            comp = PlacedComponent(
                id: newID,
                deviceKindID: comp.deviceKindID,
                name: nextComponentName(for: comp.deviceKindID),
                position: CGPoint(x: comp.position.x + dx, y: comp.position.y + dy),
                rotation: comp.rotation,
                mirrorX: comp.mirrorX,
                mirrorY: comp.mirrorY,
                parameters: comp.parameters
            )
            newComponents.append(comp)
        }

        var newWires: [Wire] = []
        for wire in clip.wires {
            let remappedStartPin: PinReference? = wire.startPin.map {
                PinReference(componentID: idMap[$0.componentID] ?? $0.componentID, portID: $0.portID)
            }
            let remappedEndPin: PinReference? = wire.endPin.map {
                PinReference(componentID: idMap[$0.componentID] ?? $0.componentID, portID: $0.portID)
            }
            let newWire = Wire(
                startPoint: CGPoint(x: wire.startPoint.x + dx, y: wire.startPoint.y + dy),
                endPoint: CGPoint(x: wire.endPoint.x + dx, y: wire.endPoint.y + dy),
                startPin: remappedStartPin,
                endPin: remappedEndPin,
                netName: wire.netName
            )
            newWires.append(newWire)
        }

        var newLabels: [NetLabel] = []
        for label in clip.labels {
            let newLabel = NetLabel(
                name: label.name,
                position: CGPoint(x: label.position.x + dx, y: label.position.y + dy)
            )
            newLabels.append(newLabel)
        }

        // Remap probe PinReferences to new component IDs
        var newProbes: [Probe] = []
        for probe in clip.probes {
            let remappedType: ProbeType
            switch probe.probeType {
            case .voltage(let ref):
                remappedType = .voltage(remapPinReference(ref, idMap: idMap))
            case .differential(let pos, let neg):
                remappedType = .differential(
                    positive: remapPinReference(pos, idMap: idMap),
                    negative: remapPinReference(neg, idMap: idMap)
                )
            case .current(let ref):
                remappedType = .current(remapPinReference(ref, idMap: idMap))
            }
            let newProbe = Probe(
                label: probe.label,
                probeType: remappedType,
                color: probe.color,
                isEnabled: probe.isEnabled
            )
            newProbes.append(newProbe)
        }

        document.components.append(contentsOf: newComponents)
        document.wires.append(contentsOf: newWires)
        document.labels.append(contentsOf: newLabels)
        document.probes.append(contentsOf: newProbes)

        // Select newly pasted objects
        var newSelection = Set<UUID>()
        for c in newComponents { newSelection.insert(c.id) }
        for w in newWires { newSelection.insert(w.id) }
        for l in newLabels { newSelection.insert(l.id) }
        for p in newProbes { newSelection.insert(p.id) }
        document.selection = newSelection
        recomputeJunctions()
    }

    public func cutSelection() {
        copySelection()
        deleteSelection()
    }

    public func duplicate() {
        copySelection()
        paste(at: nil)
    }

    // MARK: - Mirror

    public func mirrorSelectionX() {
        for id in document.selection {
            if let idx = document.components.firstIndex(where: { $0.id == id }) {
                document.components[idx].mirrorX.toggle()
                updateConnectedWiresAfterTransform(componentIndex: idx)
            }
        }
    }

    public func mirrorSelectionY() {
        for id in document.selection {
            if let idx = document.components.firstIndex(where: { $0.id == id }) {
                document.components[idx].mirrorY.toggle()
                updateConnectedWiresAfterTransform(componentIndex: idx)
            }
        }
    }

    // MARK: - Navigation

    /// Bounding rect of all content (components, wires, labels) in canvas coordinates.
    /// Returns `nil` when the document is empty.
    public func contentBounds() -> CGRect? {
        guard !document.components.isEmpty || !document.wires.isEmpty || !document.labels.isEmpty else {
            return nil
        }

        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity

        for comp in document.components {
            let size = catalog.device(for: comp.deviceKindID)?.symbol.size ?? CGSize(width: 40, height: 40)
            let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
            let transform = CGAffineTransform.identity
                .scaledBy(x: comp.mirrorY ? -1 : 1, y: comp.mirrorX ? -1 : 1)
                .rotated(by: comp.rotation * .pi / 180)
                .translatedBy(x: comp.position.x, y: comp.position.y)
            let corners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ].map { $0.applying(transform) }
            for corner in corners {
                minX = min(minX, corner.x)
                minY = min(minY, corner.y)
                maxX = max(maxX, corner.x)
                maxY = max(maxY, corner.y)
            }
        }
        for wire in document.wires {
            minX = min(minX, min(wire.startPoint.x, wire.endPoint.x))
            minY = min(minY, min(wire.startPoint.y, wire.endPoint.y))
            maxX = max(maxX, max(wire.startPoint.x, wire.endPoint.x))
            maxY = max(maxY, max(wire.startPoint.y, wire.endPoint.y))
        }
        for label in document.labels {
            minX = min(minX, label.position.x - 30)
            minY = min(minY, label.position.y - 10)
            maxX = max(maxX, label.position.x + 30)
            maxY = max(maxY, label.position.y + 10)
        }

        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0 else { return nil }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    public func fitAll(canvasSize: CGSize) {
        guard let bounds = contentBounds() else { return }

        let margin: CGFloat = 40
        let availableWidth = canvasSize.width - margin * 2
        let availableHeight = canvasSize.height - margin * 2
        guard availableWidth > 0, availableHeight > 0 else { return }

        let scaleX = availableWidth / bounds.width
        let scaleY = availableHeight / bounds.height
        let newZoom = max(0.1, min(10.0, min(scaleX, scaleY)))

        let centerX = bounds.midX
        let centerY = bounds.midY
        offset = CGPoint(
            x: canvasSize.width / 2 - centerX * newZoom,
            y: canvasSize.height / 2 - centerY * newZoom
        )
        zoom = newZoom
    }

    // MARK: - Placement

    public func placeComponent(deviceKindID: String, at point: CGPoint) {
        let snapped = snapToGrid(point)
        let name = nextComponentName(for: deviceKindID)

        // Populate default parameter values from catalog
        var defaults: [String: Double] = [:]
        if let kind = catalog.device(for: deviceKindID) {
            for schema in kind.parameterSchema {
                if let value = schema.defaultValue {
                    defaults[schema.id] = value
                }
            }
        }

        let placed = PlacedComponent(
            deviceKindID: deviceKindID,
            name: name,
            position: snapped,
            parameters: defaults
        )
        document.components.append(placed)
    }

    public func addWire(from start: CGPoint, to end: CGPoint) {
        let snappedStart = snapToGrid(start)
        let snappedEnd = snapToGrid(end)
        let (startPinSnapped, startRef) = snapToPin(at: snappedStart)
        let (endPinSnapped, endRef) = snapToPin(at: snappedEnd)

        let wire = Wire(
            startPoint: startPinSnapped,
            endPoint: endPinSnapped,
            startPin: startRef,
            endPin: endRef
        )
        document.wires.append(wire)
        recomputeJunctions()
    }

    public func addLabel(name: String, at point: CGPoint) {
        let label = NetLabel(
            name: name,
            position: snapToGrid(point)
        )
        document.labels.append(label)
    }

    // MARK: - Pin Snapping

    /// Snaps a point to the nearest pin within threshold, returning the snapped position and pin reference.
    public func snapToPin(at point: CGPoint) -> (CGPoint, PinReference?) {
        let threshold = gridSize * 1.5
        var bestDist = threshold
        var bestPoint = point
        var bestRef: PinReference?

        for component in document.components {
            guard let kind = catalog.device(for: component.deviceKindID) else { continue }
            for port in kind.portDefinitions {
                let pinWorld = pinWorldPosition(port: port, component: component)
                let dist = hypot(point.x - pinWorld.x, point.y - pinWorld.y)
                if dist < bestDist {
                    bestDist = dist
                    bestPoint = pinWorld
                    bestRef = PinReference(componentID: component.id, portID: port.id)
                }
            }
        }

        return (bestRef != nil ? bestPoint : point, bestRef)
    }

    /// Compute the world-space position of a port on a placed component.
    /// Applies mirror before rotation: mirror → rotate → translate.
    public func pinWorldPosition(port: PortDefinition, component: PlacedComponent) -> CGPoint {
        var p = port.position
        if component.mirrorY { p.x = -p.x }
        if component.mirrorX { p.y = -p.y }
        let rotated = rotatePoint(p, by: component.rotation * .pi / 180, around: .zero)
        return CGPoint(
            x: component.position.x + rotated.x,
            y: component.position.y + rotated.y
        )
    }

    // MARK: - Move with Rubber Banding

    public func moveSelection(by delta: CGSize) {
        // Record undo on the first drag frame
        if dragStartPositions.isEmpty {
            recordForUndo()
        }

        for id in document.selection {
            if let idx = document.components.firstIndex(where: { $0.id == id }) {
                if dragStartPositions[id] == nil {
                    dragStartPositions[id] = document.components[idx].position
                }
                if let startPos = dragStartPositions[id] {
                    let newPos = CGPoint(
                        x: startPos.x + delta.width,
                        y: startPos.y + delta.height
                    )
                    let snapped = snapToGrid(newPos)
                    let oldPos = document.components[idx].position
                    document.components[idx].position = snapped

                    // Rubber banding: update connected wire endpoints
                    let moveDelta = CGSize(
                        width: snapped.x - oldPos.x,
                        height: snapped.y - oldPos.y
                    )
                    updateConnectedWires(componentID: document.components[idx].id, delta: moveDelta)
                }
            } else if let idx = document.wires.firstIndex(where: { $0.id == id }) {
                if dragStartPositions[id] == nil {
                    dragStartPositions[id] = document.wires[idx].startPoint
                    let wire = document.wires[idx]
                    wireEndOffsets[id] = CGSize(
                        width: wire.endPoint.x - wire.startPoint.x,
                        height: wire.endPoint.y - wire.startPoint.y
                    )
                }
                if let startPos = dragStartPositions[id], let endOffset = wireEndOffsets[id] {
                    let newStart = snapToGrid(CGPoint(
                        x: startPos.x + delta.width,
                        y: startPos.y + delta.height
                    ))
                    document.wires[idx].startPoint = newStart
                    document.wires[idx].endPoint = snapToGrid(CGPoint(
                        x: newStart.x + endOffset.width,
                        y: newStart.y + endOffset.height
                    ))
                }
            } else if let idx = document.labels.firstIndex(where: { $0.id == id }) {
                if dragStartPositions[id] == nil {
                    dragStartPositions[id] = document.labels[idx].position
                }
                if let startPos = dragStartPositions[id] {
                    let newPos = CGPoint(
                        x: startPos.x + delta.width,
                        y: startPos.y + delta.height
                    )
                    document.labels[idx].position = snapToGrid(newPos)
                }
            }
        }
    }

    /// Update wire endpoints connected to a moved component.
    private func updateConnectedWires(componentID: UUID, delta: CGSize) {
        guard let component = document.components.first(where: { $0.id == componentID }),
              let kind = catalog.device(for: component.deviceKindID) else { return }

        for i in document.wires.indices {
            // Skip wires that are themselves selected (they move independently)
            guard !document.selection.contains(document.wires[i].id) else { continue }

            if document.wires[i].startPin?.componentID == componentID {
                if let portID = document.wires[i].startPin?.portID,
                   let port = kind.portDefinitions.first(where: { $0.id == portID }) {
                    document.wires[i].startPoint = pinWorldPosition(port: port, component: component)
                }
            }
            if document.wires[i].endPin?.componentID == componentID {
                if let portID = document.wires[i].endPin?.portID,
                   let port = kind.portDefinitions.first(where: { $0.id == portID }) {
                    document.wires[i].endPoint = pinWorldPosition(port: port, component: component)
                }
            }
        }
    }

    /// Update all wire endpoints connected to the component at the given index.
    /// Call after changing rotation or mirror on a component.
    public func updateConnectedWires(forComponentAt componentIndex: Int) {
        updateConnectedWiresAfterTransform(componentIndex: componentIndex)
    }

    /// Shared helper: after rotating or mirroring a component, update all connected wire endpoints.
    private func updateConnectedWiresAfterTransform(componentIndex: Int) {
        let component = document.components[componentIndex]
        guard let kind = catalog.device(for: component.deviceKindID) else { return }
        for i in document.wires.indices {
            if let startRef = document.wires[i].startPin,
               startRef.componentID == component.id,
               let port = kind.portDefinitions.first(where: { $0.id == startRef.portID }) {
                document.wires[i].startPoint = pinWorldPosition(port: port, component: component)
            }
            if let endRef = document.wires[i].endPin,
               endRef.componentID == component.id,
               let port = kind.portDefinitions.first(where: { $0.id == endRef.portID }) {
                document.wires[i].endPoint = pinWorldPosition(port: port, component: component)
            }
        }
    }

    public func commitMove() {
        dragStartPositions.removeAll()
        wireEndOffsets.removeAll()
    }

    // MARK: - Delete

    public func deleteSelection() {
        let selected = document.selection
        guard !selected.isEmpty else { return }

        // Collect IDs of components being deleted for probe cleanup
        let deletedComponentIDs = Set(
            document.components.filter { selected.contains($0.id) }.map(\.id)
        )

        document.components.removeAll { selected.contains($0.id) }
        document.wires.removeAll { selected.contains($0.id) }
        document.labels.removeAll { selected.contains($0.id) }
        document.junctions.removeAll { selected.contains($0.id) }
        // Remove selected probes and probes referencing deleted components
        document.probes.removeAll { probe in
            selected.contains(probe.id) || probeReferencesAny(probe, componentIDs: deletedComponentIDs)
        }
        document.selection.removeAll()
        recomputeJunctions()
    }

    // MARK: - Rotate

    public func rotateSelection() {
        for id in document.selection {
            if let idx = document.components.firstIndex(where: { $0.id == id }) {
                document.components[idx].rotation += 90
                updateConnectedWiresAfterTransform(componentIndex: idx)
            }
        }
    }

    // MARK: - Terminal Computation

    /// Recompute terminals from current document state.
    public func recomputeTerminals() {
        let extractor = NetExtractor()
        let nets = extractor.extract(from: document)
        let probedPins = buildProbedPinSet()

        // Build pin-to-net map
        var pinNetMap: [String: String] = [:]
        for net in nets {
            for conn in net.connections {
                pinNetMap["\(conn.componentID):\(conn.portID)"] = net.name
            }
        }

        var result: [Terminal] = []

        for component in document.components {
            guard let kind = catalog.device(for: component.deviceKindID) else { continue }

            for (index, port) in kind.portDefinitions.enumerated() {
                let pinRef = PinReference(componentID: component.id, portID: port.id)
                let key = "\(component.id):\(port.id)"
                let netName = pinNetMap[key]

                let connectionState: TerminalConnectionState
                if let net = netName {
                    if probedPins.contains(key) {
                        connectionState = .probed(netName: net)
                    } else {
                        connectionState = .connected(netName: net)
                    }
                } else {
                    connectionState = .unconnected
                }

                let worldPos = pinWorldPosition(port: port, component: component)

                result.append(Terminal(
                    pinReference: pinRef,
                    displayName: port.displayName,
                    portIndex: index,
                    worldPosition: worldPos,
                    netName: netName,
                    connectionState: connectionState,
                    componentName: component.name,
                    spicePrefix: kind.spicePrefix
                ))
            }
        }

        terminals = result
    }

    private func buildProbedPinSet() -> Set<String> {
        var set = Set<String>()
        for probe in document.probes where probe.isEnabled {
            switch probe.probeType {
            case .voltage(let ref):
                set.insert("\(ref.componentID):\(ref.portID)")
            case .differential(let pos, let neg):
                set.insert("\(pos.componentID):\(pos.portID)")
                set.insert("\(neg.componentID):\(neg.portID)")
            case .current(let ref):
                set.insert("\(ref.componentID):\(ref.portID)")
            }
        }
        return set
    }

    // MARK: - Probe Management

    /// Place a voltage probe at a terminal.
    public func addVoltageProbe(at pinRef: PinReference) {
        let terminal = terminals.first { $0.pinReference == pinRef }
        let label = terminal.map { "V(\($0.componentName).\($0.displayName))" }
            ?? "V(probe)"
        let probe = Probe(
            label: label,
            probeType: .voltage(pinRef),
            color: nextProbeColor()
        )
        document.probes.append(probe)
        recomputeTerminals()
    }

    /// Place a current probe at a terminal.
    public func addCurrentProbe(at pinRef: PinReference) {
        let terminal = terminals.first { $0.pinReference == pinRef }
        let label = terminal.map { "I(\($0.componentName))" }
            ?? "I(probe)"
        let probe = Probe(
            label: label,
            probeType: .current(pinRef),
            color: nextProbeColor()
        )
        document.probes.append(probe)
        recomputeTerminals()
    }

    /// Place a differential voltage probe between two terminals.
    public func addDifferentialProbe(positive: PinReference, negative: PinReference) {
        let posTerminal = terminals.first { $0.pinReference == positive }
        let negTerminal = terminals.first { $0.pinReference == negative }
        let label: String
        if let p = posTerminal, let n = negTerminal {
            label = "V(\(p.componentName).\(p.displayName), \(n.componentName).\(n.displayName))"
        } else {
            label = "V(diff)"
        }
        let probe = Probe(
            label: label,
            probeType: .differential(positive: positive, negative: negative),
            color: nextProbeColor()
        )
        document.probes.append(probe)
        recomputeTerminals()
    }

    /// Remove a probe by ID.
    public func removeProbe(_ probeID: UUID) {
        document.probes.removeAll { $0.id == probeID }
        recomputeTerminals()
    }

    /// Toggle a probe's enabled state.
    public func toggleProbe(_ probeID: UUID) {
        if let idx = document.probes.firstIndex(where: { $0.id == probeID }) {
            document.probes[idx].isEnabled.toggle()
            recomputeTerminals()
        }
    }

    /// World position of a probe icon, offset from its target terminal.
    public func probeIconPosition(for probe: Probe) -> CGPoint? {
        let targetRef: PinReference
        switch probe.probeType {
        case .voltage(let ref): targetRef = ref
        case .current(let ref): targetRef = ref
        case .differential(let pos, _): targetRef = pos
        }
        guard let terminal = terminals.first(where: { $0.pinReference == targetRef }) else {
            return nil
        }
        return CGPoint(x: terminal.worldPosition.x + 8, y: terminal.worldPosition.y - 8)
    }

    private func nextProbeColor() -> ProbeColor {
        let colors = ProbeColor.allCases
        let color = colors[probeColorIndex % colors.count]
        probeColorIndex += 1
        return color
    }

    // MARK: - Junction Computation

    /// Recompute junctions from wire endpoints. A junction exists where 3+ wire endpoints meet.
    public func recomputeJunctions() {
        var counts: [JunctionPointKey: Int] = [:]
        for wire in document.wires {
            counts[JunctionPointKey(wire.startPoint), default: 0] += 1
            counts[JunctionPointKey(wire.endPoint), default: 0] += 1
        }

        // Preserve existing junction IDs for stability
        var existing: [JunctionPointKey: Junction] = [:]
        for j in document.junctions {
            existing[JunctionPointKey(j.position)] = j
        }

        var newJunctions: [Junction] = []
        for (key, count) in counts where count >= 3 {
            if let j = existing[key] {
                newJunctions.append(j)
            } else {
                newJunctions.append(Junction(position: key.cgPoint))
            }
        }
        document.junctions = newJunctions
    }

    // MARK: - Grid Snapping

    public func snapToGrid(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: round(point.x / gridSize) * gridSize,
            y: round(point.y / gridSize) * gridSize
        )
    }

    // MARK: - Utilities

    private func selectionCenter(
        components: [PlacedComponent],
        wires: [Wire],
        labels: [NetLabel]
    ) -> CGPoint {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var count: CGFloat = 0

        for c in components {
            sumX += c.position.x
            sumY += c.position.y
            count += 1
        }
        for w in wires {
            sumX += (w.startPoint.x + w.endPoint.x) / 2
            sumY += (w.startPoint.y + w.endPoint.y) / 2
            count += 1
        }
        for l in labels {
            sumX += l.position.x
            sumY += l.position.y
            count += 1
        }

        guard count > 0 else { return .zero }
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    private func distanceToSegment(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSq))
        let projX = start.x + t * dx
        let projY = start.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }

    private func rotatePoint(_ point: CGPoint, by angle: Double, around center: CGPoint) -> CGPoint {
        let cos = cos(angle)
        let sin = sin(angle)
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos - dy * sin,
            y: center.y + dx * sin + dy * cos
        )
    }

    private func remapPinReference(_ ref: PinReference, idMap: [UUID: UUID]) -> PinReference {
        PinReference(componentID: idMap[ref.componentID] ?? ref.componentID, portID: ref.portID)
    }

    /// Check if a probe references any of the given component IDs.
    private func probeReferencesAny(_ probe: Probe, componentIDs: Set<UUID>) -> Bool {
        switch probe.probeType {
        case .voltage(let ref):
            return componentIDs.contains(ref.componentID)
        case .differential(let pos, let neg):
            return componentIDs.contains(pos.componentID) || componentIDs.contains(neg.componentID)
        case .current(let ref):
            return componentIDs.contains(ref.componentID)
        }
    }
}

/// Hashable point key with integer-snapped precision for junction computation.
private struct JunctionPointKey: Hashable {
    let x: Int
    let y: Int

    init(_ point: CGPoint) {
        self.x = Int(round(point.x))
        self.y = Int(round(point.y))
    }

    var cgPoint: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
}
