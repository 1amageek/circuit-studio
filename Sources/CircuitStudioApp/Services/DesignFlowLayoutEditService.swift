import Foundation
import LayoutCore

public struct DesignFlowLayoutEditScript: Sendable, Hashable, Codable {
    public let edits: [DesignFlowLayoutEdit]

    public init(edits: [DesignFlowLayoutEdit]) {
        self.edits = edits
    }
}

public struct DesignFlowLayoutEdit: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case addNet
        case removeNet
        case addRectShape
        case addPathShape
        case removeShape
        case addPin
        case removePin
        case addLabel
        case removeLabel
    }

    public let kind: Kind
    public let cellID: UUID?
    public let cellName: String?
    public let elementID: UUID?
    public let netID: UUID?
    public let netName: String?
    public let layerName: String?
    public let layerPurpose: String?
    public let x: Double?
    public let y: Double?
    public let width: Double?
    public let height: Double?
    public let points: [LayoutPoint]?
    public let pathWidth: Double?
    public let pinName: String?
    public let labelText: String?
    public let properties: [String: String]?

    public init(
        kind: Kind,
        cellID: UUID? = nil,
        cellName: String? = nil,
        elementID: UUID? = nil,
        netID: UUID? = nil,
        netName: String? = nil,
        layerName: String? = nil,
        layerPurpose: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        points: [LayoutPoint]? = nil,
        pathWidth: Double? = nil,
        pinName: String? = nil,
        labelText: String? = nil,
        properties: [String: String]? = nil
    ) {
        self.kind = kind
        self.cellID = cellID
        self.cellName = cellName
        self.elementID = elementID
        self.netID = netID
        self.netName = netName
        self.layerName = layerName
        self.layerPurpose = layerPurpose
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.points = points
        self.pathWidth = pathWidth
        self.pinName = pinName
        self.labelText = labelText
        self.properties = properties
    }
}

public struct DesignFlowLayoutEditResult: Sendable, Hashable, Codable {
    public let layout: LayoutDocument
    public let actionLog: [DesignFlowLayoutEditAction]
    public let diff: DesignFlowLayoutDiff

    public init(
        layout: LayoutDocument,
        actionLog: [DesignFlowLayoutEditAction],
        diff: DesignFlowLayoutDiff
    ) {
        self.layout = layout
        self.actionLog = actionLog
        self.diff = diff
    }
}

public struct DesignFlowLayoutEditAction: Sendable, Hashable, Codable {
    public let index: Int
    public let kind: DesignFlowLayoutEdit.Kind
    public let status: String
    public let message: String

    public init(index: Int, kind: DesignFlowLayoutEdit.Kind, status: String, message: String) {
        self.index = index
        self.kind = kind
        self.status = status
        self.message = message
    }
}

public struct DesignFlowLayoutDiff: Sendable, Hashable, Codable {
    public let addedNets: [String]
    public let removedNets: [String]
    public let addedShapes: [UUID]
    public let removedShapes: [UUID]
    public let addedPins: [String]
    public let removedPins: [String]
    public let addedLabels: [String]
    public let removedLabels: [String]

    public init(before: LayoutDocument, after: LayoutDocument) {
        let beforeNets = Self.nets(in: before)
        let afterNets = Self.nets(in: after)
        let beforeShapes = Self.shapes(in: before)
        let afterShapes = Self.shapes(in: after)
        let beforePins = Self.pins(in: before)
        let afterPins = Self.pins(in: after)
        let beforeLabels = Self.labels(in: before)
        let afterLabels = Self.labels(in: after)

        self.addedNets = afterNets.filter { !beforeNets.contains($0) }.sorted()
        self.removedNets = beforeNets.filter { !afterNets.contains($0) }.sorted()
        self.addedShapes = afterShapes.filter { !beforeShapes.contains($0) }.sorted { $0.uuidString < $1.uuidString }
        self.removedShapes = beforeShapes.filter { !afterShapes.contains($0) }.sorted { $0.uuidString < $1.uuidString }
        self.addedPins = afterPins.filter { !beforePins.contains($0) }.sorted()
        self.removedPins = beforePins.filter { !afterPins.contains($0) }.sorted()
        self.addedLabels = afterLabels.filter { !beforeLabels.contains($0) }.sorted()
        self.removedLabels = beforeLabels.filter { !afterLabels.contains($0) }.sorted()
    }

