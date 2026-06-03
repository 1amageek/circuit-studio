import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Antenna protection planner")
struct AntennaProtectionPlannerTests {
    @Test("Primary gate nets are protected without hardcoded net names", .timeLimit(.minutes(1)))
    func primaryGateNetsAreProtected() throws {
        let netlist = GateLevelNetlist.inverterChain(name: "chain3", stages: 3, input: "a", output: "y")
        let plan = try Sky130CircuitSynthesizer().antennaProtectionPlan(for: netlist)

        #expect(plan.designName == netlist.name)
        #expect(Set(plan.sites.map(\.net)).contains("a"))
        #expect(plan.sites.count == 3)
        #expect(plan.sites.allSatisfy { $0.strategy == .diffusionTie })
    }

    @Test("The rule set can distinguish local-contact protection from net-budget protection",
          .timeLimit(.minutes(1)))
    func ruleSetSeparatesLocalContactAndBudgetProtection() throws {
        let netlist = GateLevelNetlist.inverterChain(name: "chain4", stages: 4, input: "in", output: "out")
        let synth = Sky130CircuitSynthesizer()
        let defaultPlan = try synth.antennaProtectionPlan(for: netlist)
        let budgetOnlyPlanner = GateLevelAntennaProtectionPlanner(ruleSet: AntennaProtectionRuleSet(
            protectsLocalGateContacts: false
        ))
        let budgetOnlyPlan = try budgetOnlyPlanner.plan(
            for: netlist,
            candidates: try synth.antennaProtectionCandidates(for: netlist)
        )

        #expect(Set(defaultPlan.sites.map(\.net)).isSuperset(of: Set(["in", "c1", "c2", "c3"])))
        #expect(Set(budgetOnlyPlan.sites.map(\.net)) == ["in"])
    }

