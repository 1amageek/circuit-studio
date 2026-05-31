import Foundation

/// The static IR-drop result for a power grid: the worst cell's IR drop against its budget,
/// plus the effective supply each cell actually sees. A failing result means a cell is
/// starved of voltage — a real-silicon functional/timing hazard, not a geometry one.
public struct IRDropResult: Sendable, Hashable, Codable {
    public let supplyVoltage: Double
    public let maxIRDropVolts: Double
    public let worstTapLabel: String
    public let budgetVolts: Double
    public let effectiveSupplyByTap: [String: Double]

    public init(supplyVoltage: Double, maxIRDropVolts: Double, worstTapLabel: String,
                budgetVolts: Double, effectiveSupplyByTap: [String: Double]) {
        self.supplyVoltage = supplyVoltage
        self.maxIRDropVolts = maxIRDropVolts
        self.worstTapLabel = worstTapLabel
        self.budgetVolts = budgetVolts
        self.effectiveSupplyByTap = effectiveSupplyByTap
    }

    public var passed: Bool { maxIRDropVolts <= budgetVolts }
    public var maxIRDropFraction: Double { supplyVoltage > 0 ? maxIRDropVolts / supplyVoltage : .infinity }
}
