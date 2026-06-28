import Foundation
import CircuitPhysicalDesign
import LayoutCore
import LayoutTech

/// A grid maze router for inter-block global routing. It lays a uniform routing grid over
/// the floorplan and connects each net's pins with a Lee/BFS search on two routing
/// layers selected by `LayoutRoutingProfile`. Edge and via occupancy is tracked per
/// layer, so two nets may cross without a via but never share a wire. Pins reach the
/// routing grid through the profile-declared pin-access stack.
public struct MazeRouter: Sendable {

    public enum MazeError: Error, LocalizedError, Equatable {
        case unroutable(net: String)
        case emptyNets
        case invalidConfiguration(reason: String)
        case invalidRoute(reason: String)

        public var errorDescription: String? {
            switch self {
            case .unroutable(let n): return "Maze router could not find a path for net '\(n)'."
            case .emptyNets: return "Maze router was given no nets to route."
            case .invalidConfiguration(let reason): return "Maze router configuration is invalid: \(reason)."
            case .invalidRoute(let reason): return "Maze router emitted an invalid physical route: \(reason)."
            }
        }
    }

    public struct Net: Sendable, Hashable {
        public let name: String
        public let pins: [LayoutPoint]
        public let netID: UUID?

        public init(name: String, pins: [LayoutPoint], netID: UUID? = nil) {
            self.name = name
            self.pins = pins
            self.netID = netID
        }
    }

    private let profile: LayoutRoutingProfile
    private let layoutTechnology: LayoutTechDatabase
    private let pitch: Double
    private let margin: Double
    private let maxOrderingPasses: Int

    public init(
        profile: LayoutRoutingProfile,
        layoutTechnology: LayoutTechDatabase,
        pitch: Double? = nil,
        margin: Double? = nil,
        maxOrderingPasses: Int? = nil
    ) {
        self.profile = profile
        self.layoutTechnology = layoutTechnology
        self.pitch = pitch ?? profile.geometry.gridPitch
        self.margin = margin ?? profile.geometry.gridMargin
        self.maxOrderingPasses = maxOrderingPasses ?? profile.geometry.maxOrderingPasses
    }

    public init(pitch: Double? = nil, margin: Double? = nil, maxOrderingPasses: Int? = nil) {
        do {
            let profile = try LayoutTechnologyCatalog.loadDefaultRoutingProfile()
            let technology = try LayoutTechnologyCatalog.loadDefaultTechnology()
            self.init(
                profile: profile,
                layoutTechnology: technology,
                pitch: pitch,
                margin: margin,
                maxOrderingPasses: maxOrderingPasses
            )
        } catch {
            preconditionFailure("Bundled layout routing profile could not be loaded: \(error)")
        }
    }

    // A grid node.
    private struct Node: Hashable { let c: Int; let r: Int }
    private enum Layer: Hashable {
        case horizontal
        case vertical

        var sortOrder: Int {
            switch self {
            case .horizontal: return 0
            case .vertical: return 1
            }
        }
    }
    private struct RoutingPlan {
        var hEdgeOwner: [Int]
        var vEdgeOwner: [Int]
        var viaOwner: [Int]
        var horizontalNodeOwner: [Int]
        var verticalNodeOwner: [Int]
    }
    private enum AttemptResult {
        case success(RoutingPlan)
        case failure(netIndex: Int)
    }

