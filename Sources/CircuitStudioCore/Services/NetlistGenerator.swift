import Foundation

/// Errors raised while generating a netlist from a schematic hierarchy.
public enum NetlistGenerationError: Error, Equatable, LocalizedError {
    /// A component's device kind does not exist in the catalog.
    case unknownDeviceKind(instanceName: String, deviceKindID: String)
    /// A component instantiates a cell that the library does not contain.
    /// `parentCell` is nil when the reference sits in the document being
    /// generated rather than in a library cell.
    case unknownCellReference(parentCell: String?, cellName: String)
    /// A referenced cell's interface failed to derive.
    case invalidCellInterface(cellName: String, underlying: CellInterfaceError)
    /// Cell instantiations form a cycle.
    case dependencyCycle([String])
    /// A subcircuit instance must be named with an X prefix so SPICE
    /// recognizes the element type.
    case invalidSubcircuitInstanceName(String)
    /// Two emitted components in the same body share an instance name.
    /// `cellName` is nil for the top-level body, set inside a `.subckt`.
    /// SPICE instance names must be unique within their scope, so this is
    /// rejected rather than emitted as an ambiguous netlist.
    case duplicateInstanceName(cellName: String?, instanceName: String)

    public var errorDescription: String? {
        switch self {
        case .unknownDeviceKind(let instanceName, let deviceKindID):
            return "Component '\(instanceName)' uses unknown device kind '\(deviceKindID)'."
        case .unknownCellReference(let parentCell, let cellName):
            let location = parentCell.map { "Cell '\($0)'" } ?? "The schematic"
            return "\(location) instantiates '\(cellName)', which does not exist in the project."
        case .invalidCellInterface(let cellName, let underlying):
            return "Cell '\(cellName)' has an invalid interface: \(underlying.localizedDescription)"
        case .dependencyCycle(let path):
            return "Cell instantiation cycle: \(path.joined(separator: " → "))."
        case .invalidSubcircuitInstanceName(let name):
            return "Cell instance '\(name)' must be named with an 'X' prefix (SPICE subcircuit element)."
        case .duplicateInstanceName(let cellName, let instanceName):
            let location = cellName.map { "cell '\($0)'" } ?? "the top-level schematic"
            return "Duplicate instance name '\(instanceName)' in \(location). Component names must be unique within a schematic."
        }
    }
}

/// Generates SPICE netlists from a schematic document and the cell library
/// it draws subcircuits from.
///
/// Cells referenced by the document (and their transitive dependencies)
/// are emitted as `.subckt` definitions, deepest-first; the document's own
/// components form the top-level body. CoreSpice expands subcircuits
/// natively during lowering, so the same hierarchical netlist serves
/// display, simulation, and interchange.
public struct NetlistGenerator: Sendable {
    public let catalog: DeviceCatalog

    public init(catalog: DeviceCatalog = .standard()) {
        self.catalog = catalog
    }

