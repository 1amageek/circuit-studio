import CoreGraphics
import Foundation
import CircuitStudioCore

public struct DesignFlowDesignSpec: Sendable, Hashable, Codable {
    public struct Component: Sendable, Hashable, Codable {
        public let name: String
        public let deviceKindID: String
        public let parameters: [String: Double]
        public let modelPresetID: String?
        public let modelName: String?

        private enum CodingKeys: String, CodingKey {
            case name, deviceKindID, parameters, modelPresetID, modelName
        }

        public init(
            name: String,
            deviceKindID: String,
            parameters: [String: Double] = [:],
            modelPresetID: String? = nil,
            modelName: String? = nil
        ) {
            self.name = name
            self.deviceKindID = deviceKindID
            self.parameters = parameters
            self.modelPresetID = modelPresetID
            self.modelName = modelName
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.deviceKindID = try container.decode(String.self, forKey: .deviceKindID)
            self.parameters = try container.decodeIfPresent([String: Double].self, forKey: .parameters) ?? [:]
            self.modelPresetID = try container.decodeIfPresent(String.self, forKey: .modelPresetID)
            self.modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        }
    }

    public struct Net: Sendable, Hashable, Codable {
        public let name: String
        public let terminals: [Terminal]

        public init(name: String, terminals: [Terminal]) {
            self.name = name
            self.terminals = terminals
        }
    }

    public struct Terminal: Sendable, Hashable, Codable {
        public let component: String
        public let port: String

        public init(component: String, port: String) {
            self.component = component
            self.port = port
        }
    }

    public struct Analysis: Sendable, Hashable, Codable {
        public enum Kind: String, Sendable, Hashable, Codable {
            case op
            case tran
            case dcSweep
        }

        public let kind: Kind
        public let stopTime: Double?
        public let stepTime: Double?
        public let startTime: Double?
        public let maxStep: Double?
        public let source: String?
        public let startValue: Double?
        public let stopValue: Double?
        public let stepValue: Double?

        public init(
            kind: Kind,
            stopTime: Double? = nil,
            stepTime: Double? = nil,
            startTime: Double? = nil,
            maxStep: Double? = nil,
            source: String? = nil,
            startValue: Double? = nil,
            stopValue: Double? = nil,
            stepValue: Double? = nil
        ) {
            self.kind = kind
            self.stopTime = stopTime
            self.stepTime = stepTime
            self.startTime = startTime
            self.maxStep = maxStep
            self.source = source
            self.startValue = startValue
            self.stopValue = stopValue
            self.stepValue = stepValue
        }

        public func command() throws -> AnalysisCommand {
            switch kind {
            case .op:
                return .op
            case .tran:
                guard let stopTime else {
                    throw DesignFlowDesignSpecError.missingAnalysisValue("stopTime")
                }
                return .tran(TranSpec(
                    stopTime: stopTime,
                    stepTime: stepTime,
                    startTime: startTime,
                    maxStep: maxStep
                ))
            case .dcSweep:
                guard let source else {
                    throw DesignFlowDesignSpecError.missingAnalysisValue("source")
                }
                guard let startValue else {
                    throw DesignFlowDesignSpecError.missingAnalysisValue("startValue")
                }
                guard let stopValue else {
                    throw DesignFlowDesignSpecError.missingAnalysisValue("stopValue")
                }
                guard let stepValue else {
                    throw DesignFlowDesignSpecError.missingAnalysisValue("stepValue")
                }
                return .dcSweep(DCSweepSpec(
                    source: source,
                    startValue: startValue,
                    stopValue: stopValue,
                    stepValue: stepValue
                ))
            }
        }
    }

    public struct BuiltDesign: Sendable {
        public let name: String
        public let title: String
        public let schematic: SchematicDocument
        public let testbench: Testbench
        public let postLayoutCommand: AnalysisCommand
        public let pexIR: PEXParasiticIR?

        public init(
            name: String,
            title: String,
            schematic: SchematicDocument,
            testbench: Testbench,
            postLayoutCommand: AnalysisCommand,
            pexIR: PEXParasiticIR?
        ) {
            self.name = name
            self.title = title
            self.schematic = schematic
            self.testbench = testbench
            self.postLayoutCommand = postLayoutCommand
            self.pexIR = pexIR
        }
    }

    public struct ParasiticIR: Sendable, Hashable, Codable {
        public struct Units: Sendable, Hashable, Codable {
            public let resistance: String
            public let capacitance: String
            public let coordinate: String

