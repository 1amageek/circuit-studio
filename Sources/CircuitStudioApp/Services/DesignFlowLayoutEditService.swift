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
        case addCell
        case addNet
        case removeNet
        case addRectShape
        case addPolygonShape
        case addPathShape
        case moveShape
        case removeShape
        case setShapeNet
        case clearShapeNet
        case addVia
        case removeVia
        case addPin
        case removePin
        case addLabel
        case removeLabel
        case addInstance
        case removeInstance
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
    public let dx: Double?
    public let dy: Double?
    public let points: [LayoutPoint]?
    public let pathWidth: Double?
    public let pinName: String?
    public let labelText: String?
    public let viaDefinitionID: String?
    public let instanceName: String?
    public let referenceCellID: UUID?
    public let referenceCellName: String?
    public let rotationDegrees: Double?
    public let magnification: Double?
    public let mirrorX: Bool?
    public let mirrorY: Bool?
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
        dx: Double? = nil,
        dy: Double? = nil,
        points: [LayoutPoint]? = nil,
        pathWidth: Double? = nil,
        pinName: String? = nil,
        labelText: String? = nil,
        viaDefinitionID: String? = nil,
        instanceName: String? = nil,
        referenceCellID: UUID? = nil,
        referenceCellName: String? = nil,
        rotationDegrees: Double? = nil,
        magnification: Double? = nil,
        mirrorX: Bool? = nil,
        mirrorY: Bool? = nil,
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
        self.dx = dx
        self.dy = dy
        self.points = points
        self.pathWidth = pathWidth
        self.pinName = pinName
        self.labelText = labelText
        self.viaDefinitionID = viaDefinitionID
        self.instanceName = instanceName
        self.referenceCellID = referenceCellID
        self.referenceCellName = referenceCellName
        self.rotationDegrees = rotationDegrees
        self.magnification = magnification
        self.mirrorX = mirrorX
        self.mirrorY = mirrorY
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
    public let addedCells: [String]
    public let removedCells: [String]
    public let addedNets: [String]
    public let removedNets: [String]
    public let addedShapes: [UUID]
    public let removedShapes: [UUID]
    /// Shapes present in both documents under the same ID whose layer,
    /// geometry, net, or properties changed (e.g. by a move).
    public let modifiedShapes: [UUID]
    public let addedVias: [UUID]
    public let removedVias: [UUID]
    public let addedPins: [String]
    public let removedPins: [String]
    public let addedLabels: [String]
    public let removedLabels: [String]
    public let addedInstances: [String]
    public let removedInstances: [String]

    public init(before: LayoutDocument, after: LayoutDocument) {
        let beforeCells = Set(before.cells.map(\.name))
        let afterCells = Set(after.cells.map(\.name))
        let beforeNets = Self.nets(in: before)
        let afterNets = Self.nets(in: after)
        let beforeShapes = Self.shapes(in: before)
        let afterShapes = Self.shapes(in: after)
        let beforeVias = Self.vias(in: before)
        let afterVias = Self.vias(in: after)
        let beforePins = Self.pins(in: before)
        let afterPins = Self.pins(in: after)
        let beforeLabels = Self.labels(in: before)
        let afterLabels = Self.labels(in: after)
        let beforeInstances = Self.instances(in: before)
        let afterInstances = Self.instances(in: after)

        self.addedCells = afterCells.subtracting(beforeCells).sorted()
        self.removedCells = beforeCells.subtracting(afterCells).sorted()
        self.addedNets = afterNets.subtracting(beforeNets).sorted()
        self.removedNets = beforeNets.subtracting(afterNets).sorted()
        self.addedShapes = Set(afterShapes.keys).subtracting(beforeShapes.keys)
            .sorted { $0.uuidString < $1.uuidString }
        self.removedShapes = Set(beforeShapes.keys).subtracting(afterShapes.keys)
            .sorted { $0.uuidString < $1.uuidString }
        self.modifiedShapes = beforeShapes
            .compactMap { id, shape -> UUID? in
                guard let counterpart = afterShapes[id], counterpart != shape else { return nil }
                return id
            }
            .sorted { $0.uuidString < $1.uuidString }
        self.addedVias = afterVias.subtracting(beforeVias).sorted { $0.uuidString < $1.uuidString }
        self.removedVias = beforeVias.subtracting(afterVias).sorted { $0.uuidString < $1.uuidString }
        self.addedPins = afterPins.subtracting(beforePins).sorted()
        self.removedPins = beforePins.subtracting(afterPins).sorted()
        self.addedLabels = afterLabels.subtracting(beforeLabels).sorted()
        self.removedLabels = beforeLabels.subtracting(afterLabels).sorted()
        self.addedInstances = afterInstances.subtracting(beforeInstances).sorted()
        self.removedInstances = beforeInstances.subtracting(afterInstances).sorted()
    }

    private static func nets(in document: LayoutDocument) -> Set<String> {
        Set(document.cells.flatMap { cell in
            cell.nets.map { "\(cell.name):\($0.name)" }
        })
    }

    private static func shapes(in document: LayoutDocument) -> [UUID: LayoutShape] {
        Dictionary(
            document.cells.flatMap { cell in cell.shapes.map { ($0.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func vias(in document: LayoutDocument) -> Set<UUID> {
        Set(document.cells.flatMap { $0.vias.map(\.id) })
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

    private static func instances(in document: LayoutDocument) -> Set<String> {
        Set(document.cells.flatMap { cell in
            cell.instances.map { "\(cell.name):\($0.name)" }
        })
    }
}

public enum DesignFlowLayoutEditError: Error, LocalizedError, Equatable {
    case emptyScript
    case missingField(String, DesignFlowLayoutEdit.Kind)
    case invalidGeometry(String)
    case unknownCell(String)
    case duplicateCell(String)
    case unknownNet(String)
    case netInUse(String)
    case duplicateNet(String)
    case netReferenceMismatch(id: UUID, name: String)
    case unknownElement(UUID)
    case duplicateElement(UUID)
    case duplicateInstanceName(String)
    case instanceCycle(String)

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
        case .duplicateCell(let cell):
            return "Layout edit would create duplicate cell '\(cell)'."
        case .unknownNet(let net):
            return "Layout edit references unknown net '\(net)'."
        case .netInUse(let net):
            return "Layout edit cannot remove net '\(net)' because layout elements still reference it."
        case .duplicateNet(let net):
            return "Layout edit would create duplicate net '\(net)'."
        case .netReferenceMismatch(let id, let name):
            return "Layout edit net reference '\(id.uuidString)' does not match net name '\(name)'."
        case .unknownElement(let id):
            return "Layout edit references unknown element '\(id.uuidString)'."
        case .duplicateElement(let id):
            return "Layout edit would create duplicate element '\(id.uuidString)'."
        case .duplicateInstanceName(let name):
            return "Layout edit would create duplicate instance name '\(name)' in the target cell."
        case .instanceCycle(let message):
            return "Layout edit would create an instance cycle: \(message)"
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
        case .addCell:
            return try addCell(edit, to: &layout)
        case .addNet:
            return try addNet(edit, to: &layout)
        case .removeNet:
            return try removeNet(edit, from: &layout)
        case .addRectShape:
            return try addRectShape(edit, to: &layout)
        case .addPolygonShape:
            return try addPolygonShape(edit, to: &layout)
        case .addPathShape:
            return try addPathShape(edit, to: &layout)
        case .moveShape:
            return try moveShape(edit, in: &layout)
        case .removeShape:
            return try removeShape(edit, from: &layout)
        case .setShapeNet:
            return try setShapeNet(edit, in: &layout)
        case .clearShapeNet:
            return try clearShapeNet(edit, in: &layout)
        case .addVia:
            return try addVia(edit, to: &layout)
        case .removeVia:
            return try removeVia(edit, from: &layout)
        case .addPin:
            return try addPin(edit, to: &layout)
        case .removePin:
            return try removePin(edit, from: &layout)
        case .addLabel:
            return try addLabel(edit, to: &layout)
        case .removeLabel:
            return try removeLabel(edit, from: &layout)
        case .addInstance:
            return try addInstance(edit, to: &layout)
        case .removeInstance:
            return try removeInstance(edit, from: &layout)
        }
    }

    private func addCell(_ edit: DesignFlowLayoutEdit, to layout: inout LayoutDocument) throws -> String {
        let cellName = try nonEmpty(edit.cellName, field: "cellName", kind: edit.kind)
        guard !layout.cells.contains(where: { $0.name == cellName }) else {
            throw DesignFlowLayoutEditError.duplicateCell(cellName)
        }
        let cellID = edit.elementID ?? UUID()
        guard !allElementIDs(in: layout).contains(cellID) else {
            throw DesignFlowLayoutEditError.duplicateElement(cellID)
        }
        layout.cells.append(LayoutCell(id: cellID, name: cellName))
        if layout.topCellID == nil {
            layout.topCellID = cellID
        }
        return "Added cell \(cellName)."
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

    private func addPolygonShape(_ edit: DesignFlowLayoutEdit, to layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let shapeID = edit.elementID ?? UUID()
        guard !allElementIDs(in: layout).contains(shapeID) else {
            throw DesignFlowLayoutEditError.duplicateElement(shapeID)
        }
        let points = try required(edit.points, field: "points", kind: edit.kind)
        guard points.count >= 3 else {
            throw DesignFlowLayoutEditError.invalidGeometry("Polygon shape requires at least three points.")
        }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw DesignFlowLayoutEditError.invalidGeometry("Polygon shape points must be finite.")
        }
        let shape = LayoutShape(
            id: shapeID,
            layer: try layer(from: edit),
            netID: try optionalNetID(for: edit, in: layout),
            geometry: .polygon(LayoutPolygon(points: points)),
            properties: edit.properties ?? [:]
        )
        layout.cells[cellIndex].shapes.append(shape)
        return "Added polygon shape \(shapeID.uuidString) to cell \(layout.cells[cellIndex].name)."
    }

    private func moveShape(_ edit: DesignFlowLayoutEdit, in layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let elementID = try required(edit.elementID, field: "elementID", kind: edit.kind)
        let dx = try finite(edit.dx, field: "dx", kind: edit.kind)
        let dy = try finite(edit.dy, field: "dy", kind: edit.kind)
        guard let index = layout.cells[cellIndex].shapes.firstIndex(where: { $0.id == elementID }) else {
            throw DesignFlowLayoutEditError.unknownElement(elementID)
        }
        let delta = LayoutPoint(x: dx, y: dy)
        var shape = layout.cells[cellIndex].shapes[index]
        // The shape keeps its ID across the move so follow-up edits and
        // diff consumers can track it as the same element.
        switch shape.geometry {
        case .rect(let rect):
            shape.geometry = .rect(LayoutRect(
                origin: rect.origin.translated(by: delta),
                size: rect.size
            ))
        case .polygon(let polygon):
            shape.geometry = .polygon(LayoutPolygon(
                points: polygon.points.map { $0.translated(by: delta) }
            ))
        case .path(let path):
            shape.geometry = .path(LayoutPath(
                points: path.points.map { $0.translated(by: delta) },
                width: path.width,
                endCap: path.endCap
            ))
        }
        layout.cells[cellIndex].shapes[index] = shape
        return "Moved shape \(elementID.uuidString) by (\(dx), \(dy)) in cell \(layout.cells[cellIndex].name)."
    }

    private func setShapeNet(_ edit: DesignFlowLayoutEdit, in layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let elementID = try required(edit.elementID, field: "elementID", kind: edit.kind)
        let net = try resolvedNet(for: edit, in: layout)
        guard let index = layout.cells[cellIndex].shapes.firstIndex(where: { $0.id == elementID }) else {
            throw DesignFlowLayoutEditError.unknownElement(elementID)
        }
        layout.cells[cellIndex].shapes[index].netID = net.id
        return "Assigned net \(net.name) to shape \(elementID.uuidString) in cell \(layout.cells[cellIndex].name)."
    }

    private func clearShapeNet(_ edit: DesignFlowLayoutEdit, in layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let elementID = try required(edit.elementID, field: "elementID", kind: edit.kind)
        guard let index = layout.cells[cellIndex].shapes.firstIndex(where: { $0.id == elementID }) else {
            throw DesignFlowLayoutEditError.unknownElement(elementID)
        }
        layout.cells[cellIndex].shapes[index].netID = nil
        return "Cleared net from shape \(elementID.uuidString) in cell \(layout.cells[cellIndex].name)."
    }

    private func addVia(_ edit: DesignFlowLayoutEdit, to layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let viaID = edit.elementID ?? UUID()
        guard !allElementIDs(in: layout).contains(viaID) else {
            throw DesignFlowLayoutEditError.duplicateElement(viaID)
        }
        // The via definition is a tech-database key; whether it exists in
        // the active tech is the DRC's verdict, not this document edit's.
        let viaDefinitionID = try nonEmpty(edit.viaDefinitionID, field: "viaDefinitionID", kind: edit.kind)
        let x = try finite(edit.x, field: "x", kind: edit.kind)
        let y = try finite(edit.y, field: "y", kind: edit.kind)
        let via = LayoutVia(
            id: viaID,
            viaDefinitionID: viaDefinitionID,
            position: LayoutPoint(x: x, y: y),
            netID: try optionalNetID(for: edit, in: layout)
        )
        layout.cells[cellIndex].vias.append(via)
        return "Added via \(viaDefinitionID) at (\(x), \(y)) to cell \(layout.cells[cellIndex].name)."
    }

    private func removeVia(_ edit: DesignFlowLayoutEdit, from layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let elementID = try required(edit.elementID, field: "elementID", kind: edit.kind)
        guard let index = layout.cells[cellIndex].vias.firstIndex(where: { $0.id == elementID }) else {
            throw DesignFlowLayoutEditError.unknownElement(elementID)
        }
        layout.cells[cellIndex].vias.remove(at: index)
        return "Removed via \(elementID.uuidString) from cell \(layout.cells[cellIndex].name)."
    }

    private func addInstance(_ edit: DesignFlowLayoutEdit, to layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let instanceID = edit.elementID ?? UUID()
        guard !allElementIDs(in: layout).contains(instanceID) else {
            throw DesignFlowLayoutEditError.duplicateElement(instanceID)
        }
        let instanceName = try nonEmpty(edit.instanceName, field: "instanceName", kind: edit.kind)
        guard !layout.cells[cellIndex].instances.contains(where: { $0.name == instanceName }) else {
            throw DesignFlowLayoutEditError.duplicateInstanceName(instanceName)
        }
        let referenceCell = try resolvedReferenceCell(for: edit, in: layout)
        let hostCell = layout.cells[cellIndex]
        guard !isCellReachable(hostCell.id, from: referenceCell.id, in: layout) else {
            throw DesignFlowLayoutEditError.instanceCycle(
                "instantiating \(referenceCell.name) inside \(hostCell.name) would make \(hostCell.name) contain itself"
            )
        }
        let x = try finite(edit.x, field: "x", kind: edit.kind)
        let y = try finite(edit.y, field: "y", kind: edit.kind)
        let magnification = edit.magnification ?? 1.0
        guard magnification.isFinite, magnification > 0 else {
            throw DesignFlowLayoutEditError.invalidGeometry("magnification must be finite and greater than zero.")
        }
        let rotationDegrees = edit.rotationDegrees ?? 0.0
        guard rotationDegrees.isFinite else {
            throw DesignFlowLayoutEditError.invalidGeometry("rotationDegrees must be finite.")
        }
        let instance = LayoutInstance(
            id: instanceID,
            cellID: referenceCell.id,
            name: instanceName,
            transform: LayoutTransform(
                translation: LayoutPoint(x: x, y: y),
                rotationDegrees: rotationDegrees,
                magnification: magnification,
                mirrorX: edit.mirrorX ?? false,
                mirrorY: edit.mirrorY ?? false
            )
        )
        layout.cells[cellIndex].instances.append(instance)
        return "Added instance \(instanceName) of cell \(referenceCell.name) to cell \(hostCell.name)."
    }

    private func removeInstance(_ edit: DesignFlowLayoutEdit, from layout: inout LayoutDocument) throws -> String {
        let cellIndex = try resolvedCellIndex(for: edit, in: layout)
        let elementID = try required(edit.elementID, field: "elementID", kind: edit.kind)
        guard let index = layout.cells[cellIndex].instances.firstIndex(where: { $0.id == elementID }) else {
            throw DesignFlowLayoutEditError.unknownElement(elementID)
        }
        let instanceName = layout.cells[cellIndex].instances[index].name
        layout.cells[cellIndex].instances.remove(at: index)
        return "Removed instance \(instanceName) from cell \(layout.cells[cellIndex].name)."
    }

    private func resolvedReferenceCell(
        for edit: DesignFlowLayoutEdit,
        in layout: LayoutDocument
    ) throws -> LayoutCell {
        if let referenceCellID = edit.referenceCellID {
            guard let cell = layout.cells.first(where: { $0.id == referenceCellID }) else {
                throw DesignFlowLayoutEditError.unknownCell(referenceCellID.uuidString)
            }
            return cell
        }
        if let referenceCellName = edit.referenceCellName {
            guard let cell = layout.cells.first(where: { $0.name == referenceCellName }) else {
                throw DesignFlowLayoutEditError.unknownCell(referenceCellName)
            }
            return cell
        }
        throw DesignFlowLayoutEditError.missingField("referenceCellName", edit.kind)
    }

    /// Whether `target` is reachable from `start` through instance
    /// references. Used to reject edits that would close an instance cycle
    /// (including self-instantiation), which GDS hierarchies forbid.
    private func isCellReachable(_ target: UUID, from start: UUID, in layout: LayoutDocument) -> Bool {
        var visited = Set<UUID>()
        var stack = [start]
        while let current = stack.popLast() {
            if current == target { return true }
            guard visited.insert(current).inserted else { continue }
            if let cell = layout.cells.first(where: { $0.id == current }) {
                stack.append(contentsOf: cell.instances.map(\.cellID))
            }
        }
        return false
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
        if let netID = edit.netID {
            guard let net = layout.cells[cellIndex].nets.first(where: { $0.id == netID }) else {
                throw DesignFlowLayoutEditError.unknownNet(netID.uuidString)
            }
            if let netName = edit.netName {
                let checkedName = try nonEmpty(netName, field: "netName", kind: edit.kind)
                guard net.name == checkedName else {
                    throw DesignFlowLayoutEditError.netReferenceMismatch(id: netID, name: checkedName)
                }
            }
            return net
        }
        let netName = try nonEmpty(edit.netName, field: "netName", kind: edit.kind)
        if let net = layout.cells[cellIndex].nets.first(where: { $0.name == netName }) {
            return net
        }
        throw DesignFlowLayoutEditError.unknownNet(netName)
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