    /// Generate a SPICE netlist from a schematic document.
    ///
    /// - Parameters:
    ///   - document: The top-level schematic (the active cell's body).
    ///   - library: Cells available for instantiation. The default empty
    ///     library means any cell instance in the document is an error.
    public func generate(
        from document: SchematicDocument,
        library: CellLibrary = CellLibrary(),
        title: String = "Untitled",
        testbench: Testbench? = nil,
        processConfiguration: ProcessConfiguration? = nil
    ) throws -> String {
        let dependencies = try collectDependencies(of: document, in: library)

        var interfaces: [String: CellInterface] = [:]
        for name in dependencies {
            guard let cell = library.cell(named: name) else {
                throw NetlistGenerationError.unknownCellReference(parentCell: nil, cellName: name)
            }
            do {
                interfaces[name] = try CellInterface.derive(from: cell.schematic)
            } catch let error as CellInterfaceError {
                throw NetlistGenerationError.invalidCellInterface(cellName: name, underlying: error)
            }
        }

        var lines: [String] = []
        var modelCards: [String] = []
        var generatedModels: Set<String> = []

        // Title
        lines.append("* \(title)")
        lines.append("")

        if let processConfiguration {
            appendProcessHeader(processConfiguration, to: &lines)
        }

        // Subcircuit definitions, deepest-first so every reference is
        // already defined when read top to bottom.
        for name in dependencies {
            guard let cell = library.cell(named: name),
                  let interface = interfaces[name] else {
                throw NetlistGenerationError.unknownCellReference(parentCell: nil, cellName: name)
            }
            let portList = interface.ports.map(\.name).joined(separator: " ")
            lines.append(".subckt \(name) \(portList)")
            lines.append(contentsOf: try emitBody(
                of: cell.schematic,
                cellName: name,
                interfaces: interfaces,
                modelCards: &modelCards,
                generatedModels: &generatedModels
            ))
            lines.append(".ends \(name)")
            lines.append("")
        }

        // Top-level body
        let body = try emitBody(
            of: document,
            cellName: nil,
            interfaces: interfaces,
            modelCards: &modelCards,
            generatedModels: &generatedModels
        )
        lines.append(contentsOf: body)
        if !body.isEmpty {
            lines.append("")
        }

        // Model cards are global: subcircuit bodies reference them by name.
        if !modelCards.isEmpty {
            lines.append(contentsOf: modelCards)
            lines.append("")
        }

        // Testbench analysis commands
        if let testbench {
            for command in testbench.analysisCommands {
                lines.append(analysisLine(command))
            }
            lines.append("")
        }

        lines.append(".end")
        return lines.joined(separator: "\n")
    }

    // MARK: - Hierarchy

    /// Cells the document transitively instantiates, deepest-first.
    private func collectDependencies(
        of document: SchematicDocument,
        in library: CellLibrary
    ) throws -> [String] {
        var ordered: [String] = []
        var visited: Set<String> = []
        var stack: [String] = []

        func visit(_ name: String, parentCell: String?) throws {
            if let cycleStart = stack.firstIndex(of: name) {
                throw NetlistGenerationError.dependencyCycle(Array(stack[cycleStart...]) + [name])
            }
            if visited.contains(name) { return }
            guard let cell = library.cell(named: name) else {
                throw NetlistGenerationError.unknownCellReference(parentCell: parentCell, cellName: name)
            }
            stack.append(name)
            for child in cell.referencedCellNames {
                try visit(child, parentCell: name)
            }
            stack.removeLast()
            visited.insert(name)
            ordered.append(name)
        }

        for component in document.components {
            if let child = component.cellName {
                try visit(child, parentCell: nil)
            }
        }
        return ordered
    }

    // MARK: - Body Emission