            private enum CodingKeys: String, CodingKey {
                case resistance, capacitance, coordinate
            }

            public init(resistance: String = "ohm", capacitance: String = "F", coordinate: String = "um") {
                self.resistance = resistance
                self.capacitance = capacitance
                self.coordinate = coordinate
            }

            public init(_ units: PEXParasiticUnits) {
                self.resistance = units.resistance
                self.capacitance = units.capacitance
                self.coordinate = units.coordinate
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.resistance = try container.decodeIfPresent(String.self, forKey: .resistance) ?? "ohm"
                self.capacitance = try container.decodeIfPresent(String.self, forKey: .capacitance) ?? "F"
                self.coordinate = try container.decodeIfPresent(String.self, forKey: .coordinate) ?? "um"
            }

            public var core: PEXParasiticUnits {
                PEXParasiticUnits(
                    resistance: resistance,
                    capacitance: capacitance,
                    coordinate: coordinate
                )
            }
        }

        public struct Element: Sendable, Hashable, Codable {
            public let id: String
            public let kind: PEXParasiticElement.Kind
            public let nodeA: String
            public let nodeB: String?
            public let value: Double

            private enum CodingKeys: String, CodingKey {
                case id, kind, nodeA, nodeB, value
            }

            public init(
                id: String,
                kind: PEXParasiticElement.Kind,
                nodeA: String,
                nodeB: String?,
                value: Double
            ) {
                self.id = id
                self.kind = kind
                self.nodeA = nodeA
                self.nodeB = nodeB
                self.value = value
            }

            public init(_ element: PEXParasiticElement) {
                self.id = element.id
                self.kind = element.kind
                self.nodeA = element.nodeA
                self.nodeB = element.nodeB
                self.value = element.value
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.id = try container.decode(String.self, forKey: .id)
                let kindValue = try container.decode(String.self, forKey: .kind)
                guard let kind = PEXParasiticElement.Kind(rawValue: kindValue) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .kind,
                        in: container,
                        debugDescription: "Unsupported parasitic element kind: \(kindValue)"
                    )
                }
                self.kind = kind
                self.nodeA = try container.decode(String.self, forKey: .nodeA)
                self.nodeB = try container.decodeIfPresent(String.self, forKey: .nodeB)
                self.value = try container.decode(Double.self, forKey: .value)
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(kind.rawValue, forKey: .kind)
                try container.encode(nodeA, forKey: .nodeA)
                try container.encodeIfPresent(nodeB, forKey: .nodeB)
                try container.encode(value, forKey: .value)
            }

