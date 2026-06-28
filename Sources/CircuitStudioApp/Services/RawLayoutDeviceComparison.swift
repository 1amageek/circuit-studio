struct RawLayoutDeviceComparison: Sendable, Hashable {
    let parameterMismatches: [LVSVerificationReport.DeviceParameterMismatch]
    let duplicateDeviceNames: [String]
}
