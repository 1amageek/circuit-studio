import Foundation

public struct LayoutOwnershipPolicy: Sendable, Hashable, Codable {
    public let evaluatedLayerNames: Set<String>
    public let netNameProperty: String
    public let exemptionProperty: String
    public let exemptPurposeValues: Set<String>
    public static let defaultExemptionProperty = "layout.trust.purpose"

    public init(
        evaluatedLayerNames: Set<String> = LayoutOwnershipPolicy.defaultEvaluatedLayerNames,
        netNameProperty: String = NetAwareLayoutEvaluator.netNameProperty,
        exemptionProperty: String = LayoutOwnershipPolicy.defaultExemptionProperty,
        exemptPurposeValues: Set<String> = ["device", "fill", "tap", "guard", "label-only", "non-net"]
    ) {
        self.evaluatedLayerNames = Set(evaluatedLayerNames.map { $0.lowercased() })
        self.netNameProperty = netNameProperty
        self.exemptionProperty = exemptionProperty
        self.exemptPurposeValues = Set(exemptPurposeValues.map { $0.lowercased() })
    }

    public static let defaultEvaluatedLayerNames: Set<String> = [
        "li1", "mcon",
        "met1", "met2", "met3", "met4", "met5",
        "m1", "m2", "m3", "m4", "m5",
        "via", "via1", "via2", "via3", "via4",
        "contact", "licon1",
        "metal1", "metal2", "metal3", "metal4", "metal5",
    ]

    public func evaluates(layerName: String) -> Bool {
        evaluatedLayerNames.contains(layerName.lowercased())
    }

    public func isExemptPurpose(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !trimmed.isEmpty && exemptPurposeValues.contains(trimmed)
    }
}
