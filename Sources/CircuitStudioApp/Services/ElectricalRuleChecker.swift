import Foundation

/// Checks a `GateLevelNetlist` against the electrical rules that geometry signoff (DRC) and
/// even LVS can miss: every read net must have exactly one source, every primary output must
/// be driven, and no driven net may dangle. It is a TOOL-INDEPENDENT structural analysis (no
/// SPICE / Magic), so it always runs and is the cheapest tapeout gate to fail fast on.
public struct ElectricalRuleChecker: Sendable {

    public init() {}

    public func check(_ netlist: GateLevelNetlist) -> ERCReport {
        let rails: Set<String> = [netlist.vpwr, netlist.vgnd]
        let primaryInputs = Set(netlist.inputs)
        let primaryOutputs = Set(netlist.outputs)

        // Drivers and consumers of every net.
        var drivers: [String: [String]] = [:]     // net -> instance names that drive it
        var consumers: [String: [String]] = [:]    // net -> instance names that read it
        for inst in netlist.instances {
            drivers[netlist.driverNet(of: inst), default: []].append(inst.name)
            for gate in Set(inst.cell.devices.map(\.gate)) {
                let net = inst.net(gate)
                guard !rails.contains(net) else { continue }   // rail-tied gate input is a constant, not a signal
                consumers[net, default: []].append(inst.name)
            }
        }

        let allNets = Set(drivers.keys).union(consumers.keys).union(primaryOutputs).subtracting(rails)
        var violations: [ERCReport.Violation] = []
        for net in allNets.sorted() {
            let netDrivers = drivers[net] ?? []
            let netConsumers = consumers[net] ?? []
            let isPrimaryInput = primaryInputs.contains(net)
            let isPrimaryOutput = primaryOutputs.contains(net)
            // External sources count toward the driver total: a primary input is driven from
            // outside, so an internal driver on top of it is a second source.
            let sourceCount = netDrivers.count + (isPrimaryInput ? 1 : 0)

            if sourceCount > 1 {
                let named = netDrivers + (isPrimaryInput ? ["<primary-input>"] : [])
                violations.append(.multipleDrivers(net: net, drivers: named))
            }
            if !netConsumers.isEmpty && sourceCount == 0 {
                violations.append(.floatingInput(net: net, consumers: netConsumers))
            }
            if isPrimaryOutput && sourceCount == 0 {
                violations.append(.undrivenOutput(net: net))
            }
            if netConsumers.isEmpty && !isPrimaryOutput, let driver = netDrivers.first {
                violations.append(.danglingNet(net: net, driver: driver))
            }
        }
        return ERCReport(designName: netlist.name, violations: violations)
    }
}
