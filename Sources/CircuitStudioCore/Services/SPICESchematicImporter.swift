import CoreGraphics
import CoreSpiceIO
import Foundation

public struct SPICESchematicImportResult: Sendable {
    public let cells: [DesignCell]
    public let topCellName: String
    public let activeCellName: String
    public let sourceDescription: String

    public init(
        cells: [DesignCell],
        topCellName: String,
        activeCellName: String,
        sourceDescription: String
    ) {
        self.cells = cells
        self.topCellName = topCellName
        self.activeCellName = activeCellName
        self.sourceDescription = sourceDescription
    }
}

public enum SPICESchematicImportError: Error, Equatable, LocalizedError {
    case parseFailed([String])
    case noImportableComponents
    case unsupportedComponents([String])
    case layoutFailed([String])

    public var errorDescription: String? {
        switch self {
        case .parseFailed(let diagnostics):
            return "SPICE could not be parsed for schematic materialization: \(diagnostics.joined(separator: "; "))"
        case .noImportableComponents:
            return "SPICE contains no primitive components that can be materialized into a schematic."
        case .unsupportedComponents(let components):
            return "SPICE contains components that cannot be materialized into a schematic yet: \(components.joined(separator: ", "))."
        case .layoutFailed(let diagnostics):
            return "SPICE connectivity could not be materialized into a trustworthy schematic: \(diagnostics.joined(separator: "; "))"
        }
    }
}

public struct SPICESchematicImporter: Sendable {
    public init() {}

    public func importTopLevel(
        source: String,
        fileName: String?,
        topCellName requestedTopCellName: String,
        catalog: DeviceCatalog = .standard()
    ) async throws -> SPICESchematicImportResult {
        let parseResult = await SPICEParser().parse(source: source, fileName: fileName)
        guard let netlist = parseResult.netlist, !parseResult.hasErrors else {
            let diagnostics = parseResult.errors.map(\.message)
            throw SPICESchematicImportError.parseFailed(diagnostics.isEmpty ? ["unknown parse error"] : diagnostics)
        }

        let selected = selectedBody(from: netlist, requestedTopCellName: requestedTopCellName)
        let document = try materializeDocument(
            body: selected.body,
            ports: selected.ports,
            models: selected.models,
            catalog: catalog
        )
        guard !document.components.isEmpty else {
            throw SPICESchematicImportError.noImportableComponents
        }

        return SPICESchematicImportResult(
            cells: [DesignCell(name: selected.cellName, schematic: document)],
            topCellName: selected.cellName,
            activeCellName: selected.cellName,
            sourceDescription: selected.sourceDescription
        )
    }

    private struct SelectedBody {
        let cellName: String
        let ports: [String]
        let body: ParsedNetlistBody
        let models: [ParsedModel]
        let sourceDescription: String
    }

    private func selectedBody(
        from netlist: ParsedNetlist,
        requestedTopCellName: String
    ) -> SelectedBody {
        if netlist.components.isEmpty {
            if let subcircuit = netlist.subcircuit(named: requestedTopCellName) {
                return SelectedBody(
                    cellName: subcircuit.name,
                    ports: subcircuit.ports,
                    body: subcircuit.body,
                    models: netlist.models + subcircuit.body.models,
                    sourceDescription: ".subckt \(subcircuit.name)"
                )
            }
            if netlist.subcircuits.count == 1, let subcircuit = netlist.subcircuits.first {
                return SelectedBody(
                    cellName: subcircuit.name,
                    ports: subcircuit.ports,
                    body: subcircuit.body,
                    models: netlist.models + subcircuit.body.models,
                    sourceDescription: ".subckt \(subcircuit.name)"
                )
            }
        }

        return SelectedBody(
            cellName: requestedTopCellName,
            ports: [],
            body: netlist.body,
            models: netlist.models,
            sourceDescription: "top-level SPICE body"
        )
    }