            public var core: PEXParasiticElement {
                PEXParasiticElement(
                    id: id,
                    kind: kind,
                    nodeA: nodeA,
                    nodeB: nodeB,
                    value: value
                )
            }
        }

        public struct Diagnostic: Sendable, Hashable, Codable {
            public let severity: PEXArtifactDiagnostic.Severity
            public let message: String
            public let elementID: String?

            private enum CodingKeys: String, CodingKey {
                case severity, message, elementID
            }

            public init(severity: PEXArtifactDiagnostic.Severity, message: String, elementID: String? = nil) {
                self.severity = severity
                self.message = message
                self.elementID = elementID
            }

            public init(_ diagnostic: PEXArtifactDiagnostic) {
                self.severity = diagnostic.severity
                self.message = diagnostic.message
                self.elementID = diagnostic.elementID
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let severityValue = try container.decode(String.self, forKey: .severity)
                guard let severity = PEXArtifactDiagnostic.Severity(rawValue: severityValue) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .severity,
                        in: container,
                        debugDescription: "Unsupported PEX diagnostic severity: \(severityValue)"
                    )
                }
                self.severity = severity
                self.message = try container.decode(String.self, forKey: .message)
                self.elementID = try container.decodeIfPresent(String.self, forKey: .elementID)
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(severity.rawValue, forKey: .severity)
                try container.encode(message, forKey: .message)
                try container.encodeIfPresent(elementID, forKey: .elementID)
            }

            public var core: PEXArtifactDiagnostic {
                PEXArtifactDiagnostic(
                    severity: severity,
                    message: message,
                    elementID: elementID
                )
            }
        }

        public let version: String
        public let cornerID: String
        public let units: Units
        public let elements: [Element]
        public let diagnostics: [Diagnostic]

        private enum CodingKeys: String, CodingKey {
            case version, cornerID, units, elements, diagnostics
        }

        public init(
            version: String,
            cornerID: String,
            units: Units = Units(),
            elements: [Element],
            diagnostics: [Diagnostic] = []
        ) {
            self.version = version
            self.cornerID = cornerID
            self.units = units
            self.elements = elements
            self.diagnostics = diagnostics
        }

        public init(_ ir: PEXParasiticIR) {
            self.version = ir.version
            self.cornerID = ir.cornerID
            self.units = Units(ir.units)
            self.elements = ir.elements.map(Element.init)
            self.diagnostics = ir.diagnostics.map(Diagnostic.init)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.version = try container.decode(String.self, forKey: .version)
            self.cornerID = try container.decode(String.self, forKey: .cornerID)
            self.units = try container.decodeIfPresent(Units.self, forKey: .units) ?? Units()
            self.elements = try container.decode([Element].self, forKey: .elements)
            self.diagnostics = try container.decodeIfPresent([Diagnostic].self, forKey: .diagnostics) ?? []
        }

        public var core: PEXParasiticIR {
            PEXParasiticIR(
                version: version,
                cornerID: cornerID,
                units: units.core,
                elements: elements.map(\.core),
                diagnostics: diagnostics.map(\.core)
            )
        }
    }

    public let name: String
    public let title: String?
    public let components: [Component]
    public let nets: [Net]
    public let analyses: [Analysis]
    public let postLayoutAnalysis: Analysis?
    public let pexIR: ParasiticIR?

    public init(
        name: String,
        title: String? = nil,
        components: [Component],
        nets: [Net],
        analyses: [Analysis],
        postLayoutAnalysis: Analysis? = nil,
        pexIR: PEXParasiticIR? = nil
    ) {
        self.name = name
        self.title = title
        self.components = components
        self.nets = nets
        self.analyses = analyses
        self.postLayoutAnalysis = postLayoutAnalysis
        self.pexIR = pexIR.map(ParasiticIR.init)
    }

    public func build(catalog: DeviceCatalog = .standard()) throws -> BuiltDesign {
        try validateName(name, kind: .design)
        guard !components.isEmpty else {
            throw DesignFlowDesignSpecError.emptyComponents
        }
        guard !analyses.isEmpty else {
            throw DesignFlowDesignSpecError.emptyAnalyses
        }

        var placedComponents: [PlacedComponent] = []
        var componentIDs: [String: UUID] = [:]
        var componentKinds: [String: DeviceKind] = [:]

        for (index, component) in components.enumerated() {
            try validateName(component.name, kind: .component)
            guard componentIDs[component.name] == nil else {
                throw DesignFlowDesignSpecError.duplicateComponent(component.name)
            }
            guard let kind = catalog.device(for: component.deviceKindID) else {
                throw DesignFlowDesignSpecError.unknownDeviceKind(component.deviceKindID)
            }
            let id = UUID()
            componentIDs[component.name] = id
            componentKinds[component.name] = kind
            placedComponents.append(PlacedComponent(
                id: id,
                deviceKindID: component.deviceKindID,
                name: component.name,
                position: CGPoint(x: Double(index) * 120.0, y: 0),
                parameters: component.parameters,
                modelPresetID: component.modelPresetID,
                modelName: component.modelName
            ))
        }

        var wires: [Wire] = []
        var labels: [NetLabel] = []
        var netNames = Set<String>()
        var terminalOwners: [Terminal: String] = [:]

        for (netIndex, net) in nets.enumerated() {
            try validateName(net.name, kind: .net)
            guard netNames.insert(net.name).inserted else {
                throw DesignFlowDesignSpecError.duplicateNet(net.name)
            }
            for terminal in net.terminals {
                if let owner = terminalOwners[terminal] {
                    throw DesignFlowDesignSpecError.duplicateTerminal(
                        component: terminal.component,
                        port: terminal.port,
                        firstNet: owner,
                        secondNet: net.name
                    )
                }
                terminalOwners[terminal] = net.name
            }
            let terminalPins = try net.terminals.map { terminal in
                try pinReference(
                    terminal,
                    componentIDs: componentIDs,
                    componentKinds: componentKinds
                )
            }
            guard !terminalPins.isEmpty else {
                continue
            }

            let hub = CGPoint(x: Double(netIndex) * 40.0, y: 200.0 + Double(netIndex) * 20.0)
            labels.append(NetLabel(name: net.name, position: hub))

            if terminalPins.count == 1 {
                wires.append(Wire(
                    startPoint: hub,
                    endPoint: hub,
                    startPin: terminalPins[0],
                    netName: net.name
                ))
            } else {
                let first = terminalPins[0]
                for terminalIndex in terminalPins.indices.dropFirst() {
                    wires.append(Wire(
                        startPoint: hub,
                        endPoint: CGPoint(x: hub.x + Double(terminalIndex) * 10.0, y: hub.y),
                        startPin: first,
                        endPin: terminalPins[terminalIndex],
                        netName: net.name
                    ))
                }
            }
        }

        let commands = try analyses.map { try $0.command() }
        let postLayoutCommand = try (postLayoutAnalysis?.command() ?? commands[0])
        let designTitle = title ?? name
        return BuiltDesign(
            name: name,
            title: designTitle,
            schematic: SchematicDocument(
                components: placedComponents,
                wires: wires,
                labels: labels
            ),
            testbench: Testbench(
                name: designTitle,
                analysisCommands: commands
            ),
            postLayoutCommand: postLayoutCommand,
            pexIR: pexIR?.core
        )
    }

    private enum NameKind {
        case design
        case component
        case net
    }

    private func validateName(_ value: String, kind: NameKind) throws {
        let invalid = value.isEmpty
            || value.trimmingCharacters(in: .whitespacesAndNewlines) != value
            || value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            || value.contains("/")
            || value.contains("\\")
            || value == "."
            || value == ".."
        guard !invalid else {
            switch kind {
            case .design:
                throw DesignFlowDesignSpecError.invalidDesignName(value)
            case .component:
                throw DesignFlowDesignSpecError.invalidComponentName(value)
            case .net:
                throw DesignFlowDesignSpecError.invalidNetName(value)
            }
        }
    }

    private func pinReference(
        _ terminal: Terminal,
        componentIDs: [String: UUID],
        componentKinds: [String: DeviceKind]
    ) throws -> PinReference {
        guard let componentID = componentIDs[terminal.component],
              let componentKind = componentKinds[terminal.component] else {
            throw DesignFlowDesignSpecError.unknownComponent(terminal.component)
        }
        guard componentKind.portDefinitions.contains(where: { $0.id == terminal.port }) else {
            throw DesignFlowDesignSpecError.unknownPort(
                component: terminal.component,
                port: terminal.port
            )
        }
        return PinReference(componentID: componentID, portID: terminal.port)
    }
}

