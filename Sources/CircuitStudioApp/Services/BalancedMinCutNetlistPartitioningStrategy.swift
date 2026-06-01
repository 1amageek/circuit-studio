import Foundation

/// Deterministic balanced graph partitioning for gate-level netlists.
///
/// The strategy converts each signal net into weighted connectivity between instances. A balanced
/// connectivity order gives the initial assignment, then bounded move/swap refinement reduces the
/// weighted edge cut without changing block size limits.
public struct BalancedMinCutNetlistPartitioningStrategy: NetlistPartitioningStrategy {

    public enum PartitioningError: Error, LocalizedError, Equatable {
        case nonPositiveBlocks

        public var errorDescription: String? {
            switch self {
            case .nonPositiveBlocks: return "Balanced min-cut partitioning needs blockCount >= 1."
            }
        }
    }

    private struct EdgeKey: Hashable, Sendable {
        let lhs: Int
        let rhs: Int

        init(_ a: Int, _ b: Int) {
            self.lhs = min(a, b)
            self.rhs = max(a, b)
        }
    }

    private struct WeightedGraph: Sendable {
        let adjacency: [[Int: Int]]
    }

    private struct Candidate: Sendable {
        enum Action: Sendable {
            case move(index: Int, to: Int)
            case swap(lhs: Int, rhs: Int)
        }

        let gain: Int
        let key: [Int]
        let action: Action
    }

    public init() {}

    public func assignment(for netlist: GateLevelNetlist, blockCount: Int, rails: Set<String>) throws -> [Int] {
        guard blockCount >= 1 else { throw PartitioningError.nonPositiveBlocks }
        let instanceCount = netlist.instances.count
        guard instanceCount > 0 else { return [] }
        let activeBlockCount = min(blockCount, instanceCount)
        guard activeBlockCount > 1 else { return Array(repeating: 0, count: instanceCount) }

        let graph = weightedGraph(for: netlist, rails: rails)
        return refinedAssignment(instanceCount: instanceCount, blockCount: activeBlockCount, graph: graph)
    }

