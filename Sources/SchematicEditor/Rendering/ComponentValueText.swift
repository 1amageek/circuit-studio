import Foundation
import CircuitStudioCore

/// Builds the value annotation drawn under a component name on the canvas
/// (e.g. "1kΩ" for a resistor, "W=10µm L=1µm" for a MOSFET). Driven entirely
/// by the device's parameter schema — no hardcoded device types.
public enum ComponentValueText {
    /// The annotation for a placed component, or `nil` when the device has
    /// nothing meaningful to show.
    public static func annotation(for component: PlacedComponent, kind: DeviceKind) -> String? {
        // An external model name identifies the part better than parameters.
        if let model = component.modelName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty {
            return model
        }

        let instanceParameters = kind.parameterSchema.filter { !$0.isModelParameter }
        let valued: [(schema: ParameterSchema, value: Double)] = instanceParameters.compactMap { schema in
            guard let value = component.parameters[schema.id] ?? schema.defaultValue else { return nil }
            return (schema, value)
        }

        let required = valued.filter { $0.schema.isRequired }
        if required.count == 1, let only = required.first {
            return EngineeringNotation.format(only.value, unit: only.schema.unit)
        }
        if !required.isEmpty {
            return required.prefix(2)
                .map { "\($0.schema.id.uppercased())=\(EngineeringNotation.format($0.value, unit: $0.schema.unit))" }
                .joined(separator: " ")
        }

        // Sources have no required parameters; the DC value is the headline.
        if let dc = valued.first(where: { $0.schema.id == "dc" }) {
            return EngineeringNotation.format(dc.value, unit: dc.schema.unit)
        }
        return nil
    }
}
