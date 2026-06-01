import Foundation
import LayoutTech

public protocol NetAwareLayoutEvaluating: Sendable {
    func evaluate(
        shapes: [NetAwareLayoutEvaluator.OwnedShape],
        tech: LayoutTechDatabase
    ) -> NetAwareLayoutEvaluator.Report
}

extension NetAwareLayoutEvaluator: NetAwareLayoutEvaluating {}
