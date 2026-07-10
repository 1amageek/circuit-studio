import CoreGraphics
import Foundation

struct ConnectivityAwareSchematicLayoutEngine: Sendable {
    struct Component: Sendable {
        var placed: PlacedComponent
        let nodesByPortID: [String: String]
        let sourceOrder: Int
    }

    private struct CMOSStage: Sendable {
        let pmosID: UUID
        let nmosID: UUID
        let inputNode: String
        let outputNode: String
        let sourceOrder: Int
    }

    private struct StageGeometry: Sendable {
        let inputPoint: CGPoint
        let outputPoint: CGPoint
    }

    private let catalog: DeviceCatalog

    init(catalog: DeviceCatalog) {
        self.catalog = catalog
    }

    func makeDocument(components: [Component]) throws -> SchematicDocument {
        var state = RoutingState(components: components, catalog: catalog)
        let stages = orderedStages(from: components)

        if stages.isEmpty {
            placeAndRouteFallback(components, state: &state, startingY: 80)
        } else {
            try placeAndRouteCMOS(stages: stages, components: components, state: &state)
        }

        let pinIssues = state.pinRoutingIssues()
        guard pinIssues.isEmpty else {
            throw SPICESchematicImportError.layoutFailed(pinIssues)
        }

        let document = state.document()
        try validateConnectivity(document: document, components: components)
        return document
    }

