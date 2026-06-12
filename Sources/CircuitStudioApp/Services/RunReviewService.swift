import Foundation
import DesignFlowKernel
import XcircuitePackage

/// The review cockpit's data layer: everything it shows is read from
/// the `.xcircuite` run ledger — the same record the flow kernel and
/// the agents write — and the only thing it writes back is the human
/// decision (an approval record the kernel's approval gate consumes).
public struct RunReviewService: Sendable {

    /// One run as the reviewer sees it: the manifest verdict, each
    /// stage's gates and artifacts, and any decisions already taken.
    public struct RunReview: Sendable {
        public let runID: String
        public let status: XcircuiteRunStatus
        public let artifacts: [XcircuiteFileReference]
        public let stages: [StageReview]
        public let approvals: [XcircuiteApprovalRecord]
    }

    public struct StageReview: Sendable {
        public let result: FlowStageResult
        /// The stage's recorded human decision, when one exists.
        public let approval: XcircuiteApprovalRecord?
        /// True when the stage carries an approval gate that is still
        /// incomplete — the run is waiting on this reviewer.
        public var awaitingApproval: Bool {
            result.gates.contains { $0.gateID == "approval" && $0.status == .incomplete }
        }
    }

    private let store: XcircuitePackageStore

    public init(store: XcircuitePackageStore = XcircuitePackageStore()) {
        self.store = store
    }

    /// Every run the project manifest lists, newest last.
    public func listRuns(projectRoot: URL) throws -> [XcircuiteRunReference] {
        try store.loadManifest(forProjectAt: projectRoot).runs
    }

    /// The full review picture of one run, straight from the ledger.
    public func loadRun(runID: String, projectRoot: URL) throws -> RunReview {
        let package = XcircuitePackage(projectRoot: projectRoot)
        let runDirectory = try package.runDirectoryURL(for: runID)
        let manifest = try store.readJSON(
            XcircuiteRunManifest.self,
            from: runDirectory.appending(path: "manifest.json")
        )
        let approvals = try store.loadApprovals(runID: runID, inProjectAt: projectRoot)
        let approvalsByStage = Dictionary(
            approvals.map { ($0.stageID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var stages: [StageReview] = []
        let stagesDirectory = runDirectory.appending(path: "stages")
        if FileManager.default.fileExists(atPath: stagesDirectory.path(percentEncoded: false)) {
            let stageDirectories = try FileManager.default.contentsOfDirectory(
                at: stagesDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            for directory in stageDirectories {
                let resultURL = directory.appending(path: "result.json")
                guard FileManager.default.fileExists(atPath: resultURL.path(percentEncoded: false)) else {
                    continue
                }
                let result = try store.readJSON(FlowStageResult.self, from: resultURL)
                stages.append(StageReview(
                    result: result,
                    approval: approvalsByStage[result.stageID]
                ))
            }
        }

        return RunReview(
            runID: runID,
            status: manifest.status,
            artifacts: manifest.artifacts,
            stages: stages,
            approvals: approvals
        )
    }

    /// Records the reviewer's decision. The flow kernel's approval gate
    /// reads exactly this record on the next run of the same runID.
    public func decide(
        runID: String,
        stageID: String,
        verdict: XcircuiteApprovalRecord.Verdict,
        reviewer: String,
        note: String = "",
        projectRoot: URL
    ) throws -> XcircuiteApprovalRecord {
        let record = XcircuiteApprovalRecord(
            runID: runID,
            stageID: stageID,
            verdict: verdict,
            reviewer: reviewer,
            note: note
        )
        try store.writeApproval(record, inProjectAt: projectRoot)
        return record
    }
}