    private func weightedGraph(for netlist: GateLevelNetlist, rails: Set<String>) -> WeightedGraph {
        let instances = netlist.instances
        let driverOf = Dictionary(
            instances.enumerated().map { (netlist.driverNet(of: $1), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var touchedByNet: [String: Set<Int>] = [:]
        var consumersByNet: [String: Set<Int>] = [:]

        for (index, inst) in instances.enumerated() {
            let drivenNet = netlist.driverNet(of: inst)
            if !rails.contains(drivenNet) {
                touchedByNet[drivenNet, default: []].insert(index)
            }
            for gate in Set(inst.cell.devices.map(\.gate)) {
                let net = inst.net(gate)
                guard !rails.contains(net) else { continue }
                touchedByNet[net, default: []].insert(index)
                consumersByNet[net, default: []].insert(index)
            }
        }

        var edgeWeights: [EdgeKey: Int] = [:]
        for net in touchedByNet.keys.sorted() {
            let participants = (touchedByNet[net] ?? []).sorted()
            guard participants.count > 1 else { continue }

            for (offset, lhs) in participants.enumerated() {
                for rhs in participants.dropFirst(offset + 1) {
                    addEdge(lhs, rhs, weight: 1, edgeWeights: &edgeWeights)
                }
            }
            if let driver = driverOf[net] {
                for sink in consumersByNet[net] ?? [] where sink != driver {
                    addEdge(driver, sink, weight: 3, edgeWeights: &edgeWeights)
                }
            }
        }

        var adjacency = Array(repeating: [Int: Int](), count: instances.count)
        for (key, weight) in edgeWeights.sorted(by: {
            $0.key.lhs != $1.key.lhs ? $0.key.lhs < $1.key.lhs : $0.key.rhs < $1.key.rhs
        }) {
            adjacency[key.lhs][key.rhs] = weight
            adjacency[key.rhs][key.lhs] = weight
        }
        return WeightedGraph(adjacency: adjacency)
    }

    private func addEdge(_ lhs: Int, _ rhs: Int, weight: Int, edgeWeights: inout [EdgeKey: Int]) {
        edgeWeights[EdgeKey(lhs, rhs), default: 0] += weight
    }

    private func refinedAssignment(instanceCount n: Int, blockCount k: Int, graph: WeightedGraph) -> [Int] {
        var assignment = initialAssignment(instanceCount: n, blockCount: k, adjacency: graph.adjacency)
        var sizes = blockSizes(assignment, blockCount: k)
        let minSize = n / k
        let maxSize = (n + k - 1) / k
        let passLimit = min(max(4, k * 4), 32)

        for _ in 0..<passLimit {
            var best: Candidate?

            for index in 0..<n {
                let from = assignment[index]
                guard sizes[from] > minSize else { continue }
                for to in 0..<k where to != from && sizes[to] < maxSize {
                    let gain = moveGain(index: index, to: to, assignment: assignment, adjacency: graph.adjacency)
                    consider(Candidate(gain: gain, key: [0, index, to], action: .move(index: index, to: to)),
                             best: &best)
                }
            }

            for lhs in 0..<n {
                for rhs in (lhs + 1)..<n where assignment[lhs] != assignment[rhs] {
                    let gain = swapGain(lhs: lhs, rhs: rhs, assignment: assignment, adjacency: graph.adjacency)
                    consider(Candidate(gain: gain, key: [1, lhs, rhs], action: .swap(lhs: lhs, rhs: rhs)),
                             best: &best)
                }
            }

            guard let winner = best, winner.gain > 0 else { break }
            apply(winner.action, assignment: &assignment, sizes: &sizes)
        }
        return assignment
    }

    private func initialAssignment(instanceCount n: Int, blockCount k: Int, adjacency: [[Int: Int]]) -> [Int] {
        let order = connectivityOrder(instanceCount: n, adjacency: adjacency)
        var capacities = (0..<k).map { block in
            (n / k) + (block < (n % k) ? 1 : 0)
        }
        var block = 0
        var assignment = Array(repeating: 0, count: n)
        for instanceIndex in order {
            while block < k - 1 && capacities[block] == 0 {
                block += 1
            }
            assignment[instanceIndex] = block
            capacities[block] -= 1
        }
        return assignment
    }

    private func connectivityOrder(instanceCount n: Int, adjacency: [[Int: Int]]) -> [Int] {
        var order: [Int] = []
        var visited = Set<Int>()
        for seed in 0..<n where !visited.contains(seed) {
            var queue = [seed]
            visited.insert(seed)
            var head = 0
            while head < queue.count {
                let current = queue[head]
                head += 1
                order.append(current)
                let neighbors = adjacency[current].sorted {
                    $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
                }
                for next in neighbors.map(\.key) where !visited.contains(next) {
                    visited.insert(next)
                    queue.append(next)
                }
            }
        }
        return order
    }

    private func moveGain(index: Int, to targetBlock: Int, assignment: [Int], adjacency: [[Int: Int]]) -> Int {
        let sourceBlock = assignment[index]
        var gain = 0
        for (neighbor, weight) in adjacency[index] {
            let neighborBlock = assignment[neighbor]
            if neighborBlock == sourceBlock {
                gain -= weight
            } else if neighborBlock == targetBlock {
                gain += weight
            }
        }
        return gain
    }

    private func swapGain(lhs: Int, rhs: Int, assignment: [Int], adjacency: [[Int: Int]]) -> Int {
        let lhsBlock = assignment[lhs]
        let rhsBlock = assignment[rhs]
        var visited = Set<EdgeKey>()
        var gain = 0

        func blockAfterSwap(_ index: Int) -> Int {
            if index == lhs { return rhsBlock }
            if index == rhs { return lhsBlock }
            return assignment[index]
        }

        func visit(_ a: Int, _ b: Int, _ weight: Int) {
            let key = EdgeKey(a, b)
            guard !visited.contains(key) else { return }
            visited.insert(key)
            let before = assignment[a] == assignment[b] ? 0 : weight
            let after = blockAfterSwap(a) == blockAfterSwap(b) ? 0 : weight
            gain += before - after
        }

        for (neighbor, weight) in adjacency[lhs] {
            visit(lhs, neighbor, weight)
        }
        for (neighbor, weight) in adjacency[rhs] {
            visit(rhs, neighbor, weight)
        }
        return gain
    }

    private func consider(_ candidate: Candidate, best: inout Candidate?) {
        guard candidate.gain > 0 else { return }
        if let existing = best {
            if candidate.gain > existing.gain ||
                (candidate.gain == existing.gain && candidate.key.lexicographicallyPrecedes(existing.key)) {
                best = candidate
            }
        } else {
            best = candidate
        }
    }

    private func apply(_ action: Candidate.Action, assignment: inout [Int], sizes: inout [Int]) {
        switch action {
        case let .move(index, to):
            let from = assignment[index]
            assignment[index] = to
            sizes[from] -= 1
            sizes[to] += 1
        case let .swap(lhs, rhs):
            let lhsBlock = assignment[lhs]
            assignment[lhs] = assignment[rhs]
            assignment[rhs] = lhsBlock
        }
    }

    private func blockSizes(_ assignment: [Int], blockCount: Int) -> [Int] {
        assignment.reduce(into: Array(repeating: 0, count: blockCount)) { sizes, block in
            sizes[block] += 1
        }
    }
}