    private func placeAndRouteCMOS(
        stages: [CMOSStage],
        components: [Component],
        state: inout RoutingState
    ) throws {
        let stageComponentIDs = Set(stages.flatMap { [$0.pmosID, $0.nmosID] })
        let upperRailNode = dominantRailNode(
            stages.flatMap { stage in
                railCandidates(componentID: stage.pmosID, in: components, portIDs: ["source", "bulk"])
            },
            preferred: nil
        )
        let lowerRailNode = dominantRailNode(
            stages.flatMap { stage in
                railCandidates(componentID: stage.nmosID, in: components, portIDs: ["source", "bulk"])
            },
            preferred: "0"
        )

        guard let upperRailNode, let lowerRailNode else {
            placeAndRouteFallback(components, state: &state, startingY: 80)
            return
        }

        let supply = components.first { component in
            guard component.placed.deviceKindID == "vsource",
                  let nodes = twoTerminalNodes(component) else {
                return false
            }
            return nodes.top == upperRailNode && nodes.bottom == lowerRailNode
        }
        var claimedIDs = stageComponentIDs
        if let supply {
            claimedIDs.insert(supply.placed.id)
        }

        var accessoriesByOutput: [String: [Component]] = [:]
        let outputNodes = Set(stages.map(\.outputNode))
        for component in components where !claimedIDs.contains(component.placed.id) {
            guard let nodes = twoTerminalNodes(component),
                  outputNodes.contains(nodes.top),
                  nodes.bottom == lowerRailNode else {
                continue
            }
            accessoriesByOutput[nodes.top, default: []].append(component)
            claimedIDs.insert(component.placed.id)
        }
        for node in accessoriesByOutput.keys {
            accessoriesByOutput[node]?.sort { $0.sourceOrder < $1.sourceOrder }
        }

        let maximumAccessoryCount = accessoriesByOutput.values.map(\.count).max() ?? 0
        let accessoryFirstOffset: CGFloat = 80
        let accessoryPitch: CGFloat = 140
        let accessoryTrailingSpace: CGFloat = 60
        let accessoryWidth = maximumAccessoryCount == 0
            ? CGFloat.zero
            : accessoryFirstOffset
                + CGFloat(maximumAccessoryCount - 1) * accessoryPitch
                + accessoryTrailingSpace
        let stagePitch = max(CGFloat(280), accessoryWidth)
        let firstStageX: CGFloat = 180
        let pmosY: CGFloat = 80
        let nmosY: CGFloat = 200
        let signalY: CGFloat = 140
        let upperRailY: CGFloat = 20
        let lowerRailY: CGFloat = 340

        var stageGeometry: [UUID: StageGeometry] = [:]
        for (index, stage) in stages.enumerated() {
            let x = firstStageX + CGFloat(index) * stagePitch
            state.setPosition(CGPoint(x: x, y: pmosY), componentID: stage.pmosID)
            state.setPosition(CGPoint(x: x, y: nmosY), componentID: stage.nmosID)
            stageGeometry[stage.pmosID] = StageGeometry(
                inputPoint: CGPoint(x: x - 40, y: signalY),
                outputPoint: CGPoint(x: x + 10, y: signalY)
            )
        }

        let supplyX = firstStageX - 140
        if let supply {
            state.setPosition(
                CGPoint(x: supplyX, y: (upperRailY + lowerRailY) / 2),
                componentID: supply.placed.id
            )
        }
        let railStartX = supply == nil ? firstStageX - 40 : supplyX
        let railEndX = firstStageX
            + CGFloat(stages.count - 1) * stagePitch
            + max(CGFloat(100), accessoryWidth)
        state.connect(
            from: CGPoint(x: railStartX, y: upperRailY),
            to: CGPoint(x: railEndX, y: upperRailY),
            netName: upperRailNode
        )
        state.addLabel(upperRailNode, at: CGPoint(x: railStartX, y: upperRailY))
        state.connect(
            from: CGPoint(x: railStartX, y: lowerRailY),
            to: CGPoint(x: railEndX, y: lowerRailY),
            netName: lowerRailNode
        )
        state.addLabel(lowerRailNode, at: CGPoint(x: railStartX, y: lowerRailY))

        for stage in stages {
            guard let geometry = stageGeometry[stage.pmosID] else { continue }
            routeStage(
                stage,
                geometry: geometry,
                upperRailNode: upperRailNode,
                lowerRailNode: lowerRailNode,
                upperRailY: upperRailY,
                lowerRailY: lowerRailY,
                state: &state
            )
        }

        for index in stages.indices {
            let stage = stages[index]
            guard let geometry = stageGeometry[stage.pmosID] else { continue }
            if index > 0,
               stages[index - 1].outputNode == stage.inputNode,
               let previousGeometry = stageGeometry[stages[index - 1].pmosID] {
                state.connect(
                    from: previousGeometry.outputPoint,
                    to: geometry.inputPoint,
                    netName: stage.inputNode
                )
                state.addJunction(at: previousGeometry.outputPoint)
                state.addJunction(at: geometry.inputPoint)
            } else {
                let labelPoint = CGPoint(x: geometry.inputPoint.x - 30, y: geometry.inputPoint.y)
                state.connect(from: geometry.inputPoint, to: labelPoint, netName: stage.inputNode)
                state.addLabel(stage.inputNode, at: labelPoint)
                state.addJunction(at: geometry.inputPoint)
            }
        }

        for (index, stage) in stages.enumerated() {
            guard let geometry = stageGeometry[stage.pmosID] else { continue }
            let accessories = accessoriesByOutput[stage.outputNode] ?? []
            for (accessoryIndex, accessory) in accessories.enumerated() {
                let x = firstStageX
                    + CGFloat(index) * stagePitch
                    + accessoryFirstOffset
                    + CGFloat(accessoryIndex) * accessoryPitch
                state.setPosition(CGPoint(x: x, y: 270), componentID: accessory.placed.id)
                guard let kind = catalog.device(for: accessory.placed.deviceKindID),
                      kind.portDefinitions.count == 2 else {
                    continue
                }
                let topPortID = kind.portDefinitions[0].id
                let bottomPortID = kind.portDefinitions[1].id
                guard let topPoint = state.pinPoint(componentID: accessory.placed.id, portID: topPortID),
                      let bottomPoint = state.pinPoint(componentID: accessory.placed.id, portID: bottomPortID) else {
                    continue
                }
                let branchPoint = CGPoint(x: topPoint.x, y: geometry.outputPoint.y)
                state.connect(
                    from: topPoint,
                    to: branchPoint,
                    startPin: PinReference(componentID: accessory.placed.id, portID: topPortID),
                    netName: stage.outputNode
                )
                state.connect(from: branchPoint, to: geometry.outputPoint, netName: stage.outputNode)
                state.addJunction(at: branchPoint)
                state.addJunction(at: geometry.outputPoint)
                state.connect(
                    from: bottomPoint,
                    to: CGPoint(x: bottomPoint.x, y: lowerRailY),
                    startPin: PinReference(componentID: accessory.placed.id, portID: bottomPortID),
                    netName: lowerRailNode
                )
                state.addJunction(at: CGPoint(x: bottomPoint.x, y: lowerRailY))
            }
        }

        if let supply,
           let kind = catalog.device(for: supply.placed.deviceKindID),
           kind.portDefinitions.count == 2 {
            let positivePortID = kind.portDefinitions[0].id
            let negativePortID = kind.portDefinitions[1].id
            if let positivePoint = state.pinPoint(componentID: supply.placed.id, portID: positivePortID) {
                state.connect(
                    from: positivePoint,
                    to: CGPoint(x: positivePoint.x, y: upperRailY),
                    startPin: PinReference(componentID: supply.placed.id, portID: positivePortID),
                    netName: upperRailNode
                )
                state.addJunction(at: CGPoint(x: positivePoint.x, y: upperRailY))
            }
            if let negativePoint = state.pinPoint(componentID: supply.placed.id, portID: negativePortID) {
                state.connect(
                    from: negativePoint,
                    to: CGPoint(x: negativePoint.x, y: lowerRailY),
                    startPin: PinReference(componentID: supply.placed.id, portID: negativePortID),
                    netName: lowerRailNode
                )
                state.addJunction(at: CGPoint(x: negativePoint.x, y: lowerRailY))
            }
        }

        let fallback = components.filter { !claimedIDs.contains($0.placed.id) }
        placeAndRouteFallback(fallback, state: &state, startingY: 460)
    }

