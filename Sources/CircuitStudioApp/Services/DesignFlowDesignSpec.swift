import CoreGraphics
import Foundation
import CircuitStudioCore

public struct DesignFlowDesignSpec: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

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

            fileprivate var core: PEXParasiticUnits {
                PEXParasiticUnits(
                    resistance: resistance,
                    capacitance: capacitance,
                    coordinate: coordinate
                )
            }

            public var normalizedScales: (resistance: Double, capacitance: Double) {
                get throws {
                    let units = core
                    guard let resistanceScale = units.resistanceScaleToOhm else {
                        throw DesignFlowDesignSpecError.unsupportedPEXResistanceUnit(resistance)
                    }
                    guard let capacitanceScale = units.capacitanceScaleToFarad else {
                        throw DesignFlowDesignSpecError.unsupportedPEXCapacitanceUnit(capacitance)
                    }
                    guard coordinate == PEXParasiticUnits.canonical.coordinate else {
                        throw DesignFlowDesignSpecError.unsupportedPEXCoordinateUnit(coordinate)
                    }
                    return (resistanceScale, capacitanceScale)
                }
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

            fileprivate var core: PEXParasiticElement {
                PEXParasiticElement(
                    id: id,
                    kind: kind,
                    nodeA: nodeA,
                    nodeB: nodeB,
                    value: value
                )
            }

            public func normalizedCore(
                resistanceScale: Double,
                capacitanceScale: Double
            ) throws -> PEXParasiticElement {
                try validateSPICEToken(id, error: .invalidPEXElementID(id))
                try validateSPICEToken(nodeA, error: .invalidPEXNodeName(nodeA))
                if let nodeB {
                    try validateSPICEToken(nodeB, error: .invalidPEXNodeName(nodeB))
                }
                guard value.isFinite, value > 0 else {
                    throw DesignFlowDesignSpecError.invalidPEXElementValue(id)
                }

                let scale: Double
                switch kind {
                case .resistor:
                    guard nodeB != nil else {
                        throw DesignFlowDesignSpecError.missingPEXElementNodeB(id, kind.rawValue)
                    }
                    scale = resistanceScale
                case .capacitor:
                    scale = capacitanceScale
                case .coupling:
                    guard nodeB != nil else {
                        throw DesignFlowDesignSpecError.missingPEXElementNodeB(id, kind.rawValue)
                    }
                    scale = capacitanceScale
                }

                return PEXParasiticElement(
                    id: id,
                    kind: kind,
                    nodeA: nodeA,
                    nodeB: nodeB,
                    value: value * scale
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

            fileprivate var core: PEXArtifactDiagnostic {
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

        public func normalizedCore() throws -> PEXParasiticIR {
            try validateSPICEToken(cornerID, error: .invalidPEXCornerID(cornerID))
            let scales = try units.normalizedScales
            var elementIDs = Set<String>()
            let normalizedElements = try elements.map { element in
                guard elementIDs.insert(element.id).inserted else {
                    throw DesignFlowDesignSpecError.duplicatePEXElementID(element.id)
                }
                return try element.normalizedCore(
                    resistanceScale: scales.resistance,
                    capacitanceScale: scales.capacitance
                )
            }
            return PEXParasiticIR(
                version: version,
                cornerID: cornerID,
                units: .canonical,
                elements: normalizedElements,
                diagnostics: diagnostics.map(\.core)
            )
        }
    }

    public let name: String
    public let schemaVersion: Int
    public let title: String?
    public let components: [Component]
    public let nets: [Net]
    public let analyses: [Analysis]
    public let postLayoutAnalysis: Analysis?
    public let pexIR: ParasiticIR?

    private enum CodingKeys: String, CodingKey {
        case name, schemaVersion, title, components, nets, analyses, postLayoutAnalysis, pexIR
    }

    public init(
        name: String,
        schemaVersion: Int = Self.currentSchemaVersion,
        title: String? = nil,
        components: [Component],
        nets: [Net],
        analyses: [Analysis],
        postLayoutAnalysis: Analysis? = nil,
        pexIR: PEXParasiticIR? = nil
    ) {
        self.name = name
        self.schemaVersion = schemaVersion
        self.title = title
        self.components = components
        self.nets = nets
        self.analyses = analyses
        self.postLayoutAnalysis = postLayoutAnalysis
        self.pexIR = pexIR.map(ParasiticIR.init)
    }

    public init(
        name: String,
        schemaVersion: Int = Self.currentSchemaVersion,
        title: String? = nil,
        components: [Component],
        nets: [Net],
        analyses: [Analysis],
        postLayoutAnalysis: Analysis? = nil,
        parasiticIR: ParasiticIR?
    ) {
        self.name = name
        self.schemaVersion = schemaVersion
        self.title = title
        self.components = components
        self.nets = nets
        self.analyses = analyses
        self.postLayoutAnalysis = postLayoutAnalysis
        self.pexIR = parasiticIR
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.components = try container.decode([Component].self, forKey: .components)
        self.nets = try container.decode([Net].self, forKey: .nets)
        self.analyses = try container.decode([Analysis].self, forKey: .analyses)
        self.postLayoutAnalysis = try container.decodeIfPresent(Analysis.self, forKey: .postLayoutAnalysis)
        self.pexIR = try container.decodeIfPresent(ParasiticIR.self, forKey: .pexIR)
    }

    public func build(catalog: DeviceCatalog = .standard()) throws -> BuiltDesign {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DesignFlowDesignSpecError.unsupportedSchemaVersion(schemaVersion)
        }
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
            try validateComponentNamePrefix(component.name, kind: kind)
            try validateComponentParameters(component, kind: kind)
            try validateComponentModel(component, kind: kind, catalog: catalog)
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

        try analyses.forEach(validateAnalysis)
        if let postLayoutAnalysis {
            try validateAnalysis(postLayoutAnalysis)
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
            pexIR: try pexIR?.normalizedCore()
        )
    }

    private enum NameKind {
        case design
        case component
        case net
    }

    private func validateName(_ value: String, kind: NameKind) throws {
        let allowed: CharacterSet
        switch kind {
        case .design:
            allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        case .component, .net:
            allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        }

        let invalid = value.isEmpty
            || value.trimmingCharacters(in: .whitespacesAndNewlines) != value
            || value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            || value.contains("/")
            || value.contains("\\")
            || value == "."
            || value == ".."
            || !value.unicodeScalars.allSatisfy { allowed.contains($0) }
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

    private func validateComponentNamePrefix(_ name: String, kind: DeviceKind) throws {
        guard kind.category != .special else {
            return
        }
        let expectedPrefix = kind.spicePrefix.uppercased()
        guard name.uppercased().hasPrefix(expectedPrefix) else {
            throw DesignFlowDesignSpecError.invalidComponentPrefix(
                component: name,
                deviceKindID: kind.id,
                expectedPrefix: expectedPrefix
            )
        }
    }

    private func validateComponentParameters(_ component: Component, kind: DeviceKind) throws {
        let knownParameters = Set(kind.parameterSchema.map(\.id))
        for (parameterName, parameterValue) in component.parameters {
            try validateSPICEToken(parameterName, error: .invalidParameterName(component: component.name, parameter: parameterName))
            guard parameterValue.isFinite else {
                throw DesignFlowDesignSpecError.invalidParameterValue(component: component.name, parameter: parameterName)
            }
            guard knownParameters.contains(parameterName) else {
                throw DesignFlowDesignSpecError.unknownParameter(component: component.name, parameter: parameterName)
            }
            if let range = kind.parameterSchema.first(where: { $0.id == parameterName })?.range,
               !range.contains(parameterValue) {
                throw DesignFlowDesignSpecError.parameterOutOfRange(component: component.name, parameter: parameterName)
            }
        }
        for schema in kind.parameterSchema where schema.isRequired {
            guard component.parameters[schema.id] != nil else {
                throw DesignFlowDesignSpecError.missingRequiredParameter(component: component.name, parameter: schema.id)
            }
        }
    }

    private func validateComponentModel(_ component: Component, kind: DeviceKind, catalog: DeviceCatalog) throws {
        let hasModelPreset = component.modelPresetID != nil
        let hasModelName = component.modelName != nil
        guard hasModelPreset || hasModelName else {
            return
        }
        guard !(hasModelPreset && hasModelName) else {
            throw DesignFlowDesignSpecError.ambiguousComponentModel(component: component.name)
        }
        guard let modelType = kind.modelType else {
            throw DesignFlowDesignSpecError.unsupportedComponentModel(component: component.name, deviceKindID: kind.id)
        }
        if let modelPresetID = component.modelPresetID {
            try validateSPICEToken(modelPresetID, error: .invalidModelPresetID(modelPresetID))
            guard let preset = catalog.preset(for: modelPresetID) else {
                throw DesignFlowDesignSpecError.unknownModelPresetID(modelPresetID)
            }
            guard preset.modelType == modelType else {
                throw DesignFlowDesignSpecError.incompatibleModelPresetID(
                    component: component.name,
                    modelPresetID: modelPresetID,
                    expectedModelType: modelType,
                    actualModelType: preset.modelType
                )
            }
        }
        if let modelName = component.modelName {
            try validateSPICEToken(modelName, error: .invalidModelName(modelName))
        }
    }

    private func validateAnalysis(_ analysis: Analysis) throws {
        switch analysis.kind {
        case .op:
            return
        case .tran:
            let stopTime = try finiteAnalysisValue(analysis.stopTime, name: "stopTime")
            guard stopTime > 0 else {
                throw DesignFlowDesignSpecError.invalidAnalysisValue("stopTime")
            }
            for (name, value) in [
                ("stepTime", analysis.stepTime),
                ("startTime", analysis.startTime),
                ("maxStep", analysis.maxStep),
            ] {
                if let value {
                    guard value.isFinite, value >= 0 else {
                        throw DesignFlowDesignSpecError.invalidAnalysisValue(name)
                    }
                }
            }
        case .dcSweep:
            guard let source = analysis.source else {
                throw DesignFlowDesignSpecError.missingAnalysisValue("source")
            }
            try validateSPICEToken(source, error: .invalidAnalysisSource(source))
            let startValue = try finiteAnalysisValue(analysis.startValue, name: "startValue")
            let stopValue = try finiteAnalysisValue(analysis.stopValue, name: "stopValue")
            let stepValue = try finiteAnalysisValue(analysis.stepValue, name: "stepValue")
            guard stepValue != 0,
                  (stopValue - startValue) * stepValue > 0 else {
                throw DesignFlowDesignSpecError.invalidDCSweepRange
            }
        }
    }

    private func finiteAnalysisValue(_ value: Double?, name: String) throws -> Double {
        guard let value else {
            throw DesignFlowDesignSpecError.missingAnalysisValue(name)
        }
        guard value.isFinite else {
            throw DesignFlowDesignSpecError.invalidAnalysisValue(name)
        }
        return value
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
    case unsupportedSchemaVersion(Int)
    case invalidDesignName(String)
    case invalidComponentName(String)
    case invalidNetName(String)
    case invalidComponentPrefix(component: String, deviceKindID: String, expectedPrefix: String)
    case invalidParameterName(component: String, parameter: String)
    case invalidParameterValue(component: String, parameter: String)
    case unknownParameter(component: String, parameter: String)
    case missingRequiredParameter(component: String, parameter: String)
    case parameterOutOfRange(component: String, parameter: String)
    case unsupportedComponentModel(component: String, deviceKindID: String)
    case ambiguousComponentModel(component: String)
    case invalidModelPresetID(String)
    case unknownModelPresetID(String)
    case incompatibleModelPresetID(component: String, modelPresetID: String, expectedModelType: String, actualModelType: String)
    case invalidModelName(String)
    case duplicateComponent(String)
    case duplicateNet(String)
    case duplicateTerminal(component: String, port: String, firstNet: String, secondNet: String)
    case unknownComponent(String)
    case unknownDeviceKind(String)
    case unknownPort(component: String, port: String)
    case missingAnalysisValue(String)
    case invalidAnalysisValue(String)
    case invalidAnalysisSource(String)
    case invalidDCSweepRange
    case unsupportedPEXResistanceUnit(String)
    case unsupportedPEXCapacitanceUnit(String)
    case unsupportedPEXCoordinateUnit(String)
    case invalidPEXCornerID(String)
    case invalidPEXElementID(String)
    case duplicatePEXElementID(String)
    case invalidPEXNodeName(String)
    case invalidPEXElementValue(String)
    case missingPEXElementNodeB(String, String)
    case missingPEXInput

    public var errorDescription: String? {
        switch self {
        case .emptyComponents:
            return "Design spec requires at least one component."
        case .emptyAnalyses:
            return "Design spec requires at least one analysis."
        case .unsupportedSchemaVersion(let version):
            return "Design spec schema version \(version) is not supported."
        case .invalidDesignName(let name):
            return "Design spec contains an invalid design name: \(name)."
        case .invalidComponentName(let name):
            return "Design spec contains an invalid component name: \(name)."
        case .invalidNetName(let name):
            return "Design spec contains an invalid net name: \(name)."
        case .invalidComponentPrefix(let component, let deviceKindID, let expectedPrefix):
            return "Design spec component \(component) for \(deviceKindID) must start with SPICE prefix \(expectedPrefix)."
        case .invalidParameterName(let component, let parameter):
            return "Design spec contains an invalid parameter name \(parameter) on component \(component)."
        case .invalidParameterValue(let component, let parameter):
            return "Design spec contains a non-finite parameter value \(parameter) on component \(component)."
        case .unknownParameter(let component, let parameter):
            return "Design spec contains an unknown parameter \(parameter) on component \(component)."
        case .missingRequiredParameter(let component, let parameter):
            return "Design spec is missing required parameter \(parameter) on component \(component)."
        case .parameterOutOfRange(let component, let parameter):
            return "Design spec contains an out-of-range parameter \(parameter) on component \(component)."
        case .unsupportedComponentModel(let component, let deviceKindID):
            return "Design spec component \(component) of kind \(deviceKindID) does not support model selection."
        case .ambiguousComponentModel(let component):
            return "Design spec component \(component) cannot specify both modelPresetID and modelName."
        case .invalidModelPresetID(let id):
            return "Design spec contains an invalid model preset ID: \(id)."
        case .unknownModelPresetID(let id):
            return "Design spec references an unknown model preset ID: \(id)."
        case .incompatibleModelPresetID(let component, let modelPresetID, let expectedModelType, let actualModelType):
            return "Design spec component \(component) cannot use model preset \(modelPresetID): expected \(expectedModelType), got \(actualModelType)."
        case .invalidModelName(let name):
            return "Design spec contains an invalid model name: \(name)."
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
        case .invalidAnalysisValue(let name):
            return "Design spec analysis contains an invalid value: \(name)."
        case .invalidAnalysisSource(let source):
            return "Design spec analysis contains an invalid sweep source: \(source)."
        case .invalidDCSweepRange:
            return "Design spec DC sweep range must move from startValue to stopValue using a non-zero stepValue."
        case .unsupportedPEXResistanceUnit(let unit):
            return "Design spec PEX resistance unit is not supported: \(unit)."
        case .unsupportedPEXCapacitanceUnit(let unit):
            return "Design spec PEX capacitance unit is not supported: \(unit)."
        case .unsupportedPEXCoordinateUnit(let unit):
            return "Design spec PEX coordinate unit is not supported: \(unit)."
        case .invalidPEXCornerID(let cornerID):
            return "Design spec contains an invalid PEX corner ID: \(cornerID)."
        case .invalidPEXElementID(let id):
            return "Design spec contains an invalid PEX element ID: \(id)."
        case .duplicatePEXElementID(let id):
            return "Design spec contains a duplicate PEX element ID: \(id)."
        case .invalidPEXNodeName(let node):
            return "Design spec contains an invalid PEX node name: \(node)."
        case .invalidPEXElementValue(let id):
            return "Design spec contains a non-positive or non-finite PEX element value: \(id)."
        case .missingPEXElementNodeB(let id, let kind):
            return "Design spec PEX element \(id) of kind \(kind) requires nodeB."
        case .missingPEXInput:
            return "Design round trip requires PEX input in the design spec or --pex-manifest."
        }
    }
}

private func validateSPICEToken(_ value: String, error: DesignFlowDesignSpecError) throws {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
    let invalid = value.isEmpty
        || value.trimmingCharacters(in: .whitespacesAndNewlines) != value
        || !value.unicodeScalars.allSatisfy { allowed.contains($0) }
    guard !invalid else {
        throw error
    }
}