    /// Emits the element lines for one schematic body. `cellName` is nil
    /// for the top-level document and set for `.subckt` bodies, where it
    /// namespaces custom model-card names (model cards are global in
    /// SPICE, instance names are not).
    private func emitBody(
        of document: SchematicDocument,
        cellName: String?,
        interfaces: [String: CellInterface],
        modelCards: inout [String],
        generatedModels: inout Set<String>
    ) throws -> [String] {
        let extractor = NetExtractor()
        let nets = extractor.extract(from: document)

        // Build component-pin-to-netname map
        var pinNetMap: [String: String] = [:]  // "componentID:portID" -> netName
        for net in nets {
            for conn in net.connections {
                let key = "\(conn.componentID):\(conn.portID)"
                pinNetMap[key] = net.name
            }
        }

        // Reject duplicate instance names before emitting any line: SPICE
        // instance names must be unique within their scope, and a duplicate
        // would otherwise be written as an ambiguous, silently-wrong netlist.
        var emittedNames: Set<String> = []
        for component in document.components {
            guard component.deviceKindID != "ground",
                  PortDirection(deviceKindID: component.deviceKindID) == nil else { continue }
            guard emittedNames.insert(component.name).inserted else {
                throw NetlistGenerationError.duplicateInstanceName(
                    cellName: cellName,
                    instanceName: component.name
                )
            }
        }

        var lines: [String] = []

        for component in document.components {
            guard component.deviceKindID != "ground",
                  PortDirection(deviceKindID: component.deviceKindID) == nil else { continue }

            if let childCellName = component.cellName {
                guard let interface = interfaces[childCellName] else {
                    throw NetlistGenerationError.unknownCellReference(
                        parentCell: cellName,
                        cellName: childCellName
                    )
                }
                guard component.name.uppercased().hasPrefix("X") else {
                    throw NetlistGenerationError.invalidSubcircuitInstanceName(component.name)
                }
                let nodeNames = interface.ports.map { port -> String in
                    // Connectivity is keyed by the port's stable id (the child
                    // port-marker component UUID) — the same id the parent wire
                    // stored — so a child-port rename never misroutes the net.
                    // The name still labels the unconnected-pin placeholder.
                    let key = "\(component.id):\(port.id)"
                    return pinNetMap[key] ?? "nc_\(component.name)_\(port.name)"
                }
                var parts = [component.name]
                parts.append(contentsOf: nodeNames)
                parts.append(childCellName)
                lines.append(parts.joined(separator: " "))
                continue
            }

            guard let kind = catalog.device(for: component.deviceKindID) else {
                throw NetlistGenerationError.unknownDeviceKind(
                    instanceName: component.name,
                    deviceKindID: component.deviceKindID
                )
            }

            let nodeNames = kind.portDefinitions.map { port -> String in
                let key = "\(component.id):\(port.id)"
                return pinNetMap[key] ?? "nc_\(component.name)_\(port.id)"
            }

            if let modelType = kind.modelType {
                // Semiconductor device: instance line with model name + .model card
                let modelName: String
                let resolvedModelParams: [String: Double]
                let usesExternalModel: Bool

                if let overrideName = component.modelName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !overrideName.isEmpty {
                    modelName = overrideName
                    resolvedModelParams = [:]
                    usesExternalModel = true
                } else if let presetID = component.modelPresetID,
                   let preset = catalog.preset(for: presetID) {
                    // Preset mode: share model card across instances using the same preset
                    modelName = presetID.uppercased()
                    // Start from preset parameters, overlay with component overrides
                    var merged = preset.parameters
                    for schema in kind.parameterSchema where schema.isModelParameter {
                        if let override = component.parameters[schema.id],
                           override != preset.parameters[schema.id] {
                            merged[schema.id] = override
                        }
                    }
                    resolvedModelParams = merged
                    usesExternalModel = false
                } else {
                    // Custom mode: per-instance model card. Inside a cell the
                    // name carries the cell prefix — model cards are global,
                    // so identical instance names in two cells must not
                    // collide.
                    if let cellName {
                        modelName = "\(modelType)_\(cellName)_\(component.name)"
                    } else {
                        modelName = "\(modelType)_\(component.name)"
                    }
                    var params: [String: Double] = [:]
                    for schema in kind.parameterSchema where schema.isModelParameter {
                        if let value = component.parameters[schema.id] {
                            params[schema.id] = value
                        }
                    }
                    resolvedModelParams = params
                    usesExternalModel = false
                }

                // Instance parameters (non-model parameters like W, L)
                let instanceParams = kind.parameterSchema
                    .filter { !$0.isModelParameter }
                    .compactMap { schema -> String? in
                        guard let value = component.parameters[schema.id] else { return nil }
                        return "\(schema.id.uppercased())=\(formatEngineering(value))"
                    }

                var parts = [component.name]
                parts.append(contentsOf: nodeNames)
                parts.append(modelName)
                parts.append(contentsOf: instanceParams)
                lines.append(parts.joined(separator: " "))

                // Generate .model card (once per model name)
                if !usesExternalModel,
                   !generatedModels.contains(modelName) {
                    generatedModels.insert(modelName)

                    let modelParams = resolvedModelParams
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\(formatValue($0.value))" }

                    var modelLine = ".model \(modelName) \(modelType)"
                    if modelType == "NMOS" || modelType == "PMOS" {
                        let level = modelLevel(for: kind.id) ?? 1
                        modelLine += " level=\(level)"
                    }
                    if !modelParams.isEmpty {
                        modelLine += " " + modelParams.joined(separator: " ")
                    }
                    modelCards.append(modelLine)
                }
            } else {
                // Non-semiconductor device (passives, sources, controlled sources)
                let paramStr = formatParameters(component: component, kind: kind)
                let line = "\(component.name) \(nodeNames.joined(separator: " ")) \(paramStr)"
                lines.append(line.trimmingCharacters(in: .whitespaces))
            }
        }

        return lines
    }

