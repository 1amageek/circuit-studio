import Foundation
import CircuitStudioCore

/// Builds the value annotation drawn under a component name on the canvas
/// (e.g. "1kΩ" for a resistor, "W=10µm L=1µm" for a MOSFET). Driven entirely
/// by the device's parameter schema — no hardcoded device types.
public enum ComponentValueText {
    /// The annotation for a placed component, or `nil` when the device has
    /// nothing meaningful to show.
    public static func annotation(for component: PlacedComponent, kind: DeviceKind) -> String? {
        let model = component.modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let model, !model.isEmpty {
            return model
        }

        let instanceParameters = kind.parameterSchema.filter { !$0.isModelParameter }
        let valued: [(schema: ParameterSchema, value: Double)] = instanceParameters.compactMap { schema in
            guard let value = component.parameters[schema.id] ?? schema.defaultValue else { return nil }
            return (schema, value)
        }

        if kind.id == "vsource" || kind.id == "isource" {
            return sourceAnnotation(component: component, parameters: instanceParameters)
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

        return nil
    }

    private static func sourceAnnotation(
        component: PlacedComponent,
        parameters: [ParameterSchema]
    ) -> String? {
        if let pulsed = component.parameters["pulse_v2"] {
            let initial = component.parameters["pulse_v1"] ?? 0
            let unit = parameters.first(where: { $0.id == "pulse_v2" })?.unit ?? ""
            return "PULSE \(EngineeringNotation.format(initial, unit: "")) -> \(EngineeringNotation.format(pulsed, unit: unit))"
        }
        if let frequency = component.parameters["sin_freq"] {
            let amplitude = component.parameters["sin_va"] ?? 0
            let amplitudeUnit = parameters.first(where: { $0.id == "sin_va" })?.unit ?? ""
            let frequencyUnit = parameters.first(where: { $0.id == "sin_freq" })?.unit ?? "Hz"
            return "SIN \(EngineeringNotation.format(amplitude, unit: amplitudeUnit)) @ \(EngineeringNotation.format(frequency, unit: frequencyUnit))"
        }
        if let dc = component.parameters["dc"] {
            let unit = parameters.first(where: { $0.id == "dc" })?.unit ?? ""
            return EngineeringNotation.format(dc, unit: unit)
        }
        if let ac = component.parameters["ac"] {
            let unit = parameters.first(where: { $0.id == "ac" })?.unit ?? ""
            return "AC \(EngineeringNotation.format(ac, unit: unit))"
        }
        guard let defaultDC = parameters.first(where: { $0.id == "dc" }),
              let value = defaultDC.defaultValue else {
            return nil
        }
        return EngineeringNotation.format(value, unit: defaultDC.unit)
    }
}