    @Test("ACC-4 protection targets are derived from topology, not from ACC-specific literals",
          .timeLimit(.minutes(1)))
    func acc4ProtectionTargetsComeFromTopology() throws {
        let netlist = ACC4CPUGenerator().gateLevelNetlist(name: "acc4_plan")
        let plan = try Sky130CircuitSynthesizer().antennaProtectionPlan(for: netlist)

        let protectedNets = Set(plan.sites.map(\.net))
        #expect(Set(netlist.inputs).isSubset(of: protectedNets))
        #expect(plan.sites.allSatisfy { $0.gateLoadCount > 0 })
        #expect(plan.sites.contains {
            netlist.drivenNets.contains($0.net)
                && $0.spanPerGateMicrons > plan.ruleSet.maxSpanPerGateMicrons
        })
    }

    @Test("Antenna protection site IDs do not collide when names contain separators",
          .timeLimit(.minutes(1)))
    func antennaProtectionSiteIDsDoNotCollideWhenNamesContainSeparators() throws {
        let netlist = GateLevelNetlist(
            name: "site_id_collision",
            instances: [
                GateLevelNetlist.Instance(
                    name: "a.b",
                    cell: .inverter(name: "inv0", input: "c"),
                    netMap: ["c": "d", "Y": "y0"]
                ),
                GateLevelNetlist.Instance(
                    name: "a",
                    cell: .inverter(name: "inv1", input: "b.c"),
                    netMap: ["b.c": "d", "Y": "y1"]
                ),
            ],
            inputs: ["d"],
            outputs: ["y0", "y1"]
        )
        let candidates = try Sky130CircuitSynthesizer().antennaProtectionCandidates(for: netlist)

        #expect(candidates.count == 2)
        #expect(Set(candidates.map(\.id)).count == candidates.count)
    }

    @Test("Synthesized layout materializes one diffusion tie per planned site", .timeLimit(.minutes(1)))
    func synthesizedLayoutMaterializesDiffusionTies() throws {
        let netlist = GateLevelNetlist.and2(name: "and2_protected")
        let synth = Sky130CircuitSynthesizer()
        let synthesis = try synth.synthesisResult(for: netlist)
        let plan = synthesis.antennaProtectionPlan
        let topCell = try #require(synthesis.document.cells.first)
        let tieShapes = topCell.shapes.filter {
            $0.properties[Sky130AntennaTieGenerator.protectionProperty] == "true"
        }
        let protectedNets = Set(tieShapes.compactMap {
            $0.properties[Sky130AntennaTieGenerator.netNameProperty]
        })
        let materializedSiteIDs = Set(tieShapes.compactMap {
            $0.properties[Sky130AntennaTieGenerator.siteIDProperty]
        })

        #expect(plan.sites.count == 3)
        #expect(tieShapes.count == plan.sites.count * 9)
        #expect(protectedNets == Set(plan.sites.map(\.net)))
        #expect(materializedSiteIDs == plan.siteIDs)
        #expect(plan.sites.allSatisfy { !$0.instanceName.isEmpty && !$0.gateName.isEmpty })
        #expect(plan.sites.allSatisfy { $0.centerXMicrons.isFinite && $0.trackYMicrons.isFinite })
    }

    @Test("Planner site geometry must match the routed candidate", .timeLimit(.minutes(1)))
    func plannerSiteGeometryMustMatchRoutedCandidate() throws {
        let netlist = GateLevelNetlist.and2(name: "and2_inconsistent_protection")
        let expectedID = try #require(Sky130CircuitSynthesizer().antennaProtectionCandidates(for: netlist).first?.id)
        let synth = Sky130CircuitSynthesizer(antennaProtectionPlanProvider: InconsistentAntennaProtectionPlanner())

        #expect(throws: Sky130CircuitSynthesizer.RouteError.inconsistentAntennaProtectionSiteID(expectedID)) {
            try synth.synthesisResult(for: netlist)
        }
    }

    @Test("Public plan API validates provider output before returning it", .timeLimit(.minutes(1)))
    func publicPlanAPIValidatesProviderOutputBeforeReturningIt() throws {
        let netlist = GateLevelNetlist.and2(name: "and2_public_plan_validation")
        let expectedID = try #require(Sky130CircuitSynthesizer().antennaProtectionCandidates(for: netlist).first?.id)
        let synth = Sky130CircuitSynthesizer(antennaProtectionPlanProvider: InconsistentAntennaProtectionPlanner())

        #expect(throws: Sky130CircuitSynthesizer.RouteError.inconsistentAntennaProtectionSiteID(expectedID)) {
            try synth.antennaProtectionPlan(for: netlist)
        }
    }

    @Test("Antenna protection plans are bound to the routed design name", .timeLimit(.minutes(1)))
    func antennaProtectionPlansAreBoundToRoutedDesignName() throws {
        let netlist = GateLevelNetlist.and2(name: "and2_design_name_validation")
        let synth = Sky130CircuitSynthesizer(antennaProtectionPlanProvider: WrongDesignAntennaProtectionPlanner())

        #expect(throws: Sky130CircuitSynthesizer.RouteError.inconsistentAntennaProtectionPlanDesignName(
            expected: netlist.name,
            actual: "other-design"
        )) {
            try synth.antennaProtectionPlan(for: netlist)
        }
    }

    @Test("Duplicate gate-level drivers fail with a typed route error", .timeLimit(.minutes(1)))
    func duplicateGateLevelDriversFailWithTypedRouteError() throws {
        let netlist = GateLevelNetlist(
            name: "duplicate_driver",
            instances: [
                GateLevelNetlist.Instance(
                    name: "g0",
                    cell: .inverter(name: "inv"),
                    netMap: ["A": "a", "Y": "n"]
                ),
                GateLevelNetlist.Instance(
                    name: "g1",
                    cell: .inverter(name: "inv"),
                    netMap: ["A": "b", "Y": "n"]
                ),
            ],
            inputs: ["a", "b"],
            output: "n"
        )

        #expect(throws: Sky130CircuitSynthesizer.RouteError.duplicateDriverNet("n")) {
            try Sky130CircuitSynthesizer().synthesisResult(for: netlist)
        }
    }

    @Test("Invalid antenna rule values fail loud", .timeLimit(.minutes(1)))
    func invalidRuleValuesFailLoud() throws {
        let netlist = GateLevelNetlist.inverterChain(name: "invalid_rule", stages: 2, input: "a", output: "y")
        let planner = GateLevelAntennaProtectionPlanner(ruleSet: AntennaProtectionRuleSet(
            maxSpanPerGateMicrons: .nan
        ))
        let candidates = try Sky130CircuitSynthesizer().antennaProtectionCandidates(for: netlist)

        #expect(throws: AntennaProtectionRuleSetError.invalidMaxSpanPerGateMicrons) {
            try planner.plan(for: netlist, candidates: candidates)
        }
    }

    @Test("Antenna protection artifact writer rejects invalid plans before writing", .timeLimit(.minutes(1)))
    func antennaProtectionArtifactWriterRejectsInvalidPlansBeforeWriting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "antenna-plan-validation-\(UUID().uuidString)")
        let url = directory.appending(path: "plan.json")
        let invalidPlan = AntennaProtectionPlan(
            designName: "unit",
            ruleSet: AntennaProtectionRuleSet(),
            sites: [
                antennaPlanSite(id: "duplicate"),
                antennaPlanSite(id: "duplicate"),
            ]
        )

        #expect(throws: AntennaProtectionPlanValidationError.duplicateSiteID("duplicate")) {
            try AntennaProtectionArtifactWriter().write(invalidPlan, to: url)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }
}

