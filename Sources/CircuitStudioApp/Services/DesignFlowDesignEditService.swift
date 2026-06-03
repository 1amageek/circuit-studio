import Foundation
import CircuitStudioCore

public struct DesignFlowDesignEditScript: Sendable, Hashable, Codable {
    public let edits: [DesignFlowDesignEdit]

    public init(edits: [DesignFlowDesignEdit]) {
        self.edits = edits
    }
}

public struct DesignFlowDesignEdit: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case placeComponent
        case removeComponent
        case renameComponent
        case setComponentParameters
        case connectNet
        case disconnectTerminal
    }

    public let kind: Kind
    public let componentName: String?
    public let newComponentName: String?
    public let deviceKindID: String?
    public let parameters: [String: Double]?
    public let modelPresetID: String?
    public let modelName: String?
    public let netName: String?
    public let terminal: DesignFlowDesignSpec.Terminal?

    public init(
        kind: Kind,
        componentName: String? = nil,
        newComponentName: String? = nil,
        deviceKindID: String? = nil,
        parameters: [String: Double]? = nil,
        modelPresetID: String? = nil,
        modelName: String? = nil,
        netName: String? = nil,
        terminal: DesignFlowDesignSpec.Terminal? = nil
    ) {
        self.kind = kind
        self.componentName = componentName
        self.newComponentName = newComponentName
        self.deviceKindID = deviceKindID
        self.parameters = parameters
        self.modelPresetID = modelPresetID
        self.modelName = modelName
        self.netName = netName
        self.terminal = terminal
    }
}

public struct DesignFlowDesignEditResult: Sendable, Hashable, Codable {
    public let designSpec: DesignFlowDesignSpec
    public let actionLog: [DesignFlowDesignEditAction]
    public let diff: DesignFlowDesignDiff

    public init(
        designSpec: DesignFlowDesignSpec,
        actionLog: [DesignFlowDesignEditAction],
        diff: DesignFlowDesignDiff
    ) {
        self.designSpec = designSpec
        self.actionLog = actionLog
        self.diff = diff
    }
}

public struct DesignFlowDesignEditAction: Sendable, Hashable, Codable {
    public let index: Int
    public let kind: DesignFlowDesignEdit.Kind
    public let status: String
    public let message: String

    public init(index: Int, kind: DesignFlowDesignEdit.Kind, status: String, message: String) {
        self.index = index
        self.kind = kind
        self.status = status
        self.message = message
    }
}

public struct DesignFlowDesignDiff: Sendable, Hashable, Codable {
    public let addedComponents: [String]
    public let removedComponents: [String]
    public let changedComponents: [String]
    public let addedNets: [String]
    public let removedNets: [String]
    public let changedNets: [String]

    public init(before: DesignFlowDesignSpec, after: DesignFlowDesignSpec) {
        let beforeComponents = Dictionary(uniqueKeysWithValues: before.components.map { ($0.name, $0) })
        let afterComponents = Dictionary(uniqueKeysWithValues: after.components.map { ($0.name, $0) })
        let beforeNets = Dictionary(uniqueKeysWithValues: before.nets.map { ($0.name, $0) })
        let afterNets = Dictionary(uniqueKeysWithValues: after.nets.map { ($0.name, $0) })

        self.addedComponents = after.components.map(\.name).filter { beforeComponents[$0] == nil }
        self.removedComponents = before.components.map(\.name).filter { afterComponents[$0] == nil }
        self.changedComponents = after.components.map(\.name).filter { name in
            guard let beforeComponent = beforeComponents[name],
                  let afterComponent = afterComponents[name] else {
                return false
            }
            return beforeComponent != afterComponent
        }
        self.addedNets = after.nets.map(\.name).filter { beforeNets[$0] == nil }
        self.removedNets = before.nets.map(\.name).filter { afterNets[$0] == nil }
        self.changedNets = after.nets.map(\.name).filter { name in
            guard let beforeNet = beforeNets[name],
                  let afterNet = afterNets[name] else {
                return false
            }
            return beforeNet != afterNet
        }
    }
}

public enum DesignFlowDesignEditError: Error, LocalizedError, Equatable {
    case emptyScript
    case missingField(String, DesignFlowDesignEdit.Kind)
    case duplicateComponent(String)
    case unknownComponent(String)
    case duplicateNet(String)
    case unknownNet(String)
    case terminalAlreadyConnected(component: String, port: String, net: String)
    case terminalNotConnected(component: String, port: String, net: String)

