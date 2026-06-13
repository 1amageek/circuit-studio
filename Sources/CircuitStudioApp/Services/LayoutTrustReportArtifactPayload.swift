import Foundation
import CircuitPhysicalDesign

extension LayoutTrustReport: ArtifactPayloadValidating {
    public func validateForPersistence() throws {
        _ = try JSONEncoder().encode(self)
    }
}