private struct WrongDesignAntennaProtectionPlanner: AntennaProtectionPlanProvider {
    func plan(
        for netlist: GateLevelNetlist,
        candidates: [AntennaProtectionCandidate]
    ) throws -> AntennaProtectionPlan {
        AntennaProtectionPlan(
            designName: "other-design",
            ruleSet: AntennaProtectionRuleSet(),
            sites: []
        )
    }
}

private func antennaPlanSite(id: String) -> AntennaProtectionPlan.Site {
    AntennaProtectionPlan.Site(
        id: id,
        net: "a",
        instanceName: "g0",
        gateName: "A",
        centerXMicrons: 1.0,
        trackYMicrons: 2.0,
        gateLoadCount: 1,
        hasDiffusionDischargeAnchor: false,
        spanMicrons: 10.0,
        spanPerGateMicrons: 10.0,
        strategy: .diffusionTie,
        reason: "unit fixture"
    )
}

private struct InconsistentAntennaProtectionPlanner: AntennaProtectionPlanProvider {
    func plan(
        for netlist: GateLevelNetlist,
        candidates: [AntennaProtectionCandidate]
    ) throws -> AntennaProtectionPlan {
        guard let candidate = candidates.first else {
            return AntennaProtectionPlan(
                designName: netlist.name,
                ruleSet: AntennaProtectionRuleSet(),
                sites: []
            )
        }
        return AntennaProtectionPlan(
            designName: netlist.name,
            ruleSet: AntennaProtectionRuleSet(),
            sites: [
                AntennaProtectionPlan.Site(
                    id: candidate.id,
                    net: candidate.net,
                    instanceName: candidate.instanceName,
                    gateName: candidate.gateName,
                    centerXMicrons: candidate.centerXMicrons + 1.0,
                    trackYMicrons: candidate.trackYMicrons,
                    gateLoadCount: candidate.gateLoadCount,
                    hasDiffusionDischargeAnchor: candidate.hasDiffusionDischargeAnchor,
                    spanMicrons: candidate.spanMicrons,
                    spanPerGateMicrons: candidate.spanPerGateMicrons,
                    strategy: .diffusionTie,
                    reason: "inconsistent fixture"
                ),
            ]
        )
    }
}
