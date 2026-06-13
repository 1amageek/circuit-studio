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

    public var errorDescription: String? {
        switch self {
        case .parseFailed(let diagnostics):
            return "SPICE could not be parsed for schematic materialization: \(diagnostics.joined(separator: "; "))"
        case .noImportableComponents:
            return "SPICE contains no primitive components that can be materialized into a schematic."
        case .unsupportedComponents(let components):
            return "SPICE contains components that cannot be materialized into a schematic yet: \(components.joined(separator: ", "))."
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
        var components: [PlacedComponent] = []
        var pinNodes: [(componentID: UUID, portID: String, node: String, point: CGPoint)] = []

        for (index, portName) in ports.enumerated() {
            let component = PlacedComponent(
                deviceKindID: PortDirection.bidirectional.deviceKindID,
                name: portName,
                position: CGPoint(x: -160, y: CGFloat(index) * 80)
            )
            components.append(component)
            pinNodes.append((
                componentID: component.id,
                portID: "pin",
                node: portName,
                point: CGPoint(x: component.position.x - 10, y: component.position.y)
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
                position: componentPosition(for: index),
                parameters: parameters(
                    for: parsed,
                    kind: kind,
                    model: parsed.modelName.flatMap { modelByName[$0.lowercased()] }
                ),
                modelName: parsed.modelName
            )
            components.append(component)

            for (port, node) in zip(kind.portDefinitions, parsed.nodes) {
                pinNodes.append((
                    componentID: component.id,
                    portID: port.id,
                    node: node.name,
                    point: component.position.applying(CGAffineTransform(
                        translationX: port.position.x,
                        y: port.position.y
                    ))
                ))
            }
        }

        guard unsupported.isEmpty else {
            throw SPICESchematicImportError.unsupportedComponents(unsupported.sorted())
        }

        let nets = Dictionary(grouping: pinNodes) { $0.node }
        let labels = nets.map { node, pins in
            NetLabel(name: node, position: anchorPoint(for: pins.map(\.point)))
        }
        let wires = nets.flatMap { node, pins -> [Wire] in
            let anchor = anchorPoint(for: pins.map(\.point))
            return pins.map { pin in
                Wire(
                    startPoint: pin.point,
                    endPoint: anchor,
                    startPin: PinReference(componentID: pin.componentID, portID: pin.portID),
                    netName: node
                )
            }
        }

        return SchematicDocument(
            components: components,
            wires: wires,
            labels: labels.sorted { $0.name < $1.name }
        )
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
            if let value = component.parameters[schema.id]?.numericValue {
                values[schema.id] = value
                continue
            }
            if let value = component.parameters[schema.id.uppercased()]?.numericValue {
                values[schema.id] = value
                continue
            }
            if let value = model?.parameters[schema.id]?.numericValue {
                values[schema.id] = value
                continue
            }
            if let value = model?.parameters[schema.id.uppercased()]?.numericValue {
                values[schema.id] = value
            }
        }
        return values
    }

    private func componentPosition(for index: Int) -> CGPoint {
        let column = index % 4
        let row = index / 4
        return CGPoint(x: CGFloat(column) * 160, y: CGFloat(row) * 120)
    }

    private func anchorPoint(for points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        return CGPoint(x: round(x / 20) * 20, y: round(y / 20) * 20)
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