    public var errorDescription: String? {
        switch self {
        case .emptyScript:
            return "Design edit script must contain at least one edit."
        case .missingField(let field, let kind):
            return "Design edit \(kind.rawValue) requires field '\(field)'."
        case .duplicateComponent(let component):
            return "Design edit would create duplicate component '\(component)'."
        case .unknownComponent(let component):
            return "Design edit references unknown component '\(component)'."
        case .duplicateNet(let net):
            return "Design edit would create duplicate net '\(net)'."
        case .unknownNet(let net):
            return "Design edit references unknown net '\(net)'."
        case .terminalAlreadyConnected(let component, let port, let net):
            return "Terminal \(component).\(port) is already connected to net '\(net)'."
        case .terminalNotConnected(let component, let port, let net):
            return "Terminal \(component).\(port) is not connected to net '\(net)'."
        }
    }
}

public struct DesignFlowDesignEditService: Sendable {
    public init() {}

    public func apply(
        script: DesignFlowDesignEditScript,
        to spec: DesignFlowDesignSpec,
        catalog: DeviceCatalog = .standard()
    ) throws -> DesignFlowDesignEditResult {
        guard !script.edits.isEmpty else {
            throw DesignFlowDesignEditError.emptyScript
        }
        _ = try spec.build(catalog: catalog)

        var components = spec.components
        var nets = spec.nets
        var actionLog: [DesignFlowDesignEditAction] = []

        for (index, edit) in script.edits.enumerated() {
            let message = try apply(edit: edit, components: &components, nets: &nets)
            actionLog.append(DesignFlowDesignEditAction(
                index: index,
                kind: edit.kind,
                status: "applied",
                message: message
            ))
        }

        let edited = DesignFlowDesignSpec(
            name: spec.name,
            title: spec.title,
            components: components,
            nets: nets,
            analyses: spec.analyses,
            postLayoutAnalysis: spec.postLayoutAnalysis,
            parasiticIR: spec.pexIR
        )
        _ = try edited.build(catalog: catalog)
        return DesignFlowDesignEditResult(
            designSpec: edited,
            actionLog: actionLog,
            diff: DesignFlowDesignDiff(before: spec, after: edited)
        )
    }

    private func apply(
        edit: DesignFlowDesignEdit,
        components: inout [DesignFlowDesignSpec.Component],
        nets: inout [DesignFlowDesignSpec.Net]
    ) throws -> String {
        switch edit.kind {
        case .placeComponent:
            return try placeComponent(edit, components: &components)
        case .removeComponent:
            return try removeComponent(edit, components: &components, nets: &nets)
        case .renameComponent:
            return try renameComponent(edit, components: &components, nets: &nets)
        case .setComponentParameters:
            return try setComponentParameters(edit, components: &components)
        case .connectNet:
            return try connectNet(edit, nets: &nets)
        case .disconnectTerminal:
            return try disconnectTerminal(edit, nets: &nets)
        }
    }

    private func placeComponent(
        _ edit: DesignFlowDesignEdit,
        components: inout [DesignFlowDesignSpec.Component]
    ) throws -> String {
        let name = try required(edit.componentName, field: "componentName", kind: edit.kind)
        let deviceKindID = try required(edit.deviceKindID, field: "deviceKindID", kind: edit.kind)
        guard !components.contains(where: { $0.name == name }) else {
            throw DesignFlowDesignEditError.duplicateComponent(name)
        }
        components.append(DesignFlowDesignSpec.Component(
            name: name,
            deviceKindID: deviceKindID,
            parameters: edit.parameters ?? [:],
            modelPresetID: edit.modelPresetID,
            modelName: edit.modelName
        ))
        return "Placed component \(name)."
    }

    private func removeComponent(
        _ edit: DesignFlowDesignEdit,
        components: inout [DesignFlowDesignSpec.Component],
        nets: inout [DesignFlowDesignSpec.Net]
    ) throws -> String {
        let name = try required(edit.componentName, field: "componentName", kind: edit.kind)
        guard let index = components.firstIndex(where: { $0.name == name }) else {
            throw DesignFlowDesignEditError.unknownComponent(name)
        }
        components.remove(at: index)
        nets = nets.compactMap { net in
            let terminals = net.terminals.filter { $0.component != name }
            guard !terminals.isEmpty else {
                return nil
            }
            return DesignFlowDesignSpec.Net(name: net.name, terminals: terminals)
        }
        return "Removed component \(name)."
    }