    private static func nets(in document: LayoutDocument) -> Set<String> {
        Set(document.cells.flatMap { cell in
            cell.nets.map { "\(cell.name):\($0.name)" }
        })
    }

    private static func shapes(in document: LayoutDocument) -> Set<UUID> {
        Set(document.cells.flatMap { $0.shapes.map(\.id) })
    }

    private static func pins(in document: LayoutDocument) -> Set<String> {
        Set(document.cells.flatMap { cell in
            cell.pins.map { "\(cell.name):\($0.name)" }
        })
    }

    private static func labels(in document: LayoutDocument) -> Set<String> {
        Set(document.cells.flatMap { cell in
            cell.labels.map { "\(cell.name):\($0.text)" }
        })
    }
}

public enum DesignFlowLayoutEditError: Error, LocalizedError, Equatable {
    case emptyScript
    case missingField(String, DesignFlowLayoutEdit.Kind)
    case invalidGeometry(String)
    case unknownCell(String)
    case unknownNet(String)
    case netInUse(String)
    case duplicateNet(String)
    case unknownElement(UUID)
    case duplicateElement(UUID)

    public var errorDescription: String? {
        switch self {
        case .emptyScript:
            return "Layout edit script must contain at least one edit."
        case .missingField(let field, let kind):
            return "Layout edit \(kind.rawValue) requires field '\(field)'."
        case .invalidGeometry(let message):
            return "Invalid layout edit geometry: \(message)"
        case .unknownCell(let cell):
            return "Layout edit references unknown cell '\(cell)'."
        case .unknownNet(let net):
            return "Layout edit references unknown net '\(net)'."
        case .netInUse(let net):
            return "Layout edit cannot remove net '\(net)' because layout elements still reference it."
        case .duplicateNet(let net):
            return "Layout edit would create duplicate net '\(net)'."
        case .unknownElement(let id):
            return "Layout edit references unknown element '\(id.uuidString)'."
        case .duplicateElement(let id):
            return "Layout edit would create duplicate element '\(id.uuidString)'."
        }
    }
}

public struct DesignFlowLayoutEditService: Sendable {
    public init() {}

    public func apply(
        script: DesignFlowLayoutEditScript,
        to layout: LayoutDocument
    ) throws -> DesignFlowLayoutEditResult {
        guard !script.edits.isEmpty else {
            throw DesignFlowLayoutEditError.emptyScript
        }

        var edited = layout
        var actionLog: [DesignFlowLayoutEditAction] = []

        for (index, edit) in script.edits.enumerated() {
            let message = try apply(edit: edit, to: &edited)
            actionLog.append(DesignFlowLayoutEditAction(
                index: index,
                kind: edit.kind,
                status: "applied",
                message: message
            ))
        }

        return DesignFlowLayoutEditResult(
            layout: edited,
            actionLog: actionLog,
            diff: DesignFlowLayoutDiff(before: layout, after: edited)
        )
    }

    private func apply(edit: DesignFlowLayoutEdit, to layout: inout LayoutDocument) throws -> String {
        switch edit.kind {
        case .addNet:
            return try addNet(edit, to: &layout)
        case .removeNet:
            return try removeNet(edit, from: &layout)
        case .addRectShape:
            return try addRectShape(edit, to: &layout)
        case .addPathShape:
            return try addPathShape(edit, to: &layout)
        case .removeShape:
            return try removeShape(edit, from: &layout)
        case .addPin:
            return try addPin(edit, to: &layout)
        case .removePin:
            return try removePin(edit, from: &layout)
        case .addLabel:
            return try addLabel(edit, to: &layout)
        case .removeLabel:
            return try removeLabel(edit, from: &layout)
        }
    }