    // MARK: - Process Header

    private func appendProcessHeader(_ configuration: ProcessConfiguration, to lines: inout [String]) {
        let hasLibraries = (configuration.technology?.libraries.contains { $0.isEnabled }) == true
        let parameters = configuration.effectiveParameters()
        let temperature = configuration.temperatureOverride
            ?? configuration.effectiveCorner()?.temperature
            ?? configuration.technology?.defaultTemperature

        if let technology = configuration.technology {
            lines.append("* Process: \(technology.name)")
            if let corner = configuration.effectiveCorner() {
                lines.append("* Corner: \(corner.name)")
            }
        }

        if hasLibraries {
            for library in configuration.technology?.libraries ?? [] where library.isEnabled {
                let path = quotePath(library.path)
                switch library.kind {
                case .include:
                    lines.append(".include \(path)")
                case .library:
                    if let section = configuration.librarySection(for: library) {
                        lines.append(".lib \(path) \(section)")
                    } else {
                        lines.append(".lib \(path)")
                    }
                }
            }
        }

        if !parameters.isEmpty {
            for (name, value) in parameters.sorted(by: { $0.key < $1.key }) {
                lines.append(".param \(name)=\(formatValue(value))")
            }
        }

        if let temperature {
            lines.append(".temp \(formatValue(temperature))")
        }

        if hasLibraries || !parameters.isEmpty || temperature != nil {
            lines.append("")
        }
    }

    // MARK: - Parameter Formatting

    private func formatParameters(component: PlacedComponent, kind: DeviceKind) -> String {
        switch kind.id {
        case "resistor":
            let r = component.parameters["r"] ?? 1000
            return formatEngineering(r)
        case "capacitor":
            let c = component.parameters["c"] ?? 1e-9
            return formatEngineering(c)
        case "inductor":
            let l = component.parameters["l"] ?? 1e-6
            return formatEngineering(l)
        case "vsource", "isource":
            return formatSourceParameters(component)
        case "vcvs":
            return formatValue(component.parameters["e"] ?? 1.0)
        case "vccs":
            return formatValue(component.parameters["g"] ?? 0.001)
        case "ccvs":
            return formatValue(component.parameters["h"] ?? 1000)
        case "cccs":
            return formatValue(component.parameters["f"] ?? 1.0)
        default:
            // Generic: key=value pairs
            return component.parameters
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\(formatValue($0.value))" }
                .joined(separator: " ")
        }
    }

    private func modelLevel(for deviceKindID: String) -> Int? {
        switch deviceKindID {
        case "nmos_l1", "pmos_l1":
            return 1
        case "nmos_l2", "pmos_l2":
            return 2
        case "nmos_l3", "pmos_l3":
            return 3
        default:
            return nil
        }
    }

