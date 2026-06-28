struct FullLVSResult: Sendable, Hashable {
    var shorts: [LVSVerificationReport.PhysicalShort] = []
    var opens: [LVSVerificationReport.PhysicalOpen] = []
    var unconnectedPins: [LVSVerificationReport.Terminal] = []
    var terminalMismatches: [LVSVerificationReport.TerminalMismatch] = []
    var missingExternalPorts: [String] = []
    var invalidTerminals: [LVSVerificationReport.Terminal] = []
    var duplicateTerminals: [LVSVerificationReport.Terminal] = []
    var realizedNetNames: Set<String> = []
}
