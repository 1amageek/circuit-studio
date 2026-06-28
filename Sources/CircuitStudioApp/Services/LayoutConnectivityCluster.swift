import Foundation

struct LayoutConnectivityCluster: Sendable, Hashable {
    let id: Int
    let terminals: Set<TerminalKey>
    let netIDs: Set<UUID>
    let externalPortNames: Set<String>
}
