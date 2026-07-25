import DRCCore
import LVSCore

public struct LiveSignoffExecutionResult: Sendable {
    public let drc: DRCExecutionResult
    public let lvs: LVSExecutionResult
    public let review: ExternalSignoffReview

    public init(
        drc: DRCExecutionResult,
        lvs: LVSExecutionResult,
        review: ExternalSignoffReview
    ) {
        self.drc = drc
        self.lvs = lvs
        self.review = review
    }
}
