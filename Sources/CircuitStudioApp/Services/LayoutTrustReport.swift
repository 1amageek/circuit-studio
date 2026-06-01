import Foundation

public struct LayoutTrustReport: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case passed
        case failed
    }

    public let schemaVersion: Int
    public let status: Status
    public let topCellName: String
    public let ownershipMap: LayoutOwnershipMap
    public let netAwareReport: NetAwareLayoutEvaluator.Report
    public let evaluatedShapeCount: Int
    public let ownedShapeCount: Int
    public let unownedShapeCount: Int
    public let ignoredShapeCount: Int
    public let exemptShapeCount: Int

    public init(
        schemaVersion: Int = 1,
        topCellName: String,
        ownershipMap: LayoutOwnershipMap,
        netAwareReport: NetAwareLayoutEvaluator.Report
    ) {
        self.schemaVersion = schemaVersion
        self.status = netAwareReport.passed ? .passed : .failed
        self.topCellName = topCellName
        self.ownershipMap = ownershipMap
        self.netAwareReport = netAwareReport
        self.evaluatedShapeCount = ownershipMap.ownedCount + ownershipMap.unownedCount
        self.ownedShapeCount = ownershipMap.ownedCount
        self.unownedShapeCount = ownershipMap.unownedCount
        self.ignoredShapeCount = ownershipMap.ignoredCount
        self.exemptShapeCount = ownershipMap.exemptCount
    }

    public var passed: Bool {
        status == .passed
    }

    public var summary: String {
        if passed {
            return "layout trust evaluation passed"
        }
        return netAwareReport.summary
    }
}
