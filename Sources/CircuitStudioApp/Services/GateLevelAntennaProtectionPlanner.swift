import Foundation

public struct GateLevelAntennaProtectionPlanner: AntennaProtectionPlanProvider {
    private let ruleSet: AntennaProtectionRuleSet

    public init(ruleSet: AntennaProtectionRuleSet = AntennaProtectionRuleSet()) {
        self.ruleSet = ruleSet
    }

    public func plan(
        for netlist: GateLevelNetlist,
        candidates: [AntennaProtectionCandidate]
    ) throws -> AntennaProtectionPlan {
        try ruleSet.validate()

        let sites = candidates.sorted {
            if $0.net != $1.net { return $0.net < $1.net }
            if $0.instanceName != $1.instanceName { return $0.instanceName < $1.instanceName }
            return $0.gateName < $1.gateName
        }.compactMap { candidate -> AntennaProtectionPlan.Site? in
            guard ruleSet.requiresProtection(
                gateLoadCount: candidate.gateLoadCount,
                hasDiffusionDischargeAnchor: candidate.hasDiffusionDischargeAnchor,
                spanPerGateMicrons: candidate.spanPerGateMicrons
            ) else {
                return nil
            }
            return AntennaProtectionPlan.Site(
                id: candidate.id,
                net: candidate.net,
                instanceName: candidate.instanceName,
                gateName: candidate.gateName,
                centerXMicrons: candidate.centerXMicrons,
                trackYMicrons: candidate.trackYMicrons,
                gateLoadCount: candidate.gateLoadCount,
                hasDiffusionDischargeAnchor: candidate.hasDiffusionDischargeAnchor,
                spanMicrons: candidate.spanMicrons,
                spanPerGateMicrons: candidate.spanPerGateMicrons,
                strategy: .diffusionTie,
                reason: reason(for: candidate)
            )
        }

        return AntennaProtectionPlan(
            designName: netlist.name,
            ruleSet: ruleSet,
            sites: sites
        )
    }

    private func reason(for candidate: AntennaProtectionCandidate) -> String {
        if ruleSet.protectsLocalGateContacts {
            return "gate contact met1 riser requires a same-stage diffusion discharge anchor"
        }
        if !candidate.hasDiffusionDischargeAnchor && ruleSet.protectsAllUnanchoredGateNets {
            return "gate net lacks an in-scope diffusion discharge anchor"
        }
        return candidate.spanPerGateMicrons > ruleSet.maxSpanPerGateMicrons
            ? "gate net exceeds antenna span budget"
            : "gate net is within antenna span budget"
    }
}
