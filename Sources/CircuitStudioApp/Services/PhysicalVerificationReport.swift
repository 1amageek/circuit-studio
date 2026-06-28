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

    public var isReadyForPEX: Bool {
        drc.passed && lvs.passed && (externalSignoff?.isReadyForPEX ?? true)
    }
}
