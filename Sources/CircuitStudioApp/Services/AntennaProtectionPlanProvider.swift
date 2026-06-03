import Foundation

public protocol AntennaProtectionPlanProvider: Sendable {
    func plan(
        for netlist: GateLevelNetlist,
        candidates: [AntennaProtectionCandidate]
    ) throws -> AntennaProtectionPlan
}
