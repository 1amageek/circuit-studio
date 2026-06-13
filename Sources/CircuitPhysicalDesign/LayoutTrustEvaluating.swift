import Foundation
import LayoutCore
import LayoutTech

public protocol LayoutTrustEvaluating: Sendable {
    func evaluate(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        policy: LayoutOwnershipPolicy
    ) throws -> LayoutTrustReport
}

extension LayoutTrustEvaluationService: LayoutTrustEvaluating {}
