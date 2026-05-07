import Foundation
import CoreGraphics

/// An extracted net with its name and connected pins.
public struct ExtractedNet: Sendable {
    public let name: String
    public var connections: [PinReference]

    public init(name: String, connections: [PinReference] = []) {
        self.name = name
        self.connections = connections
    }
}

/// Extracts net connectivity from a SchematicDocument.
///
/// Traces wires via PinReference endpoints and groups them into nets.
/// Wire endpoints sharing the same point (junction) or connected via NetLabels
/// are merged into a single net.
public struct NetExtractor: Sendable {

    public init() {}

    /// Extract nets from a schematic document.
    public func extract(from document: SchematicDocument) -> [ExtractedNet] {
        // Build union-find over wire endpoints to group connected wires
        var wireGroups = UnionFind()
        let wires = document.wires

        // Assign each wire endpoint an index: wire[i].start = 2*i, wire[i].end = 2*i+1
        for i in wires.indices {
            wireGroups.makeSet(2 * i)
            wireGroups.makeSet(2 * i + 1)
        }

        // Merge endpoints at the same grid position (junction)
        var pointToEndpoint: [PointKey: Int] = [:]
        for i in wires.indices {
            let startKey = PointKey(wires[i].startPoint)
            let endKey = PointKey(wires[i].endPoint)

            if let existing = pointToEndpoint[startKey] {
                wireGroups.union(existing, 2 * i)
            } else {
                pointToEndpoint[startKey] = 2 * i
            }

            if let existing = pointToEndpoint[endKey] {
                wireGroups.union(existing, 2 * i + 1)
            } else {
                pointToEndpoint[endKey] = 2 * i + 1
            }
        }

        // Merge each wire's start and end endpoints (a wire connects its own two endpoints)
        for i in wires.indices {
            wireGroups.union(2 * i, 2 * i + 1)
        }

        // Merge geometric connections that may exist in loaded or programmatically-built schematics.
        // The editor usually splits T-junctions as wires are drawn, but imported data can contain
        // unsplit endpoint-to-segment contacts or overlapping collinear wire segments.
        for i in wires.indices {
            for j in wires.indices where i < j {
                if wiresShareConductivePoint(wires[i], wires[j]) {
                    wireGroups.union(2 * i, 2 * j)
                }
            }
        }

        // Merge disconnected wire groups that share the same explicit net label name.
        var labelNameToEndpoint: [String: Int] = [:]
        for label in document.labels {
            let name = label.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let endpointIdx = endpointIndex(for: label.position, in: wires) else {
                continue
            }
            if let existing = labelNameToEndpoint[name] {
                wireGroups.union(existing, endpointIdx)
            } else {
                labelNameToEndpoint[name] = endpointIdx
            }
        }

        // Collect nets by group
        var groupToNet: [Int: (name: String?, pins: [PinReference])] = [:]

        for i in wires.indices {
            let wire = wires[i]

            // Start endpoint
            let startGroup = wireGroups.find(2 * i)
            if groupToNet[startGroup] == nil {
                groupToNet[startGroup] = (name: nil, pins: [])
            }
            if let ref = wire.startPin {
                if !groupToNet[startGroup]!.pins.contains(ref) {
                    groupToNet[startGroup]!.pins.append(ref)
                }
            }
            if let name = wire.netName, groupToNet[startGroup]!.name == nil {
                groupToNet[startGroup]!.name = name
            }

            // End endpoint
            let endGroup = wireGroups.find(2 * i + 1)
            if groupToNet[endGroup] == nil {
                groupToNet[endGroup] = (name: nil, pins: [])
            }
            if let ref = wire.endPin {
                if !groupToNet[endGroup]!.pins.contains(ref) {
                    groupToNet[endGroup]!.pins.append(ref)
                }
            }
            if let name = wire.netName, groupToNet[endGroup]!.name == nil {
                groupToNet[endGroup]!.name = name
            }
        }

        // Merge nets that share the same group root (start/end already merged by union-find)
        // Assign net labels from document.labels based on position proximity
        for label in document.labels {
            let name = label.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let endpointIdx = endpointIndex(for: label.position, in: wires) else {
                continue
            }
            let group = wireGroups.find(endpointIdx)
            if groupToNet[group] != nil {
                groupToNet[group]!.name = name
            }
        }

        // Build final nets, auto-naming unnamed ones
        var nets: [ExtractedNet] = []
        var autoNetCounter = 0
        for (_, value) in groupToNet.sorted(by: { $0.key < $1.key }) {
            guard !value.pins.isEmpty else { continue }
            let name: String
            if let explicitName = value.name {
                name = explicitName
            } else {
                name = "net\(autoNetCounter)"
                autoNetCounter += 1
            }
            nets.append(ExtractedNet(name: name, connections: value.pins))
        }

        // Check for ground components — any pin connected to a ground component gets net name "0"
        let groundIDs = Set(document.components.filter { $0.deviceKindID == "ground" }.map(\.id))
        for i in nets.indices {
            if nets[i].connections.contains(where: { groundIDs.contains($0.componentID) }) {
                nets[i] = ExtractedNet(name: "0", connections: nets[i].connections)
            }
        }

        return nets
    }
}

