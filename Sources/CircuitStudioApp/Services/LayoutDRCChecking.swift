import CircuitSignoff
import Foundation
import LayoutCore

/// Checks a layout document against a foundry DRC and returns the structured report.
/// Abstracting the check (rather than calling Magic directly) lets the physical design
/// loop depend on the contract, not the toolchain — testable and substitutable.
public protocol LayoutDRCChecking: Sendable {
    /// Export `document`'s `cell` and run DRC on it, writing artifacts under `directory`.
    func check(_ document: LayoutDocument, cell: String, in directory: URL) async throws -> ExternalSignoffToolReport
}