    private func routeStage(
        _ stage: CMOSStage,
        geometry: StageGeometry,
        upperRailNode: String,
        lowerRailNode: String,
        upperRailY: CGFloat,
        lowerRailY: CGFloat,
        state: inout RoutingState
    ) {
        guard let pmosGate = state.pinPoint(componentID: stage.pmosID, portID: "gate"),
              let nmosGate = state.pinPoint(componentID: stage.nmosID, portID: "gate"),
              let pmosDrain = state.pinPoint(componentID: stage.pmosID, portID: "drain"),
              let nmosDrain = state.pinPoint(componentID: stage.nmosID, portID: "drain") else {
            return
        }

        let gateTop = CGPoint(x: geometry.inputPoint.x, y: pmosGate.y)
        let gateBottom = CGPoint(x: geometry.inputPoint.x, y: nmosGate.y)
        state.connect(
            from: pmosGate,
            to: gateTop,
            startPin: PinReference(componentID: stage.pmosID, portID: "gate"),
            netName: stage.inputNode
        )
        state.connect(from: gateTop, to: gateBottom, netName: stage.inputNode)
        state.connect(
            from: nmosGate,
            to: gateBottom,
            startPin: PinReference(componentID: stage.nmosID, portID: "gate"),
            netName: stage.inputNode
        )

        state.connect(
            from: pmosDrain,
            to: geometry.outputPoint,
            startPin: PinReference(componentID: stage.pmosID, portID: "drain"),
            netName: stage.outputNode
        )
        state.connect(
            from: nmosDrain,
            to: geometry.outputPoint,
            startPin: PinReference(componentID: stage.nmosID, portID: "drain"),
            netName: stage.outputNode
        )
        let outputLabelPoint = CGPoint(x: geometry.outputPoint.x + 18, y: geometry.outputPoint.y)
        state.connect(from: geometry.outputPoint, to: outputLabelPoint, netName: stage.outputNode)
        state.addLabel(stage.outputNode, at: outputLabelPoint)
        state.addJunction(at: geometry.outputPoint)

        routeRailPins(
            componentID: stage.pmosID,
            portIDs: ["source", "bulk"],
            railNode: upperRailNode,
            railY: upperRailY,
            fallbackDirection: -1,
            state: &state
        )
        routeRailPins(
            componentID: stage.nmosID,
            portIDs: ["source", "bulk"],
            railNode: lowerRailNode,
            railY: lowerRailY,
            fallbackDirection: 1,
            state: &state
        )
    }