    private func formatSourceParameters(_ component: PlacedComponent) -> String {
        var parts: [String] = []

        // DC value
        if let dc = component.parameters["dc"] {
            parts.append("dc \(formatValue(dc))")
        }

        // AC magnitude
        if let ac = component.parameters["ac"] {
            parts.append("ac \(formatValue(ac))")
        }

        // PULSE function: detected by presence of pulse_v2
        if let v2 = component.parameters["pulse_v2"] {
            let v1 = component.parameters["pulse_v1"] ?? 0
            let td = component.parameters["pulse_td"] ?? 0
            let tr = component.parameters["pulse_tr"] ?? 0
            let tf = component.parameters["pulse_tf"] ?? 0
            let pw = component.parameters["pulse_pw"] ?? 0
            let per = component.parameters["pulse_per"] ?? 0
            parts.append("PULSE(\(formatEngineering(v1)) \(formatEngineering(v2)) \(formatEngineering(td)) \(formatEngineering(tr)) \(formatEngineering(tf)) \(formatEngineering(pw)) \(formatEngineering(per)))")
        }

        // SIN function: detected by presence of sin_freq
        if let freq = component.parameters["sin_freq"] {
            let vo = component.parameters["sin_vo"] ?? 0
            let va = component.parameters["sin_va"] ?? 0
            let td = component.parameters["sin_td"] ?? 0
            let theta = component.parameters["sin_theta"] ?? 0
            parts.append("SIN(\(formatValue(vo)) \(formatValue(va)) \(formatEngineering(freq)) \(formatEngineering(td)) \(formatValue(theta)))")
        }

        return parts.isEmpty ? "dc 0" : parts.joined(separator: " ")
    }

    // MARK: - Analysis Line Generation

    private func analysisLine(_ command: AnalysisCommand) -> String {
        switch command {
        case .op:
            return ".op"
        case .tran(let spec):
            let step = spec.stepTime ?? spec.stopTime / 100.0
            return ".tran \(formatEngineering(step)) \(formatEngineering(spec.stopTime))"
        case .ac(let spec):
            let scaleStr: String
            switch spec.scaleType {
            case .decade: scaleStr = "dec"
            case .octave: scaleStr = "oct"
            case .linear: scaleStr = "lin"
            }
            return ".ac \(scaleStr) \(spec.numberOfPoints) \(formatEngineering(spec.startFrequency)) \(formatEngineering(spec.stopFrequency))"
        case .dcSweep(let spec):
            return ".dc \(spec.source) \(formatValue(spec.startValue)) \(formatValue(spec.stopValue)) \(formatValue(spec.stepValue))"
        case .noise(let spec):
            let scaleStr: String
            switch spec.scaleType {
            case .decade: scaleStr = "dec"
            case .octave: scaleStr = "oct"
            case .linear: scaleStr = "lin"
            }
            return ".noise v(\(spec.outputNode)) \(spec.inputSource) \(scaleStr) \(spec.numberOfPoints) \(formatEngineering(spec.startFrequency)) \(formatEngineering(spec.stopFrequency))"
        case .tf(let spec):
            // spec.output is a bare node name; the .tf card requires V(node).
            return ".tf v(\(spec.output)) \(spec.input)"
        case .pz(let spec):
            return ".pz \(spec.inputNode) \(spec.inputReference) \(spec.outputNode) \(spec.outputReference) vol pz"
        }
    }

    // MARK: - Number Formatting

    private func formatValue(_ value: Double) -> String {
        if value == Double(Int(value)) && abs(value) < 1e9 {
            return "\(Int(value))"
        }
        return "\(value)"
    }

    private func formatEngineering(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue == 0 { return "0" }
        if absValue >= 1e12 { return String(format: "%.4gT", value / 1e12) }
        if absValue >= 1e9 { return String(format: "%.4gG", value / 1e9) }
        if absValue >= 1e6 { return String(format: "%.4gMeg", value / 1e6) }
        if absValue >= 1e3 { return String(format: "%.4gk", value / 1e3) }
        if absValue >= 1 { return String(format: "%.4g", value) }
        if absValue >= 1e-3 { return String(format: "%.4gm", value * 1e3) }
        if absValue >= 1e-6 { return String(format: "%.4gu", value * 1e6) }
        if absValue >= 1e-9 { return String(format: "%.4gn", value * 1e9) }
        if absValue >= 1e-12 { return String(format: "%.4gp", value * 1e12) }
        return String(format: "%.4gf", value * 1e15)
    }

    private func quotePath(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