    private func addNet(_ edit: DesignFlowLayoutEdit, to layout: inout LayoutDocument) throws -> String {
        let netName = try nonEmpty(edit.netName, field: "netName", kind: edit.kind)
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        guard !layout.cells[cellIndex].nets.contains(where: { $0.name == netName }) else {
            throw DesignFlowLayoutEditError.duplicateNet(netName)
        }
        let net = LayoutNet(id: edit.netID ?? UUID(), name: netName)
        guard !allElementIDs(in: layout).contains(net.id) else {
            throw DesignFlowLayoutEditError.duplicateElement(net.id)
        }
        layout.cells[cellIndex].nets.append(net)
        return "Added net \(netName) to cell \(layout.cells[cellIndex].name)."
    }

    private func removeNet(_ edit: DesignFlowLayoutEdit, from layout: inout LayoutDocument) throws -> String {
        let net = try resolvedNet(for: edit, in: layout)
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        guard !isNetReferenced(net.id, in: layout.cells[cellIndex]) else {
            throw DesignFlowLayoutEditError.netInUse(net.name)
        }
        guard let index = layout.cells[cellIndex].nets.firstIndex(where: { $0.id == net.id }) else {
            throw DesignFlowLayoutEditError.unknownNet(net.name)
        }
        layout.cells[cellIndex].nets.remove(at: index)
        return "Removed net \(net.name) from cell \(layout.cells[cellIndex].name)."
    }

