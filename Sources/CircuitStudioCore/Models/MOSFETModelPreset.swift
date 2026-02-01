import Foundation

/// A reusable MOSFET model preset with named parameters.
///
/// Presets allow multiple MOSFET instances to share a single `.model` card
/// in the generated netlist. Each preset defines a complete set of model
/// parameters for a specific MOSFET type (NMOS or PMOS).
public struct MOSFETModelPreset: Sendable, Identifiable, Codable {
    public let id: String
    public let displayName: String
    public let description: String
    /// "NMOS" or "PMOS".
    public let modelType: String
    public let parameters: [String: Double]

    public init(
        id: String,
        displayName: String,
        description: String,
        modelType: String,
        parameters: [String: Double]
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.modelType = modelType
        self.parameters = parameters
    }
}
