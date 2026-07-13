public struct PhysicalVerificationReport: Sendable, Hashable {
    public let drc: DRCVerificationReport
    public let lvs: LVSVerificationReport
    public let externalSignoff: ExternalSignoffReview?

    public init(
        drc: DRCVerificationReport,
        lvs: LVSVerificationReport,
        externalSignoff: ExternalSignoffReview? = nil
    ) {
        self.drc = drc
        self.lvs = lvs
        self.externalSignoff = externalSignoff
    }

    /// Local editor preflight readiness. Production flow readiness is derived
    /// from retained LVSEngine v2 and DRC artifacts, never from this property.
    public var isReadyForPEX: Bool {
        drc.passed && lvs.passed && (externalSignoff?.isReadyForPEX ?? true)
    }
}