    private func routeRailPins(
        componentID: UUID,
        portIDs: [String],
        railNode: String,
        railY: CGFloat,
        fallbackDirection: CGFloat,
        state: inout RoutingState
    ) {
        for portID in portIDs {
            guard let node = state.node(componentID: componentID, portID: portID),
                  let point = state.pinPoint(componentID: componentID, portID: portID) else {
                continue
            }
            let pin = PinReference(componentID: componentID, portID: portID)
            if node == railNode {
                let railPoint = CGPoint(x: point.x, y: railY)
                state.connect(from: point, to: railPoint, startPin: pin, netName: node)
                state.addJunction(at: railPoint)
            } else {
                let labelPoint = CGPoint(x: point.x, y: point.y + fallbackDirection * 36)
                state.connect(from: point, to: labelPoint, startPin: pin, netName: node)
                state.addLabel(node, at: labelPoint)
            }
        }
    }

    private func placeAndRouteFallback(
        _ components: [Component],
        state: inout RoutingState,
        startingY: CGFloat
    ) {
        for (index, component) in components.sorted(by: { $0.sourceOrder < $1.sourceOrder }).enumerated() {
            let column = index % 4
            let row = index / 4
            state.setPosition(
                CGPoint(x: 160 + CGFloat(column) * 220, y: startingY + CGFloat(row) * 150),
                componentID: component.placed.id
            )
            guard let kind = catalog.device(for: component.placed.deviceKindID) else { continue }
            for port in kind.portDefinitions {
                guard let node = component.nodesByPortID[port.id],
                      let point = state.pinPoint(componentID: component.placed.id, portID: port.id) else {
                    continue
                }
                let offset = port.position
                let labelPoint: CGPoint
                if abs(offset.x) >= abs(offset.y) {
                    let direction: CGFloat = offset.x < 0 ? -1 : 1
                    labelPoint = CGPoint(x: point.x + direction * 44, y: point.y)
                } else {
                    let direction: CGFloat = offset.y < 0 ? -1 : 1
                    labelPoint = CGPoint(x: point.x, y: point.y + direction * 44)
                }
                state.connect(
                    from: point,
                    to: labelPoint,
                    startPin: PinReference(componentID: component.placed.id, portID: port.id),
                    netName: node
                )
                state.addLabel(node, at: labelPoint)
            }
        }
    }

