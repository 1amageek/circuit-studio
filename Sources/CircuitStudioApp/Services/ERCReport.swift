import Foundation

/// The result of an electrical rule check on a gate-level netlist: the electrical-integrity
/// problems that LVS does not catch on its own (a floating gate input, a net driven by two
/// outputs, an undriven primary output, a driven net that goes nowhere). A clean report is a
/// precondition for tapeout — a floating input or a driver fight is a real-silicon failure,
/// not a geometry one.
public struct ERCReport: Sendable, Codable, Hashable {

    public enum Severity: String, Sendable, Codable, Hashable {
        case error     // a real-silicon failure: it fails the check
        case warning   // wasteful but not fatal: reported, does not fail the check
    }

    public enum Violation: Sendable, Codable, Hashable {
        /// A net is read by a gate but driven by nothing (no gate output, not a primary input).
        case floatingInput(net: String, consumers: [String])
        /// A net is driven by more than one source (a short / driver fight).
        case multipleDrivers(net: String, drivers: [String])
        /// A primary output net is driven by nothing.
        case undrivenOutput(net: String)
        /// A net is driven but read by nothing and is not a primary output (a dangling node).
        case danglingNet(net: String, driver: String)

        /// A floating input, a driver fight, or an undriven output is a hard failure; a
        /// dangling net is wasteful but works in silicon, so it is only a warning.
        public var severity: Severity {
            switch self {
            case .floatingInput, .multipleDrivers, .undrivenOutput: return .error
            case .danglingNet: return .warning
            }
        }

        public var ruleID: String {
            switch self {
            case .floatingInput: return "erc.floating-input"
            case .multipleDrivers: return "erc.multiple-drivers"
            case .undrivenOutput: return "erc.undriven-output"
            case .danglingNet: return "erc.dangling-net"
            }
        }

        public var message: String {
            switch self {
            case .floatingInput(let net, let consumers):
                return "net '\(net)' is read by \(consumers.joined(separator: ", ")) but has no driver (floating input)"
            case .multipleDrivers(let net, let drivers):
                return "net '\(net)' is driven by multiple sources: \(drivers.joined(separator: ", ")) (driver fight)"
            case .undrivenOutput(let net):
                return "primary output '\(net)' has no driver"
            case .danglingNet(let net, let driver):
                return "net '\(net)' is driven by \(driver) but read by nothing (dangling)"
            }
        }
    }

    public let designName: String
    public let violations: [Violation]

    public init(designName: String, violations: [Violation]) {
        self.designName = designName
        self.violations = violations
    }

    /// Passes when there are no ERROR-severity violations (warnings do not fail the check).
    public var passed: Bool { !violations.contains { $0.severity == .error } }
    public var errors: [Violation] { violations.filter { $0.severity == .error } }
    public var warnings: [Violation] { violations.filter { $0.severity == .warning } }
    public func violations(of ruleID: String) -> [Violation] { violations.filter { $0.ruleID == ruleID } }
}
