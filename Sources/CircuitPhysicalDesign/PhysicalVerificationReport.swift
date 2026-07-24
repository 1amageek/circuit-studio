import CircuitSignoff
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

    /// Reports whether the in-memory editor checks pass.
    ///
    /// This value is diagnostic only and never authorizes PEX or signoff.
    public var isLocalPreflightPassing: Bool {
        drc.passed && lvs.passed
    }

    /// Authorizes PEX only when local checks and retained external signoff pass.
    public var isReadyForPEX: Bool {
        isLocalPreflightPassing && externalSignoff?.isReadyForPEX == true
    }
}
