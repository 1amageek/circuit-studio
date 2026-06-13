import Foundation
import LayoutCore
import LayoutTech
import LayoutVerify

/// Evaluates net-owned physical geometry directly, without relying on schematic metadata.
/// It is intended for generated route artifacts where every emitted shape claims exactly one
/// logical net. Same-layer contact and cut-layer bridges are treated as electrical connectivity.
public struct NetAwareLayoutEvaluator: Sendable {
    public static let netNameProperty = "layout.net.name"

    public struct OwnedShape: Sendable, Hashable, Codable {
        public let netName: String
        public let shape: LayoutShape

        public init(netName: String, shape: LayoutShape) {
            self.netName = netName
            self.shape = shape
        }
    }

    public struct PhysicalShort: Sendable, Hashable, Codable {
        public let netNames: [String]
        public let layer: LayoutLayerID
        public let region: LayoutRect
        public let shapeIDs: [UUID]

        public init(netNames: [String], layer: LayoutLayerID, region: LayoutRect, shapeIDs: [UUID]) {
            self.netNames = netNames
            self.layer = layer
            self.region = region
            self.shapeIDs = shapeIDs
        }
    }

    public struct PhysicalOpen: Sendable, Hashable, Codable {
        public let netName: String
        public let physicalNetCount: Int
        public let shapeIDs: [UUID]

        public init(netName: String, physicalNetCount: Int, shapeIDs: [UUID]) {
            self.netName = netName
            self.physicalNetCount = physicalNetCount
            self.shapeIDs = shapeIDs
        }
    }

    public struct UnownedShape: Sendable, Hashable, Codable {
        public let shapeID: UUID
        public let layer: LayoutLayerID

        public init(shapeID: UUID, layer: LayoutLayerID) {
            self.shapeID = shapeID
            self.layer = layer
        }
    }

    public struct Report: Sendable, Hashable, Codable {
        public let shorts: [PhysicalShort]
        public let opens: [PhysicalOpen]
        public let unownedShapes: [UnownedShape]

        public init(
            shorts: [PhysicalShort],
            opens: [PhysicalOpen],
            unownedShapes: [UnownedShape]
        ) {
            self.shorts = shorts
            self.opens = opens
            self.unownedShapes = unownedShapes
        }

        public var passed: Bool {
            shorts.isEmpty && opens.isEmpty && unownedShapes.isEmpty
        }

        public var summary: String {
            if passed { return "net-aware layout evaluation passed" }
            return "\(shorts.count) short(s), \(opens.count) open(s), \(unownedShapes.count) unowned shape(s)"
        }
    }

    public init() {}

    public func evaluate(shapes: [OwnedShape], tech: LayoutTechDatabase) -> Report {
        guard !shapes.isEmpty else {
            return Report(shorts: [], opens: [], unownedShapes: [])
        }

        var unownedShapes: [UnownedShape] = []
        let elements = shapes.compactMap { ownedShape -> EvaluationElement? in
            guard !ownedShape.netName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                unownedShapes.append(UnownedShape(shapeID: ownedShape.shape.id, layer: ownedShape.shape.layer))
                return nil
            }
            return EvaluationElement(
                netName: ownedShape.netName,
                shape: ownedShape.shape,
                bridge: bridge(for: ownedShape.shape.layer, tech: tech)
            )
        }

        var unionFind = LayoutUnionFind(count: elements.count)
        var shortsByKey: [ShortKey: PhysicalShort] = [:]

        if elements.count >= 2 {
            for i in 0..<(elements.count - 1) {
                for j in (i + 1)..<elements.count {
                    guard connects(elements[i], elements[j]) else { continue }
                    if elements[i].netName == elements[j].netName {
                        unionFind.union(i, j)
                    } else {
                        let short = makeShort(elements[i], elements[j])
                        shortsByKey[ShortKey(short)] = short
                    }
                }
            }
        }

        var componentIDsByNet: [String: Set<Int>] = [:]
        var shapeIDsByNet: [String: [UUID]] = [:]
        for index in elements.indices {
            let root = unionFind.find(index)
            componentIDsByNet[elements[index].netName, default: []].insert(root)
            shapeIDsByNet[elements[index].netName, default: []].append(elements[index].shape.id)
        }

        let opens = componentIDsByNet.compactMap { netName, componentIDs -> PhysicalOpen? in
            guard componentIDs.count > 1 else { return nil }
            return PhysicalOpen(
                netName: netName,
                physicalNetCount: componentIDs.count,
                shapeIDs: shapeIDsByNet[netName, default: []].sorted { $0.uuidString < $1.uuidString }
            )
        }
        .sorted { lhs, rhs in
            if lhs.netName != rhs.netName { return lhs.netName < rhs.netName }
            return lhs.physicalNetCount < rhs.physicalNetCount
        }