    private func renameComponent(
        _ edit: DesignFlowDesignEdit,
        components: inout [DesignFlowDesignSpec.Component],
        nets: inout [DesignFlowDesignSpec.Net]
    ) throws -> String {
        let name = try required(edit.componentName, field: "componentName", kind: edit.kind)
        let newName = try required(edit.newComponentName, field: "newComponentName", kind: edit.kind)
        guard let index = components.firstIndex(where: { $0.name == name }) else {
            throw DesignFlowDesignEditError.unknownComponent(name)
        }
        guard !components.contains(where: { $0.name == newName }) else {
            throw DesignFlowDesignEditError.duplicateComponent(newName)
        }
        let component = components[index]
        components[index] = DesignFlowDesignSpec.Component(
            name: newName,
            deviceKindID: component.deviceKindID,
            parameters: component.parameters,
            modelPresetID: component.modelPresetID,
            modelName: component.modelName
        )
        nets = nets.map { net in
            DesignFlowDesignSpec.Net(
                name: net.name,
                terminals: net.terminals.map { terminal in
                    terminal.component == name
                        ? DesignFlowDesignSpec.Terminal(component: newName, port: terminal.port)
                        : terminal
                }
            )
        }
        return "Renamed component \(name) to \(newName)."
    }

    private func setComponentParameters(
        _ edit: DesignFlowDesignEdit,
        components: inout [DesignFlowDesignSpec.Component]
    ) throws -> String {
        let name = try required(edit.componentName, field: "componentName", kind: edit.kind)
        let parameters = try required(edit.parameters, field: "parameters", kind: edit.kind)
        guard let index = components.firstIndex(where: { $0.name == name }) else {
            throw DesignFlowDesignEditError.unknownComponent(name)
        }
        let component = components[index]
        var mergedParameters = component.parameters
        for (key, value) in parameters {
            mergedParameters[key] = value
        }
        components[index] = DesignFlowDesignSpec.Component(
            name: component.name,
            deviceKindID: component.deviceKindID,
            parameters: mergedParameters,
            modelPresetID: edit.modelPresetID ?? component.modelPresetID,
            modelName: edit.modelName ?? component.modelName
        )
        return "Updated parameters for component \(name)."
    }

    private func connectNet(
        _ edit: DesignFlowDesignEdit,
        nets: inout [DesignFlowDesignSpec.Net]
    ) throws -> String {
        let netName = try required(edit.netName, field: "netName", kind: edit.kind)
        let terminal = try required(edit.terminal, field: "terminal", kind: edit.kind)
        if let existing = nets.first(where: { $0.terminals.contains(terminal) }) {
            throw DesignFlowDesignEditError.terminalAlreadyConnected(
                component: terminal.component,
                port: terminal.port,
                net: existing.name
            )
        }
        if let index = nets.firstIndex(where: { $0.name == netName }) {
            var terminals = nets[index].terminals
            terminals.append(terminal)
            nets[index] = DesignFlowDesignSpec.Net(name: netName, terminals: terminals)
        } else {
            nets.append(DesignFlowDesignSpec.Net(name: netName, terminals: [terminal]))
        }
        return "Connected \(terminal.component).\(terminal.port) to net \(netName)."
    }

    private func disconnectTerminal(
        _ edit: DesignFlowDesignEdit,
        nets: inout [DesignFlowDesignSpec.Net]
    ) throws -> String {
        let netName = try required(edit.netName, field: "netName", kind: edit.kind)
        let terminal = try required(edit.terminal, field: "terminal", kind: edit.kind)
        guard let index = nets.firstIndex(where: { $0.name == netName }) else {
            throw DesignFlowDesignEditError.unknownNet(netName)
        }
        guard nets[index].terminals.contains(terminal) else {
            throw DesignFlowDesignEditError.terminalNotConnected(
                component: terminal.component,
                port: terminal.port,
                net: netName
            )
        }
        let terminals = nets[index].terminals.filter { $0 != terminal }
        if terminals.isEmpty {
            nets.remove(at: index)
        } else {
            nets[index] = DesignFlowDesignSpec.Net(name: netName, terminals: terminals)
        }
        return "Disconnected \(terminal.component).\(terminal.port) from net \(netName)."
    }

    private func required<T>(
        _ value: T?,
        field: String,
        kind: DesignFlowDesignEdit.Kind
    ) throws -> T {
        guard let value else {
            throw DesignFlowDesignEditError.missingField(field, kind)
        }
        return value
    }
}
