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

        public var errorDescription: String? {
            switch self {
            case .unroutable(let n): return "Maze router could not find a path for net '\(n)'."
            case .emptyNets: return "Maze router was given no nets to route."
            }
        }
    }

    public struct Net: Sendable, Hashable {
        public let name: String
        public let pins: [LayoutPoint]
        public init(name: String, pins: [LayoutPoint]) { self.name = name; self.pins = pins }
    }

    private let pitch: Double
    private let margin: Double

    public init(pitch: Double = 0.9, margin: Double = 1.4) {
        self.pitch = pitch   // >= 0.50 (via pad) + 0.30 (met3/met4 spacing) so pads never clash
        self.margin = margin
    }

    // A grid node.
    private struct Node: Hashable { let c: Int; let r: Int }
    private enum Layer: Hashable { case met3, met4 }   // met3 = horizontal, met4 = vertical

    public func route(_ nets: [Net]) throws -> [LayoutShape] {
        guard !nets.isEmpty else { throw MazeError.emptyNets }
        let allPins = nets.flatMap(\.pins)
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

        // Occupancy across all nets: which net owns each met3 horizontal edge, met4 vertical
        // edge, and via3 node. -1 = free.
        var hEdgeOwner = [Int](repeating: -1, count: cols * rows)   // edge (c,r)-(c+1,r), met3
        var vEdgeOwner = [Int](repeating: -1, count: cols * rows)   // edge (c,r)-(c,r+1), met4
        var viaOwner = [Int](repeating: -1, count: cols * rows)     // via3 at node (c,r)
        func hIdx(_ c: Int, _ r: Int) -> Int { r * cols + c }
        func vIdx(_ c: Int, _ r: Int) -> Int { r * cols + c }

        var shapes: [LayoutShape] = []
        var pinNodes: [Net: [Node]] = [:]
        for net in nets { pinNodes[net] = net.pins.map(snap) }

        for (netIndex, net) in nets.enumerated() {
            guard let terminals = pinNodes[net], let first = terminals.first else { continue }
            var inTree = Set([first])
            for target in terminals.dropFirst() where !inTree.contains(target) {
                let path = search(from: inTree, to: target, netIndex: netIndex, cols: cols, rows: rows,
                                  hEdgeOwner: hEdgeOwner, vEdgeOwner: vEdgeOwner, viaOwner: viaOwner)
                guard let path else { throw MazeError.unroutable(net: net.name) }
                commit(path, netIndex: netIndex, cols: cols,
                       hEdgeOwner: &hEdgeOwner, vEdgeOwner: &vEdgeOwner, viaOwner: &viaOwner)
                for state in path { inTree.insert(state.node) }
            }
            // Connect each pin to the grid: via2 (met2->met3) at the pin's REAL position, then
            // a met3 jog up to its snapped grid node where the maze route attaches.
            for pin in net.pins {
                let node = snap(pin)
                shapes.append(contentsOf: via2Drop(x: pin.x, y: pin.y))
                shapes.append(contentsOf: met3Jog(from: pin, toX: nodeX(node.c), toY: nodeY(node.r)))
            }
        }

        // Emit wire/via geometry from the committed occupancy.
        for r in 0..<rows {
            for c in 0..<(cols - 1) where hEdgeOwner[hIdx(c, r)] >= 0 {
                shapes.append(hMet3(nodeX(c), nodeX(c + 1), nodeY(r)))
            }
        }
        for c in 0..<cols {
            for r in 0..<(rows - 1) where vEdgeOwner[vIdx(c, r)] >= 0 {
                shapes.append(vMet4(nodeX(c), nodeY(r), nodeY(r + 1)))
            }
        }
        for r in 0..<rows {
            for c in 0..<cols where viaOwner[r * cols + c] >= 0 {
                shapes.append(contentsOf: via3Drop(x: nodeX(c), y: nodeY(r)))
            }
        }
        return shapes
    }

    // MARK: - search

    private struct State: Hashable { let node: Node; let layer: Layer }

    /// BFS over (node, layer); pins live on met3, so the search both starts and ends on met3.
    /// Horizontal moves use met3 edges, vertical use met4 edges, and a layer switch at a node
    /// costs a via3 — avoiding any edge/via already owned by another net. Returns the full
    /// (node, layer) path so edges and vias are read off exactly.
    private func search(
        from sources: Set<Node>, to target: Node, netIndex: Int, cols: Int, rows: Int,
        hEdgeOwner: [Int], vEdgeOwner: [Int], viaOwner: [Int]
    ) -> [State]? {
        func hOK(_ c: Int, _ r: Int) -> Bool { let o = hEdgeOwner[r * cols + c]; return o < 0 || o == netIndex }
        func vOK(_ c: Int, _ r: Int) -> Bool { let o = vEdgeOwner[r * cols + c]; return o < 0 || o == netIndex }
        func viaOK(_ c: Int, _ r: Int) -> Bool { let o = viaOwner[r * cols + c]; return o < 0 || o == netIndex }

        var prev: [State: State] = [:]
        var visited = Set<State>()
        var queue: [State] = []
        for s in sources {
            let st = State(node: s, layer: .met3)   // pins are on met3
            visited.insert(st); queue.append(st)
        }
        var head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            if cur.node == target && cur.layer == .met3 { return reconstruct(cur, prev: prev) }
            let c = cur.node.c, r = cur.node.r
            var neighbors: [State] = []
            if cur.layer == .met3 {
                if c + 1 < cols && hOK(c, r) { neighbors.append(State(node: Node(c: c + 1, r: r), layer: .met3)) }
                if c - 1 >= 0 && hOK(c - 1, r) { neighbors.append(State(node: Node(c: c - 1, r: r), layer: .met3)) }
            } else {
                if r + 1 < rows && vOK(c, r) { neighbors.append(State(node: Node(c: c, r: r + 1), layer: .met4)) }
                if r - 1 >= 0 && vOK(c, r - 1) { neighbors.append(State(node: Node(c: c, r: r - 1), layer: .met4)) }
            }
            if viaOK(c, r) { neighbors.append(State(node: cur.node, layer: cur.layer == .met3 ? .met4 : .met3)) }
            for nb in neighbors where !visited.contains(nb) {
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
        hEdgeOwner: inout [Int], vEdgeOwner: inout [Int], viaOwner: inout [Int]
    ) {
        guard path.count >= 2 else { return }
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

    // MARK: - geometry

    private func rect(_ layer: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutShape {
        LayoutShape(layer: Sky130LayoutTech.layer(layer),
                    geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h))))
    }
    private func hMet3(_ x0: Double, _ x1: Double, _ y: Double) -> LayoutShape {
        rect("met3", min(x0, x1) - 0.15, y - 0.15, abs(x1 - x0) + 0.30, 0.30)
    }
    private func vMet4(_ x: Double, _ y0: Double, _ y1: Double) -> LayoutShape {
        rect("met4", x - 0.15, min(y0, y1) - 0.15, 0.30, abs(y1 - y0) + 0.30)
    }
    private func via2Drop(x: Double, y: Double) -> [LayoutShape] {
        [rect("met2", x - 0.185, y - 0.185, 0.37, 0.37),
         rect("via2", x - 0.10, y - 0.10, 0.20, 0.20),
         rect("met3", x - 0.25, y - 0.25, 0.50, 0.50)]
    }
    /// An L-shaped met3 jog joining a pin to its grid node (both on met3).
    private func met3Jog(from p: LayoutPoint, toX gx: Double, toY gy: Double) -> [LayoutShape] {
        var shapes: [LayoutShape] = []
        if abs(gx - p.x) > 1e-6 { shapes.append(hMet3(p.x, gx, p.y)) }
        if abs(gy - p.y) > 1e-6 { shapes.append(vMet3(gx, p.y, gy)) }
        return shapes
    }
    private func vMet3(_ x: Double, _ y0: Double, _ y1: Double) -> LayoutShape {
        rect("met3", x - 0.15, min(y0, y1) - 0.15, 0.30, abs(y1 - y0) + 0.30)
    }
    private func via3Drop(x: Double, y: Double) -> [LayoutShape] {
        [rect("met3", x - 0.25, y - 0.25, 0.50, 0.50),
         rect("via3", x - 0.10, y - 0.10, 0.20, 0.20),
         rect("met4", x - 0.25, y - 0.25, 0.50, 0.50)]
    }
}