    private func addRectShape(_ edit: DesignFlowLayoutEdit, to layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let shapeID = edit.elementID ?? UUID()
        guard !allElementIDs(in: layout).contains(shapeID) else {
            throw DesignFlowLayoutEditError.duplicateElement(shapeID)
        }
        let x = try finite(edit.x, field: "x", kind: edit.kind)
        let y = try finite(edit.y, field: "y", kind: edit.kind)
        let width = try positive(edit.width, field: "width", kind: edit.kind)
        let height = try positive(edit.height, field: "height", kind: edit.kind)
        let shape = LayoutShape(
            id: shapeID,
            layer: try layer(from: edit),
            netID: try optionalNetID(for: edit, in: layout),
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: x, y: y),
                size: LayoutSize(width: width, height: height)
            )),
            properties: edit.properties ?? [:]
        )
        layout.cells[cellIndex].shapes.append(shape)
        return "Added rect shape \(shapeID.uuidString) to cell \(layout.cells[cellIndex].name)."
    }

    private func addPathShape(_ edit: DesignFlowLayoutEdit, to layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let shapeID = edit.elementID ?? UUID()
        guard !allElementIDs(in: layout).contains(shapeID) else {
            throw DesignFlowLayoutEditError.duplicateElement(shapeID)
        }
        let points = try required(edit.points, field: "points", kind: edit.kind)
        guard points.count >= 2 else {
            throw DesignFlowLayoutEditError.invalidGeometry("Path shape requires at least two points.")
        }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw DesignFlowLayoutEditError.invalidGeometry("Path shape points must be finite.")
        }
        let pathWidth = try positive(edit.pathWidth, field: "pathWidth", kind: edit.kind)
        let shape = LayoutShape(
            id: shapeID,
            layer: try layer(from: edit),
            netID: try optionalNetID(for: edit, in: layout),
            geometry: .path(LayoutPath(points: points, width: pathWidth)),
            properties: edit.properties ?? [:]
        )
        layout.cells[cellIndex].shapes.append(shape)
        return "Added path shape \(shapeID.uuidString) to cell \(layout.cells[cellIndex].name)."
    }

    private func removeShape(_ edit: DesignFlowLayoutEdit, from layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let elementID = try required(edit.elementID, field: "elementID", kind: edit.kind)
        guard let index = layout.cells[cellIndex].shapes.firstIndex(where: { $0.id == elementID }) else {
            throw DesignFlowLayoutEditError.unknownElement(elementID)
        }
        layout.cells[cellIndex].shapes.remove(at: index)
        return "Removed shape \(elementID.uuidString) from cell \(layout.cells[cellIndex].name)."
    }

    private func addPin(_ edit: DesignFlowLayoutEdit, to layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let pinID = edit.elementID ?? UUID()
        guard !allElementIDs(in: layout).contains(pinID) else {
            throw DesignFlowLayoutEditError.duplicateElement(pinID)
        }
        let pinName = try nonEmpty(edit.pinName, field: "pinName", kind: edit.kind)
        let x = try finite(edit.x, field: "x", kind: edit.kind)
        let y = try finite(edit.y, field: "y", kind: edit.kind)
        let width = try positive(edit.width, field: "width", kind: edit.kind)
        let height = try positive(edit.height, field: "height", kind: edit.kind)
        let pin = LayoutPin(
            id: pinID,
            name: pinName,
            position: LayoutPoint(x: x, y: y),
            size: LayoutSize(width: width, height: height),
            layer: try layer(from: edit),
            netID: try optionalNetID(for: edit, in: layout)
        )
        layout.cells[cellIndex].pins.append(pin)
        return "Added pin \(pinName) to cell \(layout.cells[cellIndex].name)."
    }

    private func removePin(_ edit: DesignFlowLayoutEdit, from layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let elementID = try required(edit.elementID, field: "elementID", kind: edit.kind)
        guard let index = layout.cells[cellIndex].pins.firstIndex(where: { $0.id == elementID }) else {
            throw DesignFlowLayoutEditError.unknownElement(elementID)
        }
        let pinName = layout.cells[cellIndex].pins[index].name
        layout.cells[cellIndex].pins.remove(at: index)
        return "Removed pin \(pinName) from cell \(layout.cells[cellIndex].name)."
    }

    private func addLabel(_ edit: DesignFlowLayoutEdit, to layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let labelID = edit.elementID ?? UUID()
        guard !allElementIDs(in: layout).contains(labelID) else {
            throw DesignFlowLayoutEditError.duplicateElement(labelID)
        }
        let labelText = try nonEmpty(edit.labelText, field: "labelText", kind: edit.kind)
        let x = try finite(edit.x, field: "x", kind: edit.kind)
        let y = try finite(edit.y, field: "y", kind: edit.kind)
        let label = LayoutLabel(
            id: labelID,
            text: labelText,
            position: LayoutPoint(x: x, y: y),
            layer: try layer(from: edit),
            netID: try optionalNetID(for: edit, in: layout)
        )
        layout.cells[cellIndex].labels.append(label)
        return "Added label \(labelText) to cell \(layout.cells[cellIndex].name)."
    }

    private func removeLabel(_ edit: DesignFlowLayoutEdit, from layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let elementID = try required(edit.elementID, field: "elementID", kind: edit.kind)
        guard let index = layout.cells[cellIndex].labels.firstIndex(where: { $0.id == elementID }) else {
            throw DesignFlowLayoutEditError.unknownElement(elementID)
        }
        let labelText = layout.cells[cellIndex].labels[index].text
        layout.cells[cellIndex].labels.remove(at: index)
        return "Removed label \(labelText) from cell \(layout.cells[cellIndex].name)."
    }

    private func resolvedCellIndex(for edit: DesignFlowLayoutEdit, in layout: LayoutDocument) throws -> Int {
        if let cellID = edit.cellID {
            guard let index = layout.cells.firstIndex(where: { $0.id == cellID }) else {
                throw DesignFlowLayoutEditError.unknownCell(cellID.uuidString)
            }
            return index
        }
        if let cellName = edit.cellName {
            guard let index = layout.cells.firstIndex(where: { $0.name == cellName }) else {
                throw DesignFlowLayoutEditError.unknownCell(cellName)
            }
            return index
        }
        if let topCellID = layout.topCellID,
           let index = layout.cells.firstIndex(where: { $0.id == topCellID }) {
            return index
        }
        guard let index = layout.cells.indices.first else {
            throw DesignFlowLayoutEditError.unknownCell("top")
        }
        return index
    }

    private func resolvedNet(for edit: DesignFlowLayoutEdit, in layout: LayoutDocument) throws -> LayoutNet {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        if let netID = edit.netID,
           let net = layout.cells[cellIndex].nets.first(where: { $0.id == netID }) {
            return net
        }
        if let netName = edit.netName,
           let net = layout.cells[cellIndex].nets.first(where: { $0.name == netName }) {
            return net
        }
        throw DesignFlowLayoutEditError.unknownNet(edit.netName ?? edit.netID?.uuidString ?? "")
    }

    private func optionalNetID(for edit: DesignFlowLayoutEdit, in layout: LayoutDocument) throws -> UUID? {
        guard edit.netID != nil || edit.netName != nil else {
            return nil
        }
        return try resolvedNet(for: edit, in: layout).id
    }

    private func layer(from edit: DesignFlowLayoutEdit) throws -> LayoutLayerID {
        let name = try required(edit.layerName, field: "layerName", kind: edit.kind)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignFlowLayoutEditError.invalidGeometry("layerName must not be empty.")
        }
        let purpose = edit.layerPurpose ?? "drawing"
        guard !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DesignFlowLayoutEditError.invalidGeometry("layerPurpose must not be empty.")
        }
        return LayoutLayerID(name: name, purpose: purpose)
    }

    private func isNetReferenced(_ netID: UUID, in cell: LayoutCell) -> Bool {
        cell.shapes.contains { $0.netID == netID }
            || cell.vias.contains { $0.netID == netID }
            || cell.pins.contains { $0.netID == netID }
            || cell.labels.contains { $0.netID == netID }
    }

    private func allElementIDs(in layout: LayoutDocument) -> Set<UUID> {
        var ids = Set<UUID>()
        ids.insert(layout.id)
        for cell in layout.cells {
            ids.insert(cell.id)
            ids.formUnion(cell.nets.map(\.id))
            ids.formUnion(cell.shapes.map(\.id))
            ids.formUnion(cell.vias.map(\.id))
            ids.formUnion(cell.labels.map(\.id))
            ids.formUnion(cell.pins.map(\.id))
            ids.formUnion(cell.instances.map(\.id))
        }
        return ids
    }

    private func required<T>(
        _ value: T?,
        field: String,
        kind: DesignFlowLayoutEdit.Kind
    ) throws -> T {
        guard let value else {
            throw DesignFlowLayoutEditError.missingField(field, kind)
        }
        return value
    }

    private func nonEmpty(
        _ value: String?,
        field: String,
        kind: DesignFlowLayoutEdit.Kind
    ) throws -> String {
        let value = try required(value, field: field, kind: kind)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DesignFlowLayoutEditError.invalidGeometry("\(field) must not be empty.")
        }
        return value
    }

    private func finite(
        _ value: Double?,
        field: String,
        kind: DesignFlowLayoutEdit.Kind
    ) throws -> Double {
        let value = try required(value, field: field, kind: kind)
        guard value.isFinite else {
            throw DesignFlowLayoutEditError.invalidGeometry("\(field) must be finite.")
        }
        return value
    }

    private func positive(
        _ value: Double?,
        field: String,
        kind: DesignFlowLayoutEdit.Kind
    ) throws -> Double {
        let value = try required(value, field: field, kind: kind)
        guard value.isFinite, value > 0 else {
            throw DesignFlowLayoutEditError.invalidGeometry("\(field) must be finite and greater than zero.")
        }
        return value
    }
}