    public func route(_ nets: [Net]) throws -> [LayoutShape] {
        guard !nets.isEmpty else { throw MazeError.emptyNets }
        guard pitch.isFinite && pitch > 0 else {
            throw MazeError.invalidConfiguration(reason: "pitch must be a positive finite value")
        }
        guard margin.isFinite && margin >= 0 else {
            throw MazeError.invalidConfiguration(reason: "margin must be a non-negative finite value")
        }
        guard maxOrderingPasses > 0 else {
            throw MazeError.invalidConfiguration(reason: "maxOrderingPasses must be greater than zero")
        }
        guard nets.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw MazeError.invalidConfiguration(reason: "net names must be non-empty")
        }
        guard Set(nets.map(\.name)).count == nets.count else {
            throw MazeError.invalidConfiguration(reason: "net names must be unique")
        }
        guard nets.allSatisfy({ !$0.pins.isEmpty }) else {
            throw MazeError.invalidConfiguration(reason: "each net must have at least one pin")
        }
        let allPins = nets.flatMap(\.pins)
        guard allPins.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw MazeError.invalidConfiguration(reason: "all pin coordinates must be finite")
        }
        let minX = (allPins.map(\.x).min() ?? 0) - margin
        let minY = (allPins.map(\.y).min() ?? 0) - margin
        let maxX = (allPins.map(\.x).max() ?? 0) + margin
        let maxY = (allPins.map(\.y).max() ?? 0) + margin
        let cols = max(2, Int(((maxX - minX) / pitch).rounded(.up)) + 1)
        let rows = max(2, Int(((maxY - minY) / pitch).rounded(.up)) + 1)

        func nodeX(_ c: Int) -> Double { minX + Double(c) * pitch }
        func nodeY(_ r: Int) -> Double { minY + Double(r) * pitch }
        func snap(_ p: LayoutPoint) -> Node {
            Node(c: min(max(Int((((p.x - minX) / pitch)).rounded()), 0), cols - 1),
                 r: min(max(Int((((p.y - minY) / pitch)).rounded()), 0), rows - 1))
        }

        let pinNodes = nets.map { $0.pins.map(snap) }
        var order = routeOrder(for: nets, pinNodes: pinNodes)
        var lastFailure: Int?
        for _ in 0..<max(1, maxOrderingPasses) {
            switch attemptRoute(order: order, pinNodes: pinNodes, cols: cols, rows: rows) {
            case .success(let plan):
                let ownedShapes = emit(plan: plan, nets: nets, cols: cols, rows: rows,
                                       nodeX: nodeX, nodeY: nodeY, snap: snap)
                let report = NetAwareLayoutEvaluator().evaluate(shapes: ownedShapes, tech: layoutTechnology)
                guard report.passed else {
                    throw MazeError.invalidRoute(reason: report.summary)
                }
                return ownedShapes.map(\.shape)
            case .failure(let netIndex):
                lastFailure = netIndex
                order.removeAll { $0 == netIndex }
                order.insert(netIndex, at: 0)
            }
        }
        throw MazeError.unroutable(net: nets[lastFailure ?? order.first ?? 0].name)
    }

    // MARK: - search

    private struct State: Hashable { let node: Node; let layer: Layer }

    private func routeOrder(for nets: [Net], pinNodes: [[Node]]) -> [Int] {
        (0..<nets.count).sorted {
            let lhs = routeDifficulty(net: nets[$0], nodes: pinNodes[$0])
            let rhs = routeDifficulty(net: nets[$1], nodes: pinNodes[$1])
            if lhs.span != rhs.span { return lhs.span > rhs.span }
            if lhs.pinCount != rhs.pinCount { return lhs.pinCount > rhs.pinCount }
            return nets[$0].name < nets[$1].name
        }
    }

    private func routeDifficulty(net: Net, nodes: [Node]) -> (span: Int, pinCount: Int) {
        let cols = nodes.map(\.c)
        let rows = nodes.map(\.r)
        let span = (cols.max() ?? 0) - (cols.min() ?? 0) + (rows.max() ?? 0) - (rows.min() ?? 0)
        return (span, net.pins.count)
    }

    private func attemptRoute(order: [Int], pinNodes: [[Node]], cols: Int, rows: Int) -> AttemptResult {
        var plan = RoutingPlan(
            hEdgeOwner: [Int](repeating: -1, count: cols * rows),
            vEdgeOwner: [Int](repeating: -1, count: cols * rows),
            viaOwner: [Int](repeating: -1, count: cols * rows),
            horizontalNodeOwner: [Int](repeating: -1, count: cols * rows),
            verticalNodeOwner: [Int](repeating: -1, count: cols * rows)
        )

        for netIndex in pinNodes.indices {
            for terminalNode in pinNodes[netIndex] {
                guard reserve(State(node: terminalNode, layer: .horizontal), netIndex: netIndex, cols: cols,
                              horizontalNodeOwner: &plan.horizontalNodeOwner,
                              verticalNodeOwner: &plan.verticalNodeOwner) else {
                    return .failure(netIndex: netIndex)
                }
            }
        }

        for netIndex in order {
            let terminals = pinNodes[netIndex]
            guard let first = terminals.first else { continue }
            var inTree = Set([State(node: first, layer: .horizontal)])
            for targetNode in terminals.dropFirst() {
                let target = State(node: targetNode, layer: .horizontal)
                guard !inTree.contains(target) else { continue }
                let path = search(from: inTree, to: target, netIndex: netIndex, cols: cols, rows: rows,
                                  hEdgeOwner: plan.hEdgeOwner,
                                  vEdgeOwner: plan.vEdgeOwner,
                                  viaOwner: plan.viaOwner,
                                  horizontalNodeOwner: plan.horizontalNodeOwner,
                                  verticalNodeOwner: plan.verticalNodeOwner)
                guard let path else { return .failure(netIndex: netIndex) }
                commit(path, netIndex: netIndex, cols: cols,
                       hEdgeOwner: &plan.hEdgeOwner,
                       vEdgeOwner: &plan.vEdgeOwner,
                       viaOwner: &plan.viaOwner,
                       horizontalNodeOwner: &plan.horizontalNodeOwner,
                       verticalNodeOwner: &plan.verticalNodeOwner)
                inTree.formUnion(path)
            }
        }
        return .success(plan)
    }

    /// BFS over (node, layer); pins live on the horizontal routing layer, so the search both
    /// starts and ends there. Horizontal moves use horizontal edges, vertical moves use
    /// vertical edges, and a layer switch at a node costs a turn cut while avoiding any
    /// edge/cut already owned by another net. Returns the full path so edges and cuts are
    /// read off exactly.
    private func search(
        from sources: Set<State>, to target: State, netIndex: Int, cols: Int, rows: Int,
        hEdgeOwner: [Int], vEdgeOwner: [Int], viaOwner: [Int],
        horizontalNodeOwner: [Int], verticalNodeOwner: [Int]
    ) -> [State]? {
        func hOK(_ c: Int, _ r: Int) -> Bool { let o = hEdgeOwner[r * cols + c]; return o < 0 || o == netIndex }
        func vOK(_ c: Int, _ r: Int) -> Bool { let o = vEdgeOwner[r * cols + c]; return o < 0 || o == netIndex }
        func viaOK(_ c: Int, _ r: Int) -> Bool { let o = viaOwner[r * cols + c]; return o < 0 || o == netIndex }
        func nodeOK(_ state: State) -> Bool {
            let owner: Int
            switch state.layer {
            case .horizontal:
                owner = horizontalNodeOwner[state.node.r * cols + state.node.c]
            case .vertical:
                owner = verticalNodeOwner[state.node.r * cols + state.node.c]
            }
            return owner < 0 || owner == netIndex
        }

        var prev: [State: State] = [:]
        var visited = Set<State>()
        var queue: [State] = []
        for source in sources.sorted(by: { lhs, rhs in
            if lhs.node.r != rhs.node.r { return lhs.node.r < rhs.node.r }
            if lhs.node.c != rhs.node.c { return lhs.node.c < rhs.node.c }
            return lhs.layer.sortOrder < rhs.layer.sortOrder
        }) {
            visited.insert(source)
            queue.append(source)
        }
        var head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            if cur == target { return reconstruct(cur, prev: prev) }
            let c = cur.node.c, r = cur.node.r
            var neighbors: [State] = []
            if cur.layer == .horizontal {
                if c + 1 < cols && hOK(c, r) {
                    neighbors.append(State(node: Node(c: c + 1, r: r), layer: .horizontal))
                }
                if c - 1 >= 0 && hOK(c - 1, r) {
                    neighbors.append(State(node: Node(c: c - 1, r: r), layer: .horizontal))
                }
            } else {
                if r + 1 < rows && vOK(c, r) {
                    neighbors.append(State(node: Node(c: c, r: r + 1), layer: .vertical))
                }
                if r - 1 >= 0 && vOK(c, r - 1) {
                    neighbors.append(State(node: Node(c: c, r: r - 1), layer: .vertical))
                }
            }
            if viaOK(c, r) {
                neighbors.append(State(node: cur.node, layer: cur.layer == .horizontal ? .vertical : .horizontal))
            }
            for nb in neighbors where !visited.contains(nb) && nodeOK(nb) {
                visited.insert(nb); prev[nb] = cur; queue.append(nb)
            }
        }
        return nil
    }

    private func reconstruct(_ end: State, prev: [State: State]) -> [State] {
        var states: [State] = []
        var cur: State? = end
        while let s = cur { states.append(s); cur = prev[s] }
        return states.reversed()
    }

    private func commit(
        _ path: [State], netIndex: Int, cols: Int,
        hEdgeOwner: inout [Int], vEdgeOwner: inout [Int], viaOwner: inout [Int],
        horizontalNodeOwner: inout [Int], verticalNodeOwner: inout [Int]
    ) {
        guard path.count >= 2 else { return }
        for state in path {
            _ = reserve(state, netIndex: netIndex, cols: cols,
                        horizontalNodeOwner: &horizontalNodeOwner,
                        verticalNodeOwner: &verticalNodeOwner)
        }
        for i in 1..<path.count {
            let a = path[i - 1], b = path[i]
            if a.node == b.node {
                viaOwner[a.node.r * cols + a.node.c] = netIndex
            } else if a.node.r == b.node.r {
                hEdgeOwner[a.node.r * cols + min(a.node.c, b.node.c)] = netIndex
            } else {
                vEdgeOwner[min(a.node.r, b.node.r) * cols + a.node.c] = netIndex
            }
        }
    }

    private func reserve(
        _ state: State,
        netIndex: Int,
        cols: Int,
        horizontalNodeOwner: inout [Int],
        verticalNodeOwner: inout [Int]
    ) -> Bool {
        let index = state.node.r * cols + state.node.c
        switch state.layer {
        case .horizontal:
            guard horizontalNodeOwner[index] < 0 || horizontalNodeOwner[index] == netIndex else { return false }
            horizontalNodeOwner[index] = netIndex
        case .vertical:
            guard verticalNodeOwner[index] < 0 || verticalNodeOwner[index] == netIndex else { return false }
            verticalNodeOwner[index] = netIndex
        }
        return true
    }

    // MARK: - geometry

    private func emit(
        plan: RoutingPlan,
        nets: [Net],
        cols: Int,
        rows: Int,
        nodeX: (Int) -> Double,
        nodeY: (Int) -> Double,
        snap: (LayoutPoint) -> Node
    ) -> [NetAwareLayoutEvaluator.OwnedShape] {
        func hIdx(_ c: Int, _ r: Int) -> Int { r * cols + c }
        func vIdx(_ c: Int, _ r: Int) -> Int { r * cols + c }
        func owned(_ shape: LayoutShape, by net: Net) -> NetAwareLayoutEvaluator.OwnedShape {
            NetAwareLayoutEvaluator.OwnedShape(netName: net.name, shape: shape)
        }

        var shapes: [NetAwareLayoutEvaluator.OwnedShape] = []
        for net in nets {
            for pin in net.pins {
                let node = snap(pin)
                shapes.append(contentsOf: pinAccessStack(x: pin.x, y: pin.y, net: net).map { owned($0, by: net) })
                shapes.append(contentsOf: horizontalLayerJog(from: pin, toX: nodeX(node.c), toY: nodeY(node.r), net: net)
                    .map { owned($0, by: net) })
            }
        }

        for r in 0..<rows {
            for c in 0..<(cols - 1) {
                let owner = plan.hEdgeOwner[hIdx(c, r)]
                guard owner >= 0 else { continue }
                let net = nets[owner]
                shapes.append(owned(horizontalWire(nodeX(c), nodeX(c + 1), nodeY(r), net: net), by: net))
            }
        }
        for c in 0..<cols {
            for r in 0..<(rows - 1) {
                let owner = plan.vEdgeOwner[vIdx(c, r)]
                guard owner >= 0 else { continue }
                let net = nets[owner]
                shapes.append(owned(verticalWire(nodeX(c), nodeY(r), nodeY(r + 1), net: net), by: net))
            }
        }
        for r in 0..<rows {
            for c in 0..<cols {
                let owner = plan.viaOwner[r * cols + c]
                guard owner >= 0 else { continue }
                let net = nets[owner]
                shapes.append(contentsOf: turnStack(x: nodeX(c), y: nodeY(r), net: net).map { owned($0, by: net) })
            }
        }
        return shapes
    }

    private func rect(
        _ role: LayoutRoutingProfile.LayerRole,
        _ x: Double,
        _ y: Double,
        _ w: Double,
        _ h: Double,
        net: Net
    ) -> LayoutShape {
        LayoutShape(layer: profile.layerID(for: role),
                    netID: net.netID,
                    geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h))),
                    properties: [NetAwareLayoutEvaluator.netNameProperty: net.name])
    }

    private func horizontalWire(_ x0: Double, _ x1: Double, _ y: Double, net: Net) -> LayoutShape {
        let width = profile.geometry.mazeWireWidth
        return rect(
            .horizontalRouting,
            min(x0, x1) - width / 2,
            y - width / 2,
            abs(x1 - x0) + width,
            width,
            net: net
        )
    }

    private func verticalWire(_ x: Double, _ y0: Double, _ y1: Double, net: Net) -> LayoutShape {
        let width = profile.geometry.mazeWireWidth
        return rect(
            .verticalRouting,
            x - width / 2,
            min(y0, y1) - width / 2,
            width,
            abs(y1 - y0) + width,
            net: net
        )
    }

    private func pinAccessStack(x: Double, y: Double, net: Net) -> [LayoutShape] {
        let bottom = profile.geometry.pinBottomPadWidth
        let cut = profile.geometry.pinAccessCutWidth
        let top = profile.geometry.pinTopPadWidth
        return [
            rect(.pinAccessBottom, x - bottom / 2, y - bottom / 2, bottom, bottom, net: net),
            rect(.pinAccessCut, x - cut / 2, y - cut / 2, cut, cut, net: net),
            rect(.horizontalRouting, x - top / 2, y - top / 2, top, top, net: net),
        ]
    }

    private func horizontalLayerJog(from p: LayoutPoint, toX gx: Double, toY gy: Double, net: Net) -> [LayoutShape] {
        var shapes: [LayoutShape] = []
        if abs(gx - p.x) > 1e-6 { shapes.append(horizontalWire(p.x, gx, p.y, net: net)) }
        if abs(gy - p.y) > 1e-6 { shapes.append(verticalJogOnHorizontalLayer(gx, p.y, gy, net: net)) }
        return shapes
    }

    private func verticalJogOnHorizontalLayer(_ x: Double, _ y0: Double, _ y1: Double, net: Net) -> LayoutShape {
        let width = profile.geometry.mazeWireWidth
        return rect(
            .horizontalRouting,
            x - width / 2,
            min(y0, y1) - width / 2,
            width,
            abs(y1 - y0) + width,
            net: net
        )
    }

    private func turnStack(x: Double, y: Double, net: Net) -> [LayoutShape] {
        let pad = profile.geometry.turnPadWidth
        let cut = profile.geometry.turnCutWidth
        return [
            rect(.horizontalRouting, x - pad / 2, y - pad / 2, pad, pad, net: net),
            rect(.turnCut, x - cut / 2, y - cut / 2, cut, cut, net: net),
            rect(.verticalRouting, x - pad / 2, y - pad / 2, pad, pad, net: net),
        ]
    }
}
