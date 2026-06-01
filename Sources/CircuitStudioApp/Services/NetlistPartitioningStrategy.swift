import Foundation

/// Assigns each instance in a flat gate-level netlist to a physical block.
///
/// The returned array must contain exactly one entry for each `netlist.instances` element, each
/// entry must be in `0..<blockCount`, and every active block must receive at least one instance.
public protocol NetlistPartitioningStrategy: Sendable {
    func assignment(for netlist: GateLevelNetlist, blockCount: Int, rails: Set<String>) throws -> [Int]
}
