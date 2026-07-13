import Foundation
import CircuiteFoundation
import Xcircuite
import DesignFlowKernel

public struct RunReviewSignoffRepairPlanningResult: Sendable, Hashable, Codable {
    public let runID: String
    public let formulationID: String
    public let problemID: String
    public let drcRepairHintPath: String?
    public let lvsRepairHintPath: String?
    public let actionDomainArtifact: ArtifactReference
    public let repairFormulationArtifact: ArtifactReference
    public let planningProblemArtifact: ArtifactReference
    public let sourceReports: [XcircuiteSignoffRepairFormulationResult.SourceReport]
    public let actionRecord: XcircuiteRunActionRecord

    public init(
        runID: String,
        formulationID: String,
        problemID: String,
        drcRepairHintPath: String?,
        lvsRepairHintPath: String?,
        actionDomainArtifact: ArtifactReference,
        repairFormulationArtifact: ArtifactReference,
        planningProblemArtifact: ArtifactReference,
        sourceReports: [XcircuiteSignoffRepairFormulationResult.SourceReport],
        actionRecord: XcircuiteRunActionRecord
    ) {
        self.runID = runID
        self.formulationID = formulationID
        self.problemID = problemID
        self.drcRepairHintPath = drcRepairHintPath
        self.lvsRepairHintPath = lvsRepairHintPath
        self.actionDomainArtifact = actionDomainArtifact
        self.repairFormulationArtifact = repairFormulationArtifact
        self.planningProblemArtifact = planningProblemArtifact
        self.sourceReports = sourceReports
        self.actionRecord = actionRecord
    }
}
