import Foundation
import LayoutCore
import LayoutTech

public protocol LayoutOwnershipResolving: Sendable {
    func resolve(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        policy: LayoutOwnershipPolicy
    ) throws -> LayoutOwnershipResolution
}

extension LayoutOwnershipResolver: LayoutOwnershipResolving {}
