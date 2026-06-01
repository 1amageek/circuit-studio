import Foundation
import LayoutCore

/// A grid maze router for inter-block global routing. It lays a uniform routing grid over
/// the floorplan and connects each net's pins with a Lee/BFS search on two over-the-cell
/// layers — met3 for horizontal edges, met4 for vertical edges, via3 where a net turns.
/// Edge and via occupancy is tracked per layer, so two nets may cross (met3 over met4
/// without a via) but never share a wire — many crossing nets route without collision,
/// which the fixed-lane router could not do. Pins reach the grid through a via2 (met2→met3).
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

    private let pitch: Double
    private let margin: Double
    private let maxOrderingPasses: Int

    public init(pitch: Double = 0.9, margin: Double = 1.4, maxOrderingPasses: Int = 64) {
        self.pitch = pitch   // >= 0.50 (via pad) + 0.30 (met3/met4 spacing) so pads never clash
        self.margin = margin
        self.maxOrderingPasses = maxOrderingPasses
    }

    // A grid node.
    private struct Node: Hashable { let c: Int; let r: Int }
    private enum Layer: Hashable {
        case met3
        case met4

        var sortOrder: Int {
            switch self {
            case .met3: return 0
            case .met4: return 1
            }
        }
    }
    private struct RoutingPlan {
        var hEdgeOwner: [Int]
        var vEdgeOwner: [Int]
        var viaOwner: [Int]
        var met3NodeOwner: [Int]
        var met4NodeOwner: [Int]
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
                let report = NetAwareLayoutEvaluator().evaluate(shapes: ownedShapes, tech: Sky130LayoutTech.tech())
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
            met3NodeOwner: [Int](repeating: -1, count: cols * rows),
            met4NodeOwner: [Int](repeating: -1, count: cols * rows)
        )

        for netIndex in pinNodes.indices {
            for terminalNode in pinNodes[netIndex] {
                guard reserve(State(node: terminalNode, layer: .met3), netIndex: netIndex, cols: cols,
                              met3NodeOwner: &plan.met3NodeOwner,
                              met4NodeOwner: &plan.met4NodeOwner) else {
                    return .failure(netIndex: netIndex)
                }
            }
        }

        for netIndex in order {
            let terminals = pinNodes[netIndex]
            guard let first = terminals.first else { continue }
            var inTree = Set([State(node: first, layer: .met3)])
            for targetNode in terminals.dropFirst() {
                let target = State(node: targetNode, layer: .met3)
                guard !inTree.contains(target) else { continue }
                let path = search(from: inTree, to: target, netIndex: netIndex, cols: cols, rows: rows,
                                  hEdgeOwner: plan.hEdgeOwner,
                                  vEdgeOwner: plan.vEdgeOwner,
                                  viaOwner: plan.viaOwner,
                                  met3NodeOwner: plan.met3NodeOwner,
                                  met4NodeOwner: plan.met4NodeOwner)
                guard let path else { return .failure(netIndex: netIndex) }
                commit(path, netIndex: netIndex, cols: cols,
                       hEdgeOwner: &plan.hEdgeOwner,
                       vEdgeOwner: &plan.vEdgeOwner,
                       viaOwner: &plan.viaOwner,
                       met3NodeOwner: &plan.met3NodeOwner,
                       met4NodeOwner: &plan.met4NodeOwner)
                inTree.formUnion(path)
            }
        }
        return .success(plan)
    }

    /// BFS over (node, layer); pins live on met3, so the search both starts and ends on met3.
    /// Horizontal moves use met3 edges, vertical use met4 edges, and a layer switch at a node
    /// costs a via3 — avoiding any edge/via already owned by another net. Returns the full
    /// (node, layer) path so edges and vias are read off exactly.
    private func search(
        from sources: Set<State>, to target: State, netIndex: Int, cols: Int, rows: Int,
        hEdgeOwner: [Int], vEdgeOwner: [Int], viaOwner: [Int],
        met3NodeOwner: [Int], met4NodeOwner: [Int]
    ) -> [State]? {
        func hOK(_ c: Int, _ r: Int) -> Bool { let o = hEdgeOwner[r * cols + c]; return o < 0 || o == netIndex }
        func vOK(_ c: Int, _ r: Int) -> Bool { let o = vEdgeOwner[r * cols + c]; return o < 0 || o == netIndex }
        func viaOK(_ c: Int, _ r: Int) -> Bool { let o = viaOwner[r * cols + c]; return o < 0 || o == netIndex }
        func nodeOK(_ state: State) -> Bool {
            let owner: Int
            switch state.layer {
            case .met3:
                owner = met3NodeOwner[state.node.r * cols + state.node.c]
            case .met4:
                owner = met4NodeOwner[state.node.r * cols + state.node.c]
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
            if cur.layer == .met3 {
                if c + 1 < cols && hOK(c, r) {
                    neighbors.append(State(node: Node(c: c + 1, r: r), layer: .met3))
                }
                if c - 1 >= 0 && hOK(c - 1, r) {
                    neighbors.append(State(node: Node(c: c - 1, r: r), layer: .met3))
                }
            } else {
                if r + 1 < rows && vOK(c, r) {
                    neighbors.append(State(node: Node(c: c, r: r + 1), layer: .met4))
                }
                if r - 1 >= 0 && vOK(c, r - 1) {
                    neighbors.append(State(node: Node(c: c, r: r - 1), layer: .met4))
                }
            }
            if viaOK(c, r) {
                neighbors.append(State(node: cur.node, layer: cur.layer == .met3 ? .met4 : .met3))
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
        met3NodeOwner: inout [Int], met4NodeOwner: inout [Int]
    ) {
        guard path.count >= 2 else { return }
        for state in path {
            _ = reserve(state, netIndex: netIndex, cols: cols,
                        met3NodeOwner: &met3NodeOwner,
                        met4NodeOwner: &met4NodeOwner)
        }
        for i in 1..<path.count {
            let a = path[i - 1], b = path[i]
            if a.node == b.node {                                  // layer switch -> via3
                viaOwner[a.node.r * cols + a.node.c] = netIndex
            } else if a.node.r == b.node.r {                       // horizontal -> met3 edge
                hEdgeOwner[a.node.r * cols + min(a.node.c, b.node.c)] = netIndex
            } else {                                               // vertical -> met4 edge
                vEdgeOwner[min(a.node.r, b.node.r) * cols + a.node.c] = netIndex
            }
        }
    }

    private func reserve(
        _ state: State,
        netIndex: Int,
        cols: Int,
        met3NodeOwner: inout [Int],
        met4NodeOwner: inout [Int]
    ) -> Bool {
        let index = state.node.r * cols + state.node.c
        switch state.layer {
        case .met3:
            guard met3NodeOwner[index] < 0 || met3NodeOwner[index] == netIndex else { return false }
            met3NodeOwner[index] = netIndex
        case .met4:
            guard met4NodeOwner[index] < 0 || met4NodeOwner[index] == netIndex else { return false }
            met4NodeOwner[index] = netIndex
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
                shapes.append(contentsOf: via2Drop(x: pin.x, y: pin.y, net: net).map { owned($0, by: net) })
                shapes.append(contentsOf: met3Jog(from: pin, toX: nodeX(node.c), toY: nodeY(node.r), net: net)
                    .map { owned($0, by: net) })
            }
        }

        for r in 0..<rows {
            for c in 0..<(cols - 1) {
                let owner = plan.hEdgeOwner[hIdx(c, r)]
                guard owner >= 0 else { continue }
                let net = nets[owner]
                shapes.append(owned(hMet3(nodeX(c), nodeX(c + 1), nodeY(r), net: net), by: net))
            }
        }
        for c in 0..<cols {
            for r in 0..<(rows - 1) {
                let owner = plan.vEdgeOwner[vIdx(c, r)]
                guard owner >= 0 else { continue }
                let net = nets[owner]
                shapes.append(owned(vMet4(nodeX(c), nodeY(r), nodeY(r + 1), net: net), by: net))
            }
        }
        for r in 0..<rows {
            for c in 0..<cols {
                let owner = plan.viaOwner[r * cols + c]
                guard owner >= 0 else { continue }
                let net = nets[owner]
                shapes.append(contentsOf: via3Drop(x: nodeX(c), y: nodeY(r), net: net).map { owned($0, by: net) })
            }
        }
        return shapes
    }

    private func rect(_ layer: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, net: Net) -> LayoutShape {
        LayoutShape(layer: Sky130LayoutTech.layer(layer),
                    netID: net.netID,
                    geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h))),
                    properties: [NetAwareLayoutEvaluator.netNameProperty: net.name])
    }
    private func hMet3(_ x0: Double, _ x1: Double, _ y: Double, net: Net) -> LayoutShape {
        rect("met3", min(x0, x1) - 0.15, y - 0.15, abs(x1 - x0) + 0.30, 0.30, net: net)
    }
    private func vMet4(_ x: Double, _ y0: Double, _ y1: Double, net: Net) -> LayoutShape {
        rect("met4", x - 0.15, min(y0, y1) - 0.15, 0.30, abs(y1 - y0) + 0.30, net: net)
    }
    private func via2Drop(x: Double, y: Double, net: Net) -> [LayoutShape] {
        [rect("met2", x - 0.185, y - 0.185, 0.37, 0.37, net: net),
         rect("via2", x - 0.10, y - 0.10, 0.20, 0.20, net: net),
         rect("met3", x - 0.25, y - 0.25, 0.50, 0.50, net: net)]
    }
    /// An L-shaped met3 jog joining a pin to its grid node (both on met3).
    private func met3Jog(from p: LayoutPoint, toX gx: Double, toY gy: Double, net: Net) -> [LayoutShape] {
        var shapes: [LayoutShape] = []
        if abs(gx - p.x) > 1e-6 { shapes.append(hMet3(p.x, gx, p.y, net: net)) }
        if abs(gy - p.y) > 1e-6 { shapes.append(vMet3(gx, p.y, gy, net: net)) }
        return shapes
    }
    private func vMet3(_ x: Double, _ y0: Double, _ y1: Double, net: Net) -> LayoutShape {
        rect("met3", x - 0.15, min(y0, y1) - 0.15, 0.30, abs(y1 - y0) + 0.30, net: net)
    }
    private func via3Drop(x: Double, y: Double, net: Net) -> [LayoutShape] {
        [rect("met3", x - 0.25, y - 0.25, 0.50, 0.50, net: net),
         rect("via3", x - 0.10, y - 0.10, 0.20, 0.20, net: net),
         rect("met4", x - 0.25, y - 0.25, 0.50, 0.50, net: net)]
    }
}
