import Foundation
import Testing
@testable import CircuitStudioApp

/// BC3.1 — electrical rule check. Tool-independent: a clean synthesized design passes, and
/// each real-silicon electrical fault (floating input, driver fight, undriven output) is
/// caught, while a harmless dangling net is only a warning.
@Suite("Electrical rule checker")
struct ElectricalRuleCheckerTests {

    private let erc = ElectricalRuleChecker()

    @Test("The synthesized ACC-4 core and ALU pass ERC (no electrical errors)")
    func cleanDesignsPass() {
        let cpu = erc.check(ACC4CPUGenerator().gateLevelNetlist())
        #expect(cpu.passed, "ACC-4 ERC errors: \(cpu.errors.map(\.message))")
        let alu = erc.check(Sky130ALUGenerator(bits: 4).gateLevelNetlist())
        #expect(alu.passed, "ALU ERC errors: \(alu.errors.map(\.message))")
    }

    @Test("A floating gate input is caught (read net with no driver)")
    func floatingInputCaught() {
        // g0 reads net "x", which is neither driven nor a primary input.
        let netlist = GateLevelNetlist(name: "flt", instances: [
            .init(name: "g0", cell: .inverter(name: "inv"), netMap: ["A": "x", "Y": "y"]),
        ], inputs: [], output: "y")
        let report = erc.check(netlist)
        #expect(!report.passed)
        #expect(report.violations(of: "erc.floating-input").count == 1)
    }

    @Test("A driver fight is caught (one net driven by two gates)")
    func multipleDriversCaught() {
        let netlist = GateLevelNetlist(name: "fight", instances: [
            .init(name: "g0", cell: .inverter(name: "inv"), netMap: ["A": "a", "Y": "y"]),
            .init(name: "g1", cell: .inverter(name: "inv"), netMap: ["A": "a", "Y": "y"]),   // also drives y
        ], inputs: ["a"], output: "y")
        let report = erc.check(netlist)
        #expect(!report.passed)
        #expect(report.violations(of: "erc.multiple-drivers").count == 1)
    }

    @Test("An undriven primary output is caught")
    func undrivenOutputCaught() {
        // g0 drives "m"; the declared output "y" is driven by nothing.
        let netlist = GateLevelNetlist(name: "undr", instances: [
            .init(name: "g0", cell: .inverter(name: "inv"), netMap: ["A": "a", "Y": "m"]),
        ], inputs: ["a"], output: "y")
        let report = erc.check(netlist)
        #expect(!report.passed)
        #expect(report.violations(of: "erc.undriven-output").count == 1)
    }

    @Test("A dangling net is only a warning (does not fail the check)")
    func danglingNetIsWarning() {
        // g1 drives "z", which nothing reads and is not the output — wasteful, not fatal.
        let netlist = GateLevelNetlist(name: "dang", instances: [
            .init(name: "g0", cell: .inverter(name: "inv"), netMap: ["A": "a", "Y": "y"]),
            .init(name: "g1", cell: .inverter(name: "inv"), netMap: ["A": "a", "Y": "z"]),
        ], inputs: ["a"], output: "y")
        let report = erc.check(netlist)
        #expect(report.passed, "dangling should not fail: \(report.errors.map(\.message))")
        #expect(report.violations(of: "erc.dangling-net").count == 1)
        #expect(report.warnings.count == 1)
    }
}