    private func orderedStages(from components: [Component]) -> [CMOSStage] {
        let pmos = components.filter { $0.placed.deviceKindID.hasPrefix("pmos_") }
        let nmos = components.filter { $0.placed.deviceKindID.hasPrefix("nmos_") }
        var usedNMOS: Set<UUID> = []
        var detected: [CMOSStage] = []

        for pmosComponent in pmos.sorted(by: { $0.sourceOrder < $1.sourceOrder }) {
            guard let gate = pmosComponent.nodesByPortID["gate"],
                  let drain = pmosComponent.nodesByPortID["drain"],
                  let match = nmos
                    .filter({ !usedNMOS.contains($0.placed.id) })
                    .sorted(by: { $0.sourceOrder < $1.sourceOrder })
                    .first(where: {
                        $0.nodesByPortID["gate"] == gate
                            && $0.nodesByPortID["drain"] == drain
                    }) else {
                continue
            }
            usedNMOS.insert(match.placed.id)
            detected.append(CMOSStage(
                pmosID: pmosComponent.placed.id,
                nmosID: match.placed.id,
                inputNode: gate,
                outputNode: drain,
                sourceOrder: min(pmosComponent.sourceOrder, match.sourceOrder)
            ))
        }

        guard !detected.isEmpty else { return [] }
        detected.sort { $0.sourceOrder < $1.sourceOrder }
        let outputNodes = Set(detected.map(\.outputNode))
        let startIndex = detected.firstIndex(where: { !outputNodes.contains($0.inputNode) }) ?? 0
        var ordered: [CMOSStage] = []
        var visited: Set<UUID> = []
        var current = detected[startIndex]

        while !visited.contains(current.pmosID) {
            ordered.append(current)
            visited.insert(current.pmosID)
            guard let next = detected.first(where: {
                !visited.contains($0.pmosID) && $0.inputNode == current.outputNode
            }) else {
                break
            }
            current = next
        }
        ordered.append(contentsOf: detected.filter { !visited.contains($0.pmosID) })
        return ordered
    }

    private func railCandidates(
        componentID: UUID,
        in components: [Component],
        portIDs: [String]
    ) -> [String] {
        guard let component = components.first(where: { $0.placed.id == componentID }) else {
            return []
        }
        return portIDs.compactMap { component.nodesByPortID[$0] }
    }

    private func dominantRailNode(_ nodes: [String], preferred: String?) -> String? {
        guard !nodes.isEmpty else { return nil }
        let counts = Dictionary(grouping: nodes, by: { $0 }).mapValues(\.count)
        return counts.keys.sorted { left, right in
            let leftCount = counts[left] ?? 0
            let rightCount = counts[right] ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            if let preferred {
                if left == preferred { return true }
                if right == preferred { return false }
            }
            return left < right
        }.first
    }

    private func twoTerminalNodes(_ component: Component) -> (top: String, bottom: String)? {
        guard let kind = catalog.device(for: component.placed.deviceKindID),
              kind.portDefinitions.count == 2,
              let top = component.nodesByPortID[kind.portDefinitions[0].id],
              let bottom = component.nodesByPortID[kind.portDefinitions[1].id] else {
            return nil
        }
        return (top, bottom)
    }

    private func validateConnectivity(
        document: SchematicDocument,
        components: [Component]
    ) throws {
        var expected: [String: Set<PinReference>] = [:]
        for component in components {
            for (portID, node) in component.nodesByPortID {
                expected[node, default: []].insert(
                    PinReference(componentID: component.placed.id, portID: portID)
                )
            }
        }

        let actualGroups = Dictionary(grouping: NetExtractor().extract(from: document), by: \.name)
        var issues: [String] = []
        for node in expected.keys.sorted() {
            guard let groups = actualGroups[node] else {
                issues.append("node '\(node)' is missing")
                continue
            }
            guard groups.count == 1 else {
                issues.append("node '\(node)' materialized as \(groups.count) disconnected nets")
                continue
            }
            let actualPins = Set(groups[0].connections)
            if actualPins != expected[node] {
                issues.append("node '\(node)' pin set does not match SPICE")
            }
        }
        for node in actualGroups.keys where expected[node] == nil {
            issues.append("unexpected node '\(node)' was materialized")
        }
        guard issues.isEmpty else {
            throw SPICESchematicImportError.layoutFailed(issues.sorted())
        }
    }

    private struct RoutingState {
        private var componentsByID: [UUID: Component]
        private let componentOrder: [UUID]
        private let catalog: DeviceCatalog
        private(set) var wires: [Wire] = []
        private(set) var labels: [NetLabel] = []
        private(set) var junctions: [Junction] = []
        private var routedPinCounts: [PinReference: Int] = [:]
        private var labelKeys: Set<LabelKey> = []
        private var junctionKeys: Set<PointKey> = []