    private func materializeDocument(
        body: ParsedNetlistBody,
        ports: [String],
        models: [ParsedModel],
        catalog: DeviceCatalog
    ) throws -> SchematicDocument {
        let modelByName = Dictionary(
            models.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var unsupported: [String] = []
        var components: [ConnectivityAwareSchematicLayoutEngine.Component] = []

        for (index, portName) in ports.enumerated() {
            let component = PlacedComponent(
                deviceKindID: PortDirection.bidirectional.deviceKindID,
                name: portName,
                position: .zero
            )
            components.append(ConnectivityAwareSchematicLayoutEngine.Component(
                placed: component,
                nodesByPortID: ["pin": portName],
                sourceOrder: index
            ))
        }

        for (index, parsed) in body.components.enumerated() {
            guard let deviceKindID = deviceKindID(
                for: parsed,
                modelByName: modelByName
            ) else {
                unsupported.append("\(parsed.name)(\(parsed.type.rawValue))")
                continue
            }
            guard let kind = catalog.device(for: deviceKindID) else {
                unsupported.append("\(parsed.name)(\(deviceKindID))")
                continue
            }
            guard kind.portDefinitions.count <= parsed.nodes.count else {
                unsupported.append("\(parsed.name)(expected \(kind.portDefinitions.count) nodes, got \(parsed.nodes.count))")
                continue
            }

            let component = PlacedComponent(
                deviceKindID: deviceKindID,
                name: parsed.name,
                position: .zero,
                parameters: parameters(
                    for: parsed,
                    kind: kind,
                    model: parsed.modelName.flatMap { modelByName[$0.lowercased()] }
                ),
                modelName: parsed.modelName
            )
            components.append(ConnectivityAwareSchematicLayoutEngine.Component(
                placed: component,
                nodesByPortID: Dictionary(
                    uniqueKeysWithValues: zip(kind.portDefinitions, parsed.nodes).map { port, node in
                        (port.id, node.name)
                    }
                ),
                sourceOrder: ports.count + index
            ))
        }

        guard unsupported.isEmpty else {
            throw SPICESchematicImportError.unsupportedComponents(unsupported.sorted())
        }

        return try ConnectivityAwareSchematicLayoutEngine(catalog: catalog)
            .makeDocument(components: components)
    }

    private func deviceKindID(
        for component: ParsedComponent,
        modelByName: [String: ParsedModel]
    ) -> String? {
        switch component.type {
        case .resistor:
            return "resistor"
        case .capacitor:
            return "capacitor"
        case .inductor:
            return "inductor"
        case .voltageSource:
            return "vsource"
        case .currentSource:
            return "isource"
        case .vcvs:
            return "vcvs"
        case .vccs:
            return "vccs"
        case .ccvs:
            return "ccvs"
        case .cccs:
            return "cccs"
        case .diode:
            return "diode"
        case .bjt:
            return bipolarKind(for: component, modelByName: modelByName)
        case .mosfet:
            return mosfetKind(for: component, modelByName: modelByName)
        case .subcircuitInstance,
             .jfet,
             .mesfet,
             .transmissionLine,
             .uniformRC,
             .coupledInductors,
             .behavioral,
             .switch_,
             .currentSwitch:
            return nil
        }
    }

    private func bipolarKind(
        for component: ParsedComponent,
        modelByName: [String: ParsedModel]
    ) -> String? {
        guard let modelName = component.modelName else { return "npn" }
        if let model = modelByName[modelName.lowercased()] {
            switch model.type {
            case .pnp:
                return "pnp"
            case .npn:
                return "npn"
            default:
                return nil
            }
        }
        return modelName.lowercased().hasPrefix("p") ? "pnp" : "npn"
    }

    private func mosfetKind(
        for component: ParsedComponent,
        modelByName: [String: ParsedModel]
    ) -> String? {
        guard let modelName = component.modelName else { return nil }
        let lowerName = modelName.lowercased()
        let isPMOS: Bool
        let level: Int
        if let model = modelByName[lowerName] {
            switch model.type {
            case .pmos:
                isPMOS = true
            case .nmos:
                isPMOS = false
            default:
                return nil
            }
            level = model.level ?? 1
        } else if lowerName.contains("pmos") || lowerName.hasPrefix("p") {
            isPMOS = true
            level = 1
        } else if lowerName.contains("nmos") || lowerName.hasPrefix("n") {
            isPMOS = false
            level = 1
        } else {
            return nil
        }

        switch (isPMOS, level) {
        case (true, 2):
            return "pmos_l2"
        case (true, 3):
            return "pmos_l3"
        case (true, _):
            return "pmos_l1"
        case (false, 2):
            return "nmos_l2"
        case (false, 3):
            return "nmos_l3"
        case (false, _):
            return "nmos_l1"
        }
    }

    private func parameters(
        for component: ParsedComponent,
        kind: DeviceKind,
        model: ParsedModel?
    ) -> [String: Double] {
        var values: [String: Double] = [:]
        for schema in kind.parameterSchema {
            if let value = numericParameter(
                keys: instanceParameterKeys(schemaID: schema.id, component: component),
                in: component.parameters
            ) {
                values[schema.id] = value
                continue
            }
            if let model,
               let value = numericParameter(keys: [schema.id], in: model.parameters) {
                values[schema.id] = value
            }
        }
        return values
    }

    private func instanceParameterKeys(
        schemaID: String,
        component: ParsedComponent
    ) -> [String] {
        let componentType = component.type
        guard componentType == .voltageSource || componentType == .currentSource else {
            return [schemaID]
        }
        let parameterKeys = Set(component.parameters.keys.map { $0.lowercased() })
        let hasPulse = !parameterKeys.isDisjoint(with: [
            "v1", "v2", "tr", "tf", "pw", "per",
        ]) || parameterKeys.contains(where: { $0.hasPrefix("pulse_") })
        let hasSine = !parameterKeys.isDisjoint(with: [
            "vo", "va", "freq", "phase", "theta",
        ]) || parameterKeys.contains(where: { $0.hasPrefix("sin_") })

        if schemaID.hasPrefix("pulse_") && !hasPulse {
            return [schemaID]
        }
        if schemaID.hasPrefix("sin_") && !hasSine {
            return [schemaID]
        }
        switch schemaID {
        case "dc":
            return [schemaID, componentType == .voltageSource ? "v" : "i"]
        case "pulse_v1":
            return [schemaID, "v1"]
        case "pulse_v2":
            return [schemaID, "v2"]
        case "pulse_td":
            return [schemaID, "td"]
        case "pulse_tr":
            return [schemaID, "tr"]
        case "pulse_tf":
            return [schemaID, "tf"]
        case "pulse_pw":
            return [schemaID, "pw"]
        case "pulse_per":
            return [schemaID, "per"]
        case "sin_vo":
            return [schemaID, "vo"]
        case "sin_va":
            return [schemaID, "va"]
        case "sin_freq":
            return [schemaID, "freq"]
        case "sin_td":
            return [schemaID, "td"]
        case "sin_theta":
            return [schemaID, "theta", "phase"]
        default:
            return [schemaID]
        }
    }

    private func numericParameter(
        keys: [String],
        in parameters: [String: ParsedParameterValue]
    ) -> Double? {
        for key in keys {
            if let value = parameters[key]?.numericValue {
                return value
            }
            if let value = parameters[key.lowercased()]?.numericValue {
                return value
            }
            if let value = parameters[key.uppercased()]?.numericValue {
                return value
            }
        }
        return nil
    }

}

private extension ParsedParameterValue {
    var numericValue: Double? {
        switch self {
        case .numeric(let value):
            return value
        case .boolean(let value):
            return value ? 1 : 0
        case .string, .expression:
            return nil
        }
    }
}
