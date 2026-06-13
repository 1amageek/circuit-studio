import Foundation

public struct LayoutTrustReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1
    public static let artifactKind = "layout-trust-report"
    private static let expectedKind = artifactKind

    public enum Status: String, Sendable, Hashable, Codable {
        case passed
        case failed
    }

    public let schemaVersion: Int
    public let kind: String
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
        topCellName: String,
        ownershipMap: LayoutOwnershipMap,
        netAwareReport: NetAwareLayoutEvaluator.Report
    ) {
        let derivedValues = Self.derivedValues(ownershipMap: ownershipMap, netAwareReport: netAwareReport)
        self.schemaVersion = Self.currentSchemaVersion
        self.kind = Self.expectedKind
        self.status = derivedValues.status
        self.topCellName = topCellName
        self.ownershipMap = ownershipMap
        self.netAwareReport = netAwareReport
        self.evaluatedShapeCount = derivedValues.evaluatedShapeCount
        self.ownedShapeCount = derivedValues.ownedShapeCount
        self.unownedShapeCount = derivedValues.unownedShapeCount
        self.ignoredShapeCount = derivedValues.ignoredShapeCount
        self.exemptShapeCount = derivedValues.exemptShapeCount
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

extension LayoutTrustReport {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case status
        case topCellName
        case ownershipMap
        case netAwareReport
        case evaluatedShapeCount
        case ownedShapeCount
        case unownedShapeCount
        case ignoredShapeCount
        case exemptShapeCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard decodedSchemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported layout trust report schema version \(decodedSchemaVersion)."
            )
        }

        let decodedKind = try container.decode(String.self, forKey: .kind)
        guard decodedKind == Self.expectedKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported layout trust report kind \(decodedKind)."
            )
        }

        let decodedStatus = try container.decode(Status.self, forKey: .status)
        let decodedTopCellName = try container.decode(String.self, forKey: .topCellName)
        let decodedOwnershipMap = try container.decode(LayoutOwnershipMap.self, forKey: .ownershipMap)
        let decodedNetAwareReport = try container.decode(NetAwareLayoutEvaluator.Report.self, forKey: .netAwareReport)
        let decodedEvaluatedShapeCount = try container.decode(Int.self, forKey: .evaluatedShapeCount)
        let decodedOwnedShapeCount = try container.decode(Int.self, forKey: .ownedShapeCount)
        let decodedUnownedShapeCount = try container.decode(Int.self, forKey: .unownedShapeCount)
        let decodedIgnoredShapeCount = try container.decode(Int.self, forKey: .ignoredShapeCount)
        let decodedExemptShapeCount = try container.decode(Int.self, forKey: .exemptShapeCount)

        let derivedValues = Self.derivedValues(
            ownershipMap: decodedOwnershipMap,
            netAwareReport: decodedNetAwareReport
        )
        try Self.validate(
            status: decodedStatus,
            topCellName: decodedTopCellName,
            evaluatedShapeCount: decodedEvaluatedShapeCount,
            ownedShapeCount: decodedOwnedShapeCount,
            unownedShapeCount: decodedUnownedShapeCount,
            ignoredShapeCount: decodedIgnoredShapeCount,
            exemptShapeCount: decodedExemptShapeCount,
            derivedValues: derivedValues,
            container: container
        )

        schemaVersion = decodedSchemaVersion
        kind = decodedKind
        status = decodedStatus
        topCellName = decodedTopCellName
        ownershipMap = decodedOwnershipMap
        netAwareReport = decodedNetAwareReport
        evaluatedShapeCount = decodedEvaluatedShapeCount
        ownedShapeCount = decodedOwnedShapeCount
        unownedShapeCount = decodedUnownedShapeCount
        ignoredShapeCount = decodedIgnoredShapeCount
        exemptShapeCount = decodedExemptShapeCount
    }

    public func encode(to encoder: Encoder) throws {
        guard schemaVersion == Self.currentSchemaVersion, kind == Self.expectedKind else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Layout trust report envelope does not match the current schema."
                )
            )
        }

        let derivedValues = Self.derivedValues(ownershipMap: ownershipMap, netAwareReport: netAwareReport)
        if let errorDescription = Self.consistencyErrorDescription(
            status: status,
            topCellName: topCellName,
            evaluatedShapeCount: evaluatedShapeCount,
            ownedShapeCount: ownedShapeCount,
            unownedShapeCount: unownedShapeCount,
            ignoredShapeCount: ignoredShapeCount,
            exemptShapeCount: exemptShapeCount,
            derivedValues: derivedValues
        ) {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: errorDescription
                )
            )
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(kind, forKey: .kind)
        try container.encode(status, forKey: .status)
        try container.encode(topCellName, forKey: .topCellName)
        try container.encode(ownershipMap, forKey: .ownershipMap)
        try container.encode(netAwareReport, forKey: .netAwareReport)
        try container.encode(evaluatedShapeCount, forKey: .evaluatedShapeCount)
        try container.encode(ownedShapeCount, forKey: .ownedShapeCount)
        try container.encode(unownedShapeCount, forKey: .unownedShapeCount)
        try container.encode(ignoredShapeCount, forKey: .ignoredShapeCount)
        try container.encode(exemptShapeCount, forKey: .exemptShapeCount)
    }

    private static func validate(
        status: Status,
        topCellName: String,
        evaluatedShapeCount: Int,
        ownedShapeCount: Int,
        unownedShapeCount: Int,
        ignoredShapeCount: Int,
        exemptShapeCount: Int,
        derivedValues: DerivedValues,
        container: KeyedDecodingContainer<CodingKeys>
    ) throws {
        if let errorDescription = consistencyErrorDescription(
            status: status,
            topCellName: topCellName,
            evaluatedShapeCount: evaluatedShapeCount,
            ownedShapeCount: ownedShapeCount,
            unownedShapeCount: unownedShapeCount,
            ignoredShapeCount: ignoredShapeCount,
            exemptShapeCount: exemptShapeCount,
            derivedValues: derivedValues
        ) {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: errorDescription
                )
            )
        }
    }

    private static func consistencyErrorDescription(
        status: Status,
        topCellName: String,
        evaluatedShapeCount: Int,
        ownedShapeCount: Int,
        unownedShapeCount: Int,
        ignoredShapeCount: Int,
        exemptShapeCount: Int,
        derivedValues: DerivedValues
    ) -> String? {
        guard status == derivedValues.status else {
            return "Layout trust report status does not match the net-aware report."
        }
        guard topCellName == derivedValues.topCellName else {
            return "Layout trust report topCellName does not match the ownership map."
        }
        guard evaluatedShapeCount == derivedValues.evaluatedShapeCount else {
            return "Layout trust report evaluatedShapeCount does not match the ownership map."
        }
        guard ownedShapeCount == derivedValues.ownedShapeCount else {
            return "Layout trust report ownedShapeCount does not match the ownership map."
        }
        guard unownedShapeCount == derivedValues.unownedShapeCount else {
            return "Layout trust report unownedShapeCount does not match the ownership map."
        }
        guard ignoredShapeCount == derivedValues.ignoredShapeCount else {
            return "Layout trust report ignoredShapeCount does not match the ownership map."
        }
        guard exemptShapeCount == derivedValues.exemptShapeCount else {
            return "Layout trust report exemptShapeCount does not match the ownership map."
        }
        return nil
    }

    private struct DerivedValues {
        let status: Status
        let topCellName: String
        let evaluatedShapeCount: Int
        let ownedShapeCount: Int
        let unownedShapeCount: Int
        let ignoredShapeCount: Int
        let exemptShapeCount: Int
    }

    private static func derivedValues(
        ownershipMap: LayoutOwnershipMap,
        netAwareReport: NetAwareLayoutEvaluator.Report
    ) -> DerivedValues {
        DerivedValues(
            status: netAwareReport.passed ? .passed : .failed,
            topCellName: ownershipMap.topCellName,
            evaluatedShapeCount: ownershipMap.ownedCount + ownershipMap.unownedCount,
            ownedShapeCount: ownershipMap.ownedCount,
            unownedShapeCount: ownershipMap.unownedCount,
            ignoredShapeCount: ownershipMap.ignoredCount,
            exemptShapeCount: ownershipMap.exemptCount
        )
    }
}
