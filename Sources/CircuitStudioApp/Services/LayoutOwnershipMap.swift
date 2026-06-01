import Foundation

public enum LayoutOwnershipStatus: String, Sendable, Hashable, Codable {
    case owned
    case unowned
    case ignored
    case exempt
}

public struct LayoutOwnershipRecord: Sendable, Hashable, Codable {
    public let cellName: String
    public let elementKind: String
    public let shapeID: UUID
    public let layerName: String
    public let netID: UUID?
    public let netName: String?
    public let status: LayoutOwnershipStatus
    public let reason: String

    public init(
        cellName: String,
        elementKind: String = "shape",
        shapeID: UUID,
        layerName: String,
        netID: UUID?,
        netName: String?,
        status: LayoutOwnershipStatus,
        reason: String
    ) {
        self.cellName = cellName
        self.elementKind = elementKind
        self.shapeID = shapeID
        self.layerName = layerName
        self.netID = netID
        self.netName = netName
        self.status = status
        self.reason = reason
    }
}

public struct LayoutOwnershipMap: Sendable, Hashable, Codable {
    public let topCellName: String
    public let records: [LayoutOwnershipRecord]

    public init(topCellName: String, records: [LayoutOwnershipRecord]) {
        self.topCellName = topCellName
        self.records = records
    }

    public var ownedCount: Int {
        records.filter { $0.status == .owned }.count
    }

    public var unownedCount: Int {
        records.filter { $0.status == .unowned }.count
    }

    public var ignoredCount: Int {
        records.filter { $0.status == .ignored }.count
    }

    public var exemptCount: Int {
        records.filter { $0.status == .exempt }.count
    }
}