        return Report(
            shorts: shortsByKey.values.sorted(by: compareShorts),
            opens: opens,
            unownedShapes: sortedUnownedShapes(unownedShapes)
        )
    }

    public func evaluateTaggedShapes(
        _ shapes: [LayoutShape],
        tech: LayoutTechDatabase,
        netNameProperty: String = NetAwareLayoutEvaluator.netNameProperty
    ) -> Report {
        var ownedShapes: [OwnedShape] = []
        var unownedShapes: [UnownedShape] = []
        for shape in shapes {
            guard let netName = shape.properties[netNameProperty], !netName.isEmpty else {
                unownedShapes.append(UnownedShape(shapeID: shape.id, layer: shape.layer))
                continue
            }
            ownedShapes.append(OwnedShape(netName: netName, shape: shape))
        }

        let report = evaluate(shapes: ownedShapes, tech: tech)
        return Report(
            shorts: report.shorts,
            opens: report.opens,
            unownedShapes: sortedUnownedShapes(report.unownedShapes + unownedShapes)
        )
    }

    private func bridge(
        for layer: LayoutLayerID,
        tech: LayoutTechDatabase
    ) -> LayerBridge? {
        if let via = tech.vias.first(where: { $0.cutLayer == layer }) {
            return LayerBridge(top: via.topLayer, bottom: via.bottomLayer)
        }
        if let contact = tech.contacts.first(where: { $0.cutLayer == layer }) {
            return LayerBridge(top: contact.topLayer, bottom: contact.bottomLayer)
        }
        return nil
    }

    private func connects(_ lhs: EvaluationElement, _ rhs: EvaluationElement) -> Bool {
        if lhs.isBridge || rhs.isBridge {
            return bridgeConnects(lhs, rhs)
        }
        guard lhs.shape.layer == rhs.shape.layer else { return false }
        return geometriesTouch(lhs.shape.geometry, rhs.shape.geometry)
    }

    private func bridgeConnects(_ lhs: EvaluationElement, _ rhs: EvaluationElement) -> Bool {
        guard lhs.isBridge != rhs.isBridge else { return false }
        let bridgeElement = lhs.isBridge ? lhs : rhs
        let conductor = lhs.isBridge ? rhs : lhs
        guard let bridge = bridgeElement.bridge else { return false }
        guard conductor.shape.layer == bridge.top || conductor.shape.layer == bridge.bottom else {
            return false
        }
        return geometriesTouch(bridgeElement.shape.geometry, conductor.shape.geometry)
    }

    private func geometriesTouch(_ lhs: LayoutGeometry, _ rhs: LayoutGeometry) -> Bool {
        let lhsBox = LayoutGeometryAnalysis.boundingBox(for: lhs)
        let rhsBox = LayoutGeometryAnalysis.boundingBox(for: rhs)
        guard lhsBox.intersects(rhsBox) else { return false }
        if LayoutGeometryAnalysis.intersects(lhs, rhs) { return true }
        if LayoutGeometryAnalysis.contains(lhsBox.center, in: rhs) { return true }
        if LayoutGeometryAnalysis.contains(rhsBox.center, in: lhs) { return true }
        return false
    }

    private func makeShort(_ lhs: EvaluationElement, _ rhs: EvaluationElement) -> PhysicalShort {
        let netNames = [lhs.netName, rhs.netName].sorted()
        let region = LayoutGeometryAnalysis.boundingBox(for: lhs.shape.geometry)
            .union(LayoutGeometryAnalysis.boundingBox(for: rhs.shape.geometry))
        let shapeIDs = [lhs.shape.id, rhs.shape.id].sorted { $0.uuidString < $1.uuidString }
        return PhysicalShort(
            netNames: netNames,
            layer: shortLayer(lhs, rhs),
            region: region,
            shapeIDs: shapeIDs
        )
    }

    private func shortLayer(_ lhs: EvaluationElement, _ rhs: EvaluationElement) -> LayoutLayerID {
        if !lhs.isBridge { return lhs.shape.layer }
        if !rhs.isBridge { return rhs.shape.layer }
        return lhs.shape.layer
    }

    private func compareShorts(_ lhs: PhysicalShort, _ rhs: PhysicalShort) -> Bool {
        let lhsName = lhs.netNames.joined(separator: ",")
        let rhsName = rhs.netNames.joined(separator: ",")
        if lhsName != rhsName { return lhsName < rhsName }
        if lhs.layer.name != rhs.layer.name { return lhs.layer.name < rhs.layer.name }
        return lhs.shapeIDs.map(\.uuidString).joined(separator: ",") < rhs.shapeIDs.map(\.uuidString).joined(separator: ",")
    }

    private func sortedUnownedShapes(_ shapes: [UnownedShape]) -> [UnownedShape] {
        shapes.sorted {
            if $0.layer.name != $1.layer.name { return $0.layer.name < $1.layer.name }
            return $0.shapeID.uuidString < $1.shapeID.uuidString
        }
    }
}

private struct EvaluationElement: Sendable, Hashable {
    let netName: String
    let shape: LayoutShape
    let bridge: LayerBridge?

    var isBridge: Bool { bridge != nil }
}

private struct LayerBridge: Sendable, Hashable {
    let top: LayoutLayerID
    let bottom: LayoutLayerID
}

private struct ShortKey: Sendable, Hashable {
    let netNames: [String]
    let shapeIDs: [UUID]

    init(_ short: NetAwareLayoutEvaluator.PhysicalShort) {
        self.netNames = short.netNames
        self.shapeIDs = short.shapeIDs
    }
}