public enum DesignFlowDesignSpecError: Error, LocalizedError, Equatable {
    case emptyComponents
    case emptyAnalyses
    case invalidDesignName(String)
    case invalidComponentName(String)
    case invalidNetName(String)
    case duplicateComponent(String)
    case duplicateNet(String)
    case duplicateTerminal(component: String, port: String, firstNet: String, secondNet: String)
    case unknownComponent(String)
    case unknownDeviceKind(String)
    case unknownPort(component: String, port: String)
    case missingAnalysisValue(String)
    case missingPEXInput

    public var errorDescription: String? {
        switch self {
        case .emptyComponents:
            return "Design spec requires at least one component."
        case .emptyAnalyses:
            return "Design spec requires at least one analysis."
        case .invalidDesignName(let name):
            return "Design spec contains an invalid design name: \(name)."
        case .invalidComponentName(let name):
            return "Design spec contains an invalid component name: \(name)."
        case .invalidNetName(let name):
            return "Design spec contains an invalid net name: \(name)."
        case .duplicateComponent(let name):
            return "Design spec contains a duplicate component: \(name)."
        case .duplicateNet(let name):
            return "Design spec contains a duplicate net: \(name)."
        case .duplicateTerminal(let component, let port, let firstNet, let secondNet):
            return "Design spec terminal \(component).\(port) appears in multiple nets: \(firstNet), \(secondNet)."
        case .unknownComponent(let name):
            return "Design spec references an unknown component: \(name)."
        case .unknownDeviceKind(let id):
            return "Design spec references an unknown device kind: \(id)."
        case .unknownPort(let component, let port):
            return "Design spec references unknown port \(port) on component \(component)."
        case .missingAnalysisValue(let name):
            return "Design spec analysis is missing required value: \(name)."
        case .missingPEXInput:
            return "Design round trip requires PEX input in the design spec or --pex-manifest."
        }
    }
}
