import Foundation

/// Generates SPICE netlists directly from a SchematicDocument.
/// Replaces the old NetlistService by eliminating the intermediate Design model.
public struct NetlistGenerator: Sendable {
    public let catalog: DeviceCatalog

    public init(catalog: DeviceCatalog = .standard()) {
        self.catalog = catalog
    }

    /// Generate a SPICE netlist from a schematic document.
    public func generate(
        from document: SchematicDocument,
        title: String = "Untitled",
        testbench: Testbench? = nil
    ) -> String {
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

        var lines: [String] = []
        var modelCards: [String] = []
        var generatedModels: Set<String> = []

        // Title
        lines.append("* \(title)")
        lines.append("")

        // Components
        for component in document.components {
            guard component.deviceKindID != "ground" else { continue }
            guard let kind = catalog.device(for: component.deviceKindID) else { continue }

            let nodeNames = kind.portDefinitions.map { port -> String in
                let key = "\(component.id):\(port.id)"
                return pinNetMap[key] ?? "nc_\(component.name)_\(port.id)"
            }

            if let modelType = kind.modelType {
                // Semiconductor device: instance line with model name + .model card
                let modelName = "\(modelType)_\(component.name)"

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
                if !generatedModels.contains(modelName) {
                    generatedModels.insert(modelName)

                    let modelParams = kind.parameterSchema
                        .filter { $0.isModelParameter }
                        .compactMap { schema -> String? in
                            guard let value = component.parameters[schema.id] else { return nil }
                            return "\(schema.id)=\(formatValue(value))"
                        }

                    var modelLine = ".model \(modelName) \(modelType)"
                    if modelType == "NMOS" || modelType == "PMOS" {
                        modelLine += " level=1"
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

        if !document.components.isEmpty {
            lines.append("")
        }

        // Model cards
        if !modelCards.isEmpty {
            for card in modelCards {
                lines.append(card)
            }
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

    private func formatSourceParameters(_ component: PlacedComponent) -> String {
        var parts: [String] = []
        if let dc = component.parameters["dc"] {
            parts.append("dc \(formatValue(dc))")
        }
        if let ac = component.parameters["ac"] {
            parts.append("ac \(formatValue(ac))")
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
            return ".tf \(spec.output) \(spec.input)"
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
}
