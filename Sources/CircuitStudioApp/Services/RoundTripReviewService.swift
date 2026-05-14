import CryptoKit
import Foundation
import CircuitStudioCore

public enum RoundTripReviewServiceError: Error, LocalizedError, Equatable {
    case missingManifest(URL)

    public var errorDescription: String? {
        switch self {
        case .missingManifest(let url):
            return "Round-trip manifest does not exist: \(url.path(percentEncoded: false))"
        }
    }
}

public struct RoundTripReviewService: Sendable {
    public init() {}

    public func loadReview(projectRoot: URL, runID: String) throws -> RoundTripReviewSummary {
        try Self.validateRunID(runID)
        let manifestURL = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: runID)
            .appending(path: "round-trip-manifest.json")
        return try loadReview(manifestURL: manifestURL)
    }

    public func loadReview(manifestURL: URL) throws -> RoundTripReviewSummary {
        guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            throw RoundTripReviewServiceError.missingManifest(manifestURL)
        }

        let manifest = try readJSON(
            HeadlessRoundTripService.Manifest.self,
            from: manifestURL,
            context: "round-trip manifest"
        )
        let resolver = RoundTripArtifactResolver(manifestURL: manifestURL)
        var diagnostics: [String] = []
        var warnings: [String] = []
        let artifactSummaries = manifest.artifacts.map { artifact in
            summarize(
                artifact: artifact,
                resolver: resolver,
                diagnostics: &diagnostics,
                warnings: &warnings
            )
        }

        let signoff = loadSignoffSummary(
            from: manifest.artifacts,
            resolver: resolver,
            diagnostics: &diagnostics,
            warnings: &warnings
        )
        let comparison = loadComparisonSummary(
            from: manifest.artifacts,
            resolver: resolver,
            diagnostics: &diagnostics,
            warnings: &warnings
        )
        let approvals = loadApprovalRecords(
            manifest: manifest,
            manifestURL: manifestURL,
            resolver: resolver,
            diagnostics: &diagnostics,
            warnings: &warnings
        )
        let stageSummaries = manifest.stages.map {
            RoundTripReviewStageSummary(
                name: $0.name,
                status: $0.status,
                message: $0.message,
                durationSeconds: $0.durationSeconds
            )
        }

        return RoundTripReviewSummary(
            runID: manifest.runID,
            title: manifest.title,
            createdAt: manifest.createdAt,
            manifestPath: manifestURL.path(percentEncoded: false),
            status: status(for: manifest, comparison: comparison, diagnostics: diagnostics),
            isRoundTripComplete: manifest.isRoundTripComplete,
            isReadyForPEX: manifest.isReadyForPEX,
            stages: stageSummaries,
            artifacts: artifactSummaries,
            externalSignoff: signoff,
            postLayoutComparison: comparison,
            approvals: approvals,
            bottleneckSummary: manifest.bottleneckSummary,
            diagnostics: diagnostics,
            warnings: warnings,
            recommendations: recommendations(
                manifest: manifest,
                signoff: signoff,
                comparison: comparison,
                diagnostics: diagnostics,
                warnings: warnings
            )
        )
    }

    private func loadApprovalRecords(
        manifest: HeadlessRoundTripService.Manifest,
        manifestURL: URL,
        resolver: RoundTripArtifactResolver,
        diagnostics: inout [String],
        warnings: inout [String]
    ) -> [GateApprovalRecord] {
        guard let projectRoot = projectRoot(fromManifestURL: manifestURL) else {
            return []
        }
        do {
            let records = try FlowRunGovernanceService().approvalRecords(
                projectRoot: projectRoot,
                runID: manifest.runID
            )
            validateApprovalRecords(
                records,
                resolver: resolver,
                diagnostics: &diagnostics,
                warnings: &warnings
            )
            return records
        } catch {
            diagnostics.append("Failed to load gate approval records: \(error.localizedDescription)")
            return []
        }
    }

    private func validateApprovalRecords(
        _ records: [GateApprovalRecord],
        resolver: RoundTripArtifactResolver,
        diagnostics: inout [String],
        warnings: inout [String]
    ) {
        for record in records {
            do {
                let url = try approvalTargetURL(record: record, resolver: resolver, warnings: &warnings)
                let path = url.path(percentEncoded: false)
                guard FileManager.default.fileExists(atPath: path) else {
                    appendUnique([
                        "Gate approval target artifact is missing: \(record.gateID.rawValue) at \(path)",
                    ], to: &diagnostics)
                    continue
                }
                let actualHash = try sha256(of: url)
                guard actualHash == record.targetArtifactSHA256 else {
                    appendUnique([
                        "Gate approval target artifact hash mismatch: \(record.gateID.rawValue) at \(path)",
                    ], to: &diagnostics)
                    continue
                }
            } catch {
                appendUnique([
                    "Gate approval target artifact is invalid: \(record.gateID.rawValue): \(error.localizedDescription)",
                ], to: &diagnostics)
            }
        }
    }

    private func approvalTargetURL(
        record: GateApprovalRecord,
        resolver: RoundTripArtifactResolver,
        warnings: inout [String]
    ) throws -> URL {
        switch record.targetArtifactPathBase {
        case .runDirectory:
            let resolution = try resolver.resolve(
                path: record.targetArtifactPath,
                kind: record.targetArtifactKind ?? record.gateID.rawValue
            )
            appendUnique(resolution.warnings, to: &warnings)
            return resolution.url
        case .absolute:
            appendUnique([
                "Gate approval record uses a legacy absolute target artifact path: \(record.targetArtifactPath)",
            ], to: &warnings)
            return URL(filePath: record.targetArtifactPath)
        }
    }

    private func summarize(
        artifact: HeadlessRoundTripService.Artifact,
        resolver: RoundTripArtifactResolver,
        diagnostics: inout [String],
        warnings: inout [String]
    ) -> RoundTripReviewArtifactSummary {
        guard let url = resolveArtifactURL(
            artifact,
            resolver: resolver,
            diagnostics: &diagnostics,
            warnings: &warnings
        ) else {
            return RoundTripReviewArtifactSummary(
                kind: artifact.kind,
                path: artifact.path,
                sourcePath: artifact.sourcePath,
                exists: false,
                isCapturedCopy: artifact.sourcePath != nil
            )
        }
        let path = url.path(percentEncoded: false)
        let exists = FileManager.default.fileExists(atPath: path)
        if !exists {
            diagnostics.append("Artifact is missing: \(artifact.kind) at \(path)")
        }
        return RoundTripReviewArtifactSummary(
            kind: artifact.kind,
            path: path,
            sourcePath: artifact.sourcePath,
            exists: exists,
            isCapturedCopy: artifact.sourcePath != nil
        )
    }

    private func loadSignoffSummary(
        from artifacts: [HeadlessRoundTripService.Artifact],
        resolver: RoundTripArtifactResolver,
        diagnostics: inout [String],
        warnings: inout [String]
    ) -> RoundTripReviewSignoffSummary? {
        guard let artifact = artifacts.first(where: { $0.kind == "external-signoff-review" }) else {
            return nil
        }
        guard let url = resolveArtifactURL(
            artifact,
            resolver: resolver,
            diagnostics: &diagnostics,
            warnings: &warnings
        ) else {
            return nil
        }
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            diagnostics.append("External signoff review artifact is missing: \(path)")
            return nil
        }

        do {
            let review = try readJSON(ExternalSignoffReview.self, from: url, context: "external signoff review")
            return RoundTripReviewSignoffSummary(
                passed: review.passed,
                approved: review.isApproved,
                readyForPEX: review.isReadyForPEX,
                approvedBy: review.approvedBy,
                approvedAt: review.approvedAt,
                waiverIDs: review.waiverIDs,
                reports: review.reports.map { report in
                    RoundTripReviewSignoffReportSummary(
                        kind: report.kind,
                        toolName: report.toolName,
                        passed: report.passed,
                        logPath: report.logPath,
                        diagnosticCount: report.diagnostics.count,
                        errorCount: report.diagnostics.filter { $0.severity == .error }.count,
                        warningCount: report.diagnostics.filter { $0.severity == .warning }.count
                    )
                }
            )
        } catch {
            diagnostics.append(error.localizedDescription)
            return nil
        }
    }

    private func loadComparisonSummary(
        from artifacts: [HeadlessRoundTripService.Artifact],
        resolver: RoundTripArtifactResolver,
        diagnostics: inout [String],
        warnings: inout [String]
    ) -> RoundTripReviewComparisonSummary? {
        guard let artifact = artifacts.first(where: { $0.kind == "post-layout-comparison" }) else {
            return nil
        }
        guard let url = resolveArtifactURL(
            artifact,
            resolver: resolver,
            diagnostics: &diagnostics,
            warnings: &warnings
        ) else {
            return nil
        }
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            diagnostics.append("Post-layout comparison artifact is missing: \(path)")
            return nil
        }

        do {
            let report = try readJSON(
                PostLayoutComparisonReport.self,
                from: url,
                context: "post-layout comparison"
            )
            return RoundTripReviewComparisonSummary(
                status: report.status,
                gateStatus: report.gateStatus,
                comparedPointCount: report.comparedPointCount,
                maxAbsoluteDelta: report.maxAbsoluteDelta,
                maxRelativeDelta: report.maxRelativeDelta,
                comparisonLimits: report.comparisonLimits,
                variableSummaries: report.comparedVariables.map {
                    RoundTripReviewVariableComparisonSummary(
                        variableName: $0.variableName,
                        maxAbsoluteDelta: $0.maxAbsoluteDelta,
                        maxRelativeDelta: $0.maxRelativeDelta
                    )
                },
                oscillationMetrics: report.oscillationMetrics.map {
                    RoundTripReviewOscillationMetricSummary(
                        variableName: $0.variableName,
                        preLayoutTransitionCount: $0.preLayout?.transitionCount,
                        postLayoutTransitionCount: $0.postLayout?.transitionCount,
                        preLayoutAmplitude: $0.preLayout?.amplitude,
                        postLayoutAmplitude: $0.postLayout?.amplitude,
                        preLayoutFrequency: $0.preLayout?.frequency,
                        postLayoutFrequency: $0.postLayout?.frequency,
                        frequencyRelativeDelta: $0.frequencyRelativeDelta,
                        periodRelativeDelta: $0.periodRelativeDelta,
                        dutyCycleDelta: $0.dutyCycleDelta,
                        diagnostics: $0.diagnostics
                    )
                },
                missingInPostLayout: report.missingInPostLayout,
                addedInPostLayout: report.addedInPostLayout,
                diagnostics: report.diagnostics,
                gateViolations: report.gateViolations
            )
        } catch {
            diagnostics.append(error.localizedDescription)
            return nil
        }
    }

    private func status(
        for manifest: HeadlessRoundTripService.Manifest,
        comparison: RoundTripReviewComparisonSummary?,
        diagnostics: [String]
    ) -> RoundTripReviewSummary.Status {
        if manifest.stages.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if let comparison, comparison.gateStatus == "failed" {
            return .failed
        }
        if !diagnostics.isEmpty {
            return .incomplete
        }
        if manifest.isRoundTripComplete {
            return .passed
        }
        return .incomplete
    }

    private func recommendations(
        manifest: HeadlessRoundTripService.Manifest,
        signoff: RoundTripReviewSignoffSummary?,
        comparison: RoundTripReviewComparisonSummary?,
        diagnostics: [String],
        warnings: [String]
    ) -> [String] {
        var recommendations: [String] = []
        for stage in manifest.stages where stage.status == .failed {
            let message = stage.message.map { ": \($0)" } ?? ""
            recommendations.append("Review failed stage \(stage.name)\(message).")
        }
        if let signoff, signoff.passed && !signoff.approved {
            recommendations.append("Approve the passing external signoff review before using it as a PEX gate.")
        }
        if let comparison, comparison.gateStatus == "failed" {
            recommendations.append("Inspect post-layout comparison gate violations before approving the run.")
        }
        if !diagnostics.isEmpty {
            recommendations.append("Resolve missing or unreadable review artifacts to make the run fully auditable.")
        }
        if !warnings.isEmpty {
            recommendations.append("Regenerate the run to replace legacy absolute artifact paths with run-relative paths.")
        }
        return recommendations
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL, context: String) throws -> T {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw StudioError.projectLoadFailed(
                "Failed to load \(context) from \(url.path(percentEncoded: false)): \(error.localizedDescription)"
            )
        }
    }

    private func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func resolveArtifactURL(
        _ artifact: HeadlessRoundTripService.Artifact,
        resolver: RoundTripArtifactResolver,
        diagnostics: inout [String],
        warnings: inout [String]
    ) -> URL? {
        do {
            let resolution = try resolver.resolve(artifact)
            appendUnique(resolution.warnings, to: &warnings)
            return resolution.url
        } catch {
            appendUnique([
                "Artifact path is invalid: \(artifact.kind) at \(artifact.path): \(error.localizedDescription)",
            ], to: &diagnostics)
            return nil
        }
    }

    private func appendUnique(_ newWarnings: [String], to warnings: inout [String]) {
        for warning in newWarnings where !warnings.contains(warning) {
            warnings.append(warning)
        }
    }

    private func projectRoot(fromManifestURL url: URL) -> URL? {
        let flowRunsDirectory = url.deletingLastPathComponent().deletingLastPathComponent()
        let configDirectory = flowRunsDirectory.deletingLastPathComponent()
        guard configDirectory.lastPathComponent == ".xcircuite" else {
            return nil
        }
        return configDirectory.deletingLastPathComponent()
    }

    private static func validateRunID(_ runID: String) throws {
        let allowedScalars = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        let isValid = !runID.isEmpty
            && runID != "."
            && runID != ".."
            && runID.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
        guard isValid else {
            throw StudioError.invalidDesign(
                "Invalid run ID: use only letters, numbers, '.', '_', or '-', and do not use '.' or '..'."
            )
        }
    }
}
