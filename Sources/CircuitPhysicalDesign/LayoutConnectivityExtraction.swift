struct LayoutConnectivityExtraction: Sendable, Hashable {
    let clusters: [LayoutConnectivityCluster]
    let terminalToCluster: [TerminalKey: Int]
    let terminalClusterIDs: [TerminalKey: Set<Int>]
    let metadataTerminals: Set<TerminalKey>
    let invalidTerminals: [LVSVerificationReport.Terminal]
}