        init(components: [Component], catalog: DeviceCatalog) {
            componentsByID = Dictionary(
                components.map { ($0.placed.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            componentOrder = components.sorted { $0.sourceOrder < $1.sourceOrder }.map(\.placed.id)
            self.catalog = catalog
        }

        mutating func setPosition(_ position: CGPoint, componentID: UUID) {
            componentsByID[componentID]?.placed.position = position
        }

        func node(componentID: UUID, portID: String) -> String? {
            componentsByID[componentID]?.nodesByPortID[portID]
        }

        func pinPoint(componentID: UUID, portID: String) -> CGPoint? {
            guard let component = componentsByID[componentID],
                  let kind = catalog.device(for: component.placed.deviceKindID),
                  let port = kind.portDefinitions.first(where: { $0.id == portID }) else {
                return nil
            }
            return CGPoint(
                x: component.placed.position.x + port.position.x,
                y: component.placed.position.y + port.position.y
            )
        }

        mutating func connect(
            from start: CGPoint,
            to end: CGPoint,
            startPin: PinReference? = nil,
            endPin: PinReference? = nil,
            netName: String
        ) {
            guard start != end else {
                if let startPin { routedPinCounts[startPin, default: 0] += 1 }
                if let endPin { routedPinCounts[endPin, default: 0] += 1 }
                wires.append(Wire(
                    startPoint: start,
                    endPoint: end,
                    startPin: startPin,
                    endPin: endPin,
                    netName: netName
                ))
                return
            }

            if start.x == end.x || start.y == end.y {
                appendSegment(
                    from: start,
                    to: end,
                    startPin: startPin,
                    endPin: endPin,
                    netName: netName
                )
                return
            }

            let corner = CGPoint(x: end.x, y: start.y)
            appendSegment(
                from: start,
                to: corner,
                startPin: startPin,
                netName: netName
            )
            appendSegment(
                from: corner,
                to: end,
                endPin: endPin,
                netName: netName
            )
        }

        mutating func addLabel(_ name: String, at point: CGPoint) {
            let key = LabelKey(name: name, point: PointKey(point))
            guard labelKeys.insert(key).inserted else { return }
            labels.append(NetLabel(name: name, position: point))
        }

        mutating func addJunction(at point: CGPoint) {
            let key = PointKey(point)
            guard junctionKeys.insert(key).inserted else { return }
            junctions.append(Junction(position: point))
        }

        func pinRoutingIssues() -> [String] {
            var issues: [String] = []
            for componentID in componentOrder {
                guard let component = componentsByID[componentID] else { continue }
                for portID in component.nodesByPortID.keys.sorted() {
                    let pin = PinReference(componentID: componentID, portID: portID)
                    let count = routedPinCounts[pin] ?? 0
                    if count != 1 {
                        issues.append("\(component.placed.name).\(portID) was routed \(count) times")
                    }
                }
            }
            return issues
        }

        func document() -> SchematicDocument {
            SchematicDocument(
                components: componentOrder.compactMap { componentsByID[$0]?.placed },
                wires: wires,
                labels: labels,
                junctions: junctions
            )
        }

        private mutating func appendSegment(
            from start: CGPoint,
            to end: CGPoint,
            startPin: PinReference? = nil,
            endPin: PinReference? = nil,
            netName: String
        ) {
            wires.append(Wire(
                startPoint: start,
                endPoint: end,
                startPin: startPin,
                endPin: endPin,
                netName: netName
            ))
            if let startPin { routedPinCounts[startPin, default: 0] += 1 }
            if let endPin { routedPinCounts[endPin, default: 0] += 1 }
        }
    }

    private struct PointKey: Hashable {
        let x: Int
        let y: Int

        init(_ point: CGPoint) {
            x = Int(point.x.rounded())
            y = Int(point.y.rounded())
        }
    }

    private struct LabelKey: Hashable {
        let name: String
        let point: PointKey
    }
}
