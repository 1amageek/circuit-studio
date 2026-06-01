import Foundation
import LayoutCore
import LayoutTech

public enum LayoutOwnershipResolverError: Error, LocalizedError, Equatable {
    case missingTopCell

    public var errorDescription: String? {
        switch self {
        case .missingTopCell:
            return "Layout ownership resolution requires a top cell."
        }
    }
}

public struct LayoutOwnershipResolution: Sendable, Hashable {
    public let ownershipMap: LayoutOwnershipMap
    public let ownedShapes: [NetAwareLayoutEvaluator.OwnedShape]
    public let unownedShapes: [NetAwareLayoutEvaluator.UnownedShape]

    public init(
        ownershipMap: LayoutOwnershipMap,
        ownedShapes: [NetAwareLayoutEvaluator.OwnedShape],
        unownedShapes: [NetAwareLayoutEvaluator.UnownedShape]
    ) {
        self.ownershipMap = ownershipMap
        self.ownedShapes = ownedShapes
        self.unownedShapes = unownedShapes
    }
}

public struct LayoutOwnershipResolver: Sendable {
    public init() {}

    public func resolve(
        document: LayoutDocument,
        tech: LayoutTechDatabase,
        policy: LayoutOwnershipPolicy = LayoutOwnershipPolicy()
    ) throws -> LayoutOwnershipResolution {
        guard let topCell = topCell(in: document) else {
            throw LayoutOwnershipResolverError.missingTopCell
        }

        let netNamesByID = Dictionary(
            topCell.nets.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        var records: [LayoutOwnershipRecord] = []
        var ownedShapes: [NetAwareLayoutEvaluator.OwnedShape] = []
        var unownedShapes: [NetAwareLayoutEvaluator.UnownedShape] = []

        for shape in topCell.shapes {
            let resolution = ownership(
                for: shape,
                cellName: topCell.name,
                elementKind: "shape",
                netNamesByID: netNamesByID,
                policy: policy
            )
            records.append(resolution.record)
            switch resolution.record.status {
            case .owned:
                if let netName = resolution.record.netName {
                    ownedShapes.append(NetAwareLayoutEvaluator.OwnedShape(netName: netName, shape: shape))
                }
            case .unowned:
                unownedShapes.append(NetAwareLayoutEvaluator.UnownedShape(shapeID: shape.id, layer: shape.layer))
            case .ignored, .exempt:
                break
            }
        }

        for via in topCell.vias {
            guard let viaShape = shape(for: via, tech: tech) else {
                records.append(LayoutOwnershipRecord(
                    cellName: topCell.name,
                    elementKind: "via",
                    shapeID: via.id,
                    layerName: via.viaDefinitionID,
                    netID: via.netID,
                    netName: via.netID.flatMap { netNamesByID[$0] },
                    status: .unowned,
                    reason: "via definition is missing from technology"
                ))
                unownedShapes.append(NetAwareLayoutEvaluator.UnownedShape(
                    shapeID: via.id,
                    layer: LayoutLayerID(name: via.viaDefinitionID, purpose: "cut")
                ))
                continue
            }
            let resolution = ownership(
                for: viaShape,
                cellName: topCell.name,
                elementKind: "via",
                netNamesByID: netNamesByID,
                policy: policy
            )
            records.append(resolution.record)
            switch resolution.record.status {
            case .owned:
                if let netName = resolution.record.netName {
                    ownedShapes.append(NetAwareLayoutEvaluator.OwnedShape(netName: netName, shape: viaShape))
                }
            case .unowned:
                unownedShapes.append(NetAwareLayoutEvaluator.UnownedShape(shapeID: viaShape.id, layer: viaShape.layer))
            case .ignored, .exempt:
                break
            }
        }

        let sortedRecords = records.sorted {
            if $0.cellName != $1.cellName { return $0.cellName < $1.cellName }
            if $0.layerName != $1.layerName { return $0.layerName < $1.layerName }
            return $0.shapeID.uuidString < $1.shapeID.uuidString
        }

        return LayoutOwnershipResolution(
            ownershipMap: LayoutOwnershipMap(topCellName: topCell.name, records: sortedRecords),
            ownedShapes: ownedShapes,
            unownedShapes: unownedShapes.sorted {
                if $0.layer.name != $1.layer.name { return $0.layer.name < $1.layer.name }
                return $0.shapeID.uuidString < $1.shapeID.uuidString
            }
        )
    }

    private func topCell(in document: LayoutDocument) -> LayoutCell? {
        if let topCellID = document.topCellID {
            return document.cell(withID: topCellID)
        }
        return document.cells.first
    }

    private func ownership(
        for shape: LayoutShape,
        cellName: String,
        elementKind: String,
        netNamesByID: [UUID: String],
        policy: LayoutOwnershipPolicy
    ) -> (record: LayoutOwnershipRecord, netName: String?) {
        if policy.isExemptPurpose(shape.properties[policy.exemptionProperty]) {
            return (
                record(
                    shape,
                    cellName: cellName,
                    elementKind: elementKind,
                    netName: nil,
                    status: .exempt,
                    reason: "explicit exemption"
                ),
                nil
            )
        }

        if let propertyNetName = normalized(shape.properties[policy.netNameProperty]) {
            return (
                record(
                    shape,
                    cellName: cellName,
                    elementKind: elementKind,
                    netName: propertyNetName,
                    status: .owned,
                    reason: "net-name property"
                ),
                propertyNetName
            )
        }

        if let netID = shape.netID {
            if let mappedName = normalized(netNamesByID[netID]) {
                return (
                    record(
                        shape,
                        cellName: cellName,
                        elementKind: elementKind,
                        netName: mappedName,
                        status: .owned,
                        reason: "layout net id"
                    ),
                    mappedName
                )
            }
            return (
                record(
                    shape,
                    cellName: cellName,
                    elementKind: elementKind,
                    netName: nil,
                    status: .unowned,
                    reason: "net id has no LayoutNet name"
                ),
                nil
            )
        }

        guard policy.evaluates(layerName: shape.layer.name) else {
            return (
                record(
                    shape,
                    cellName: cellName,
                    elementKind: elementKind,
                    netName: nil,
                    status: .ignored,
                    reason: "layer outside ownership policy"
                ),
                nil
            )
        }

        return (
            record(
                shape,
                cellName: cellName,
                elementKind: elementKind,
                netName: nil,
                status: .unowned,
                reason: "evaluated layer has no net owner"
            ),
            nil
        )
    }

    private func record(
        _ shape: LayoutShape,
        cellName: String,
        elementKind: String,
        netName: String?,
        status: LayoutOwnershipStatus,
        reason: String
    ) -> LayoutOwnershipRecord {
        LayoutOwnershipRecord(
            cellName: cellName,
            elementKind: elementKind,
            shapeID: shape.id,
            layerName: shape.layer.name,
            netID: shape.netID,
            netName: netName,
            status: status,
            reason: reason
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shape(for via: LayoutVia, tech: LayoutTechDatabase) -> LayoutShape? {
        guard let definition = tech.viaDefinition(for: via.viaDefinitionID) else {
            return nil
        }
        let rect = LayoutRect(
            origin: LayoutPoint(
                x: via.position.x - definition.cutSize.width / 2,
                y: via.position.y - definition.cutSize.height / 2
            ),
            size: definition.cutSize
        )
        return LayoutShape(
            id: via.id,
            layer: definition.cutLayer,
            netID: via.netID,
            geometry: .rect(rect)
        )
    }
}
