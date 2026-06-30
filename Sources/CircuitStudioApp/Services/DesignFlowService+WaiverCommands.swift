import Foundation

extension DesignFlowService {
    func applyWaiverEditProposalAndRunPostVerification(
        _ command: DesignFlowCommand
    ) async throws -> DesignFlowCommandResult {
        let applyResult = try applyWaiverEditProposal(command)
        let verificationResult = try await runPostWaiverEditVerification(command)
        let actionRecordIDs = [
            applyResult.message,
            verificationResult.message,
        ].compactMap { $0 }
        return DesignFlowCommandResult(
            kind: command.kind,
            fixtureName: verificationResult.fixtureName,
            designName: verificationResult.designName,
            runID: verificationResult.runID,
            projectRootPath: verificationResult.projectRootPath,
            readyForPEX: verificationResult.readyForPEX,
            technologyPackageID: verificationResult.technologyPackageID,
            technologyPackagePath: verificationResult.technologyPackagePath,
            actionLogPath: verificationResult.actionLogPath,
            layoutTrustPassed: verificationResult.layoutTrustPassed,
            layoutTrustReportPath: verificationResult.layoutTrustReportPath,
            layoutTrustReport: verificationResult.layoutTrustReport,
            verificationReportPath: verificationResult.verificationReportPath,
            verificationReport: verificationResult.verificationReport,
            actionRecordIDs: actionRecordIDs,
            message: verificationResult.message
        )
    }

    func runPostWaiverEditVerification(_ command: DesignFlowCommand) async throws -> DesignFlowCommandResult {
        guard let projectRootPath = command.projectRootPath else {
            throw DesignFlowCommandError.missingProjectRoot
        }
        guard let runID = command.runID else {
            throw DesignFlowCommandError.missingRunID
        }
        guard let reviewer = command.approvalReviewer else {
            throw DesignFlowCommandError.missingApprovalReviewer
        }
        guard let waiverReviewID = command.waiverReviewID else {
            throw DesignFlowCommandError.missingWaiverReviewID
        }
        guard let waiverProposalID = command.waiverProposalID else {
            throw DesignFlowCommandError.missingWaiverProposalID
        }

        let verificationResult = try await runVerification(command)
        guard let verificationReport = verificationResult.verificationReport,
              let verificationReportPath = verificationResult.verificationReportPath else {
            throw DesignFlowCommandError.missingVerificationReport
        }
        let projectRoot = URL(filePath: projectRootPath)
        let record = try RunReviewService().recordWaiverEditVerification(
            runID: runID,
            waiverReviewID: waiverReviewID,
            proposalID: waiverProposalID,
            reviewer: reviewer,
            verificationReport: verificationReport,
            verificationReportURL: URL(filePath: verificationReportPath),
            layoutTrustReportURL: verificationResult.layoutTrustReportPath.map { URL(filePath: $0) },
            note: command.approvalNote ?? "",
            projectRoot: projectRoot
        )
        return DesignFlowCommandResult(
            kind: command.kind,
            fixtureName: verificationResult.fixtureName,
            designName: verificationResult.designName,
            runID: runID,
            projectRootPath: projectRootPath,
            readyForPEX: verificationResult.readyForPEX,
            technologyPackageID: verificationResult.technologyPackageID,
            technologyPackagePath: verificationResult.technologyPackagePath,
            actionLogPath: actionLogPath(projectRoot: projectRoot, runID: runID),
            layoutTrustPassed: verificationResult.layoutTrustPassed,
            layoutTrustReportPath: verificationResult.layoutTrustReportPath,
            layoutTrustReport: verificationResult.layoutTrustReport,
            verificationReportPath: verificationReportPath,
            verificationReport: verificationReport,
            actionRecordIDs: [record.actionID],
            message: record.actionID
        )
    }

    func applyWaiverEditProposal(_ command: DesignFlowCommand) throws -> DesignFlowCommandResult {
        guard let projectRootPath = command.projectRootPath else {
            throw DesignFlowCommandError.missingProjectRoot
        }
        guard let runID = command.runID else {
            throw DesignFlowCommandError.missingRunID
        }
        guard let reviewer = command.approvalReviewer else {
            throw DesignFlowCommandError.missingApprovalReviewer
        }
        guard let waiverReviewID = command.waiverReviewID else {
            throw DesignFlowCommandError.missingWaiverReviewID
        }
        guard let waiverProposalID = command.waiverProposalID else {
            throw DesignFlowCommandError.missingWaiverProposalID
        }

        let projectRoot = URL(filePath: projectRootPath)
        let record = try RunReviewService().applyWaiverEditProposal(
            runID: runID,
            waiverReviewID: waiverReviewID,
            proposalID: waiverProposalID,
            reviewer: reviewer,
            note: command.approvalNote ?? "",
            projectRoot: projectRoot
        )
        return DesignFlowCommandResult(
            kind: command.kind,
            runID: runID,
            projectRootPath: projectRootPath,
            actionLogPath: actionLogPath(projectRoot: projectRoot, runID: runID),
            actionRecordIDs: [record.actionID],
            message: record.actionID
        )
    }
}
