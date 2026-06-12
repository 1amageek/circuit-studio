import Foundation

/// Describes an analysis × corner matrix to execute over one netlist.
///
/// An empty `corners` list means each analysis runs once on the base
/// configuration; otherwise every analysis runs once per corner.
public struct AnalysisMatrixRequest: Sendable {
    public let source: String
    public let fileName: String?
    public let baseConfiguration: ProcessConfiguration?
    public let corners: [Corner]
    public let analyses: [AnalysisCommand]

    public init(
        source: String,
        fileName: String?,
        baseConfiguration: ProcessConfiguration? = nil,
        corners: [Corner] = [],
        analyses: [AnalysisCommand]
    ) {
        self.source = source
        self.fileName = fileName
        self.baseConfiguration = baseConfiguration
        self.corners = corners
        self.analyses = analyses
    }
}