// MARK: - Helpers

/// Hashable point key with grid-snapped precision.
private struct PointKey: Hashable {
    let x: Int
    let y: Int

    init(_ point: CGPoint) {
        // Round to nearest integer to handle floating-point imprecision
        self.x = Int(round(point.x))
        self.y = Int(round(point.y))
    }
}

private func endpointIndex(for point: CGPoint, in wires: [Wire]) -> Int? {
    let key = PointKey(point)
    for i in wires.indices {
        if PointKey(wires[i].startPoint) == key {
            return 2 * i
        }
        if PointKey(wires[i].endPoint) == key {
            return 2 * i + 1
        }
    }

    for i in wires.indices {
        if pointOnAxisAlignedSegment(point, from: wires[i].startPoint, to: wires[i].endPoint) {
            return 2 * i
        }
    }
    return nil
}

private func wiresShareConductivePoint(_ lhs: Wire, _ rhs: Wire) -> Bool {
    pointOnAxisAlignedSegment(lhs.startPoint, from: rhs.startPoint, to: rhs.endPoint)
        || pointOnAxisAlignedSegment(lhs.endPoint, from: rhs.startPoint, to: rhs.endPoint)
        || pointOnAxisAlignedSegment(rhs.startPoint, from: lhs.startPoint, to: lhs.endPoint)
        || pointOnAxisAlignedSegment(rhs.endPoint, from: lhs.startPoint, to: lhs.endPoint)
}

private func pointOnAxisAlignedSegment(_ point: CGPoint, from: CGPoint, to: CGPoint) -> Bool {
    let pointKey = PointKey(point)
    let fromKey = PointKey(from)
    let toKey = PointKey(to)

    if fromKey == toKey {
        return pointKey == fromKey
    }

    if fromKey.y == toKey.y {
        guard pointKey.y == fromKey.y else { return false }
        return pointKey.x >= min(fromKey.x, toKey.x)
            && pointKey.x <= max(fromKey.x, toKey.x)
    }

    if fromKey.x == toKey.x {
        guard pointKey.x == fromKey.x else { return false }
        return pointKey.y >= min(fromKey.y, toKey.y)
            && pointKey.y <= max(fromKey.y, toKey.y)
    }

    return false
}

/// Simple union-find (disjoint set) data structure.
private struct UnionFind {
    private var parent: [Int: Int] = [:]
    private var rank: [Int: Int] = [:]

    mutating func makeSet(_ x: Int) {
        if parent[x] == nil {
            parent[x] = x
            rank[x] = 0
        }
    }

    mutating func find(_ x: Int) -> Int {
        guard let p = parent[x] else { return x }
        if p != x {
            parent[x] = find(p)
        }
        return parent[x]!
    }

    mutating func union(_ x: Int, _ y: Int) {
        let rx = find(x)
        let ry = find(y)
        guard rx != ry else { return }
        let rankX = rank[rx] ?? 0
        let rankY = rank[ry] ?? 0
        if rankX < rankY {
            parent[rx] = ry
        } else if rankX > rankY {
            parent[ry] = rx
        } else {
            parent[ry] = rx
            rank[rx] = rankX + 1
        }
    }
}
