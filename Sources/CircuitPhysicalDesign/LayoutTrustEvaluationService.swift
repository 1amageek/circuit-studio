import Foundation
import LayoutCore
import LayoutTech

public struct LayoutTrustEvaluationService: Sendable {
    private let ownershipResolver: any LayoutOwnershipResolving
    private let netAwareEvaluator: any NetAwareLayoutEvaluating

    public init(
        ownershipResolver: any LayoutOwnershipResolving = LayoutOwnershipResolver(),
        netAwareEvaluator: any NetAwareLayoutEvaluating = NetAwareLayoutEvaluator()
    ) {
        self.ownershipResolver = ownershipResolver
        self.netAwareEvaluator = netAwareEvaluator
    }

    public func evaluate(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        policy: LayoutOwnershipPolicy = LayoutOwnershipPolicy()
    ) throws -> LayoutTrustReport {
        let resolution = try ownershipResolver.resolve(document: document, tech: tech, policy: policy)
        let topologyReport = netAwareEvaluator.evaluate(shapes: resolution.ownedShapes, tech: tech)
        let report = NetAwareLayoutEvaluator.Report(
            shorts: topologyReport.shorts,
            opens: topologyReport.opens,
            unownedShapes: sortedUnownedShapes(topologyReport.unownedShapes + resolution.unownedShapes)
        )
        return LayoutTrustReport(
            topCellName: resolution.ownershipMap.topCellName,
            ownershipMap: resolution.ownershipMap,
            netAwareReport: report
        )
    }

    private func sortedUnownedShapes(
        _ shapes: [NetAwareLayoutEvaluator.UnownedShape]
    ) -> [NetAwareLayoutEvaluator.UnownedShape] {
        shapes.sorted {
            if $0.layer.name != $1.layer.name { return $0.layer.name < $1.layer.name }
            return $0.shapeID.uuidString < $1.shapeID.uuidString
        }
    }
}
