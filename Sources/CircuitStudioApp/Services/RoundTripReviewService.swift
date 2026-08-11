import CircuitSignoff
import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
import CircuitStudioCore
import DesignFlowKernel

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

    public func loadReview(forProjectAt projectRoot: URL, runID: String) async throws -> RoundTripReviewSummary {
        try Self.validateRunID(runID)
        let manifestURL = try RoundTripRunDirectory.manifestURL(
            projectRoot: projectRoot,
            runID: runID
        )
        return try await loadReview(manifestURL: manifestURL)
    }

    public func loadReview(manifestURL: URL) async throws -> RoundTripReviewSummary {
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

        let signoff = await loadSignoffSummary(
            from: manifest.artifacts,
            resolver: resolver,
            diagnostics: &diagnostics,
            warnings: &warnings
        )
        let comparison = await loadComparisonSummary(
            from: manifest.artifacts,
            resolver: resolver,
            diagnostics: &diagnostics,
            warnings: &warnings
        )
        let flowReviewBundle = await loadFlowReviewBundle(
            manifest: manifest,
            manifestURL: manifestURL,
            diagnostics: &diagnostics
        )
        let approvals = flowReviewBundle?.approvals ?? []
        let suggestedActionSelections = await loadSuggestedActionSelections(
            manifestURL: manifestURL,
            diagnostics: &diagnostics
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
            status: status(
                for: manifest,
                signoff: signoff,
                comparison: comparison,
                diagnostics: diagnostics
            ),
            isRoundTripComplete: manifest.isRoundTripComplete,
            isReadyForPEX: readyForPEX(
                for: manifest,
                signoff: signoff,
                comparison: comparison,
                diagnostics: diagnostics
            ),
            stages: stageSummaries,
            artifacts: artifactSummaries,
            externalSignoff: signoff,
            postLayoutComparison: comparison,
            approvals: approvals,
            suggestedActionSelections: suggestedActionSelections,
            toolchain: flowReviewBundle?.summary.toolchain,
            toolchainArtifacts: flowReviewBundle?.artifacts.filter {
                $0.purpose == .toolchain || $0.purpose == .toolchainProfile
            } ?? [],
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

    private func loadSuggestedActionSelections(
        manifestURL: URL,
        diagnostics: inout [String]
    ) async -> [FlowRunSuggestedActionSelection] {
        let ledgerURL = manifestURL.deletingLastPathComponent().appending(path: "ledger.json")
        guard FileManager.default.fileExists(atPath: ledgerURL.path(percentEncoded: false)) else {
            return []
        }
        do {
            return try await RoundTripActionLogService().loadSuggestedActionSelections(
                manifestURL: manifestURL
            )
        } catch {
            diagnostics.append("action log: \(error.localizedDescription)")
            return []
        }
    }

    private func loadFlowReviewBundle(
        manifest: HeadlessRoundTripService.Manifest,
        manifestURL: URL,
        diagnostics: inout [String]
    ) async -> FlowRunReviewBundle? {
        guard let projectRoot = projectRoot(fromManifestURL: manifestURL) else {
            return nil
        }
        let flowManifestURL = projectRoot
            .appending(path: ".xcircuite")
            .appending(path: "runs")
            .appending(path: manifest.runID)
            .appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: flowManifestURL.path(percentEncoded: false)) else {
            return nil
        }
        do {
            return try await RunReviewService().loadReviewBundle(
                runID: manifest.runID,
                projectRoot: projectRoot
            )
        } catch {
            diagnostics.append("Failed to load flow review bundle: \(error.localizedDescription)")
            return nil
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
                isCapturedCopy: artifact.sourcePath != nil,
                manifestSHA256: artifact.sha256,
                manifestByteCount: artifact.byteCount,
                integrityStatus: .unresolved
            )
        }
        let path = url.path(percentEncoded: false)
        let exists = FileManager.default.fileExists(atPath: path)
        if !exists {
            diagnostics.append("Artifact is missing: \(artifact.kind) at \(path)")
            return RoundTripReviewArtifactSummary(
                kind: artifact.kind,
                path: path,
                sourcePath: artifact.sourcePath,
                exists: false,
                isCapturedCopy: artifact.sourcePath != nil,
                manifestSHA256: artifact.sha256,
                manifestByteCount: artifact.byteCount,
                integrityStatus: .missingArtifact
            )
        }

        let actualReference: ArtifactReference
        do {
            actualReference = try ArtifactReference.circuitStudioReference(
                kind: artifact.kind,
                relativePath: artifact.path,
                fileURL: url
            )
        } catch {
            diagnostics.append("Artifact is unreadable: \(artifact.kind) at \(path): \(error.localizedDescription)")
            return RoundTripReviewArtifactSummary(
                kind: artifact.kind,
                path: path,
                sourcePath: artifact.sourcePath,
                exists: true,
                isCapturedCopy: artifact.sourcePath != nil,
                manifestSHA256: artifact.sha256,
                manifestByteCount: artifact.byteCount,
                integrityStatus: .unreadableArtifact
            )
        }

        let integrityStatus = integrityStatus(
            artifact: artifact,
            actualReference: actualReference,
            diagnostics: &diagnostics
        )

        return RoundTripReviewArtifactSummary(
            kind: artifact.kind,
            path: path,
            sourcePath: artifact.sourcePath,
            exists: true,
            isCapturedCopy: artifact.sourcePath != nil,
            manifestSHA256: artifact.sha256,
            manifestByteCount: artifact.byteCount,
            actualSHA256: actualReference.digest.hexadecimalValue,
            actualByteCount: actualReference.byteCount,
            integrityStatus: integrityStatus
        )
    }

    private func integrityStatus(
        artifact: HeadlessRoundTripService.Artifact,
        actualReference: ArtifactReference,
        diagnostics: inout [String]
    ) -> RoundTripArtifactIntegrityStatus {
        var status = RoundTripArtifactIntegrityStatus.verified
        if artifact.reference.byteCount != actualReference.byteCount {
            appendUnique([
                "Artifact byte count mismatch: \(artifact.kind) at \(artifact.path) expected \(artifact.reference.byteCount), got \(actualReference.byteCount)",
            ], to: &diagnostics)
            status = .byteCountMismatch
        }
        if artifact.reference.digest != actualReference.digest {
            appendUnique([
                "Artifact SHA-256 mismatch: \(artifact.kind) at \(artifact.path) expected \(artifact.reference.digest.hexadecimalValue), got \(actualReference.digest.hexadecimalValue)",
            ], to: &diagnostics)
            status = .sha256Mismatch
        }
        return status
    }

    private func loadSignoffSummary(
        from artifacts: [HeadlessRoundTripService.Artifact],
        resolver: RoundTripArtifactResolver,
        diagnostics: inout [String],
        warnings: inout [String]
    ) async -> RoundTripReviewSignoffSummary? {
        guard let artifact = artifacts.first(where: { $0.kind == "external-signoff-review" }) else {
            return nil
        }
        guard let verified = await resolveVerifiedArtifact(
            artifact,
            resolver: resolver,
            diagnostics: &diagnostics,
            warnings: &warnings
        ) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let review = try decoder.decode(
                ExternalSignoffReview.self,
                from: verified.data
            )
            return RoundTripReviewSignoffSummary(
                passed: review.passed,
                approved: review.isApproved,
                readyForPEX: review.isReadyForPEX,
                approvedBy: review.approvedBy,
                approvedAt: review.approvedAt,
                approvalKind: review.approvalKind,
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
    ) async -> RoundTripReviewComparisonSummary? {
        guard let artifact = artifacts.first(where: { $0.kind == "post-layout-comparison" }) else {
            return nil
        }
        guard let verified = await resolveVerifiedArtifact(
            artifact,
            resolver: resolver,
            diagnostics: &diagnostics,
            warnings: &warnings
        ) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let report = try decoder.decode(
                PostLayoutComparisonReport.self,
                from: verified.data
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
                        signalDomain: $0.signalDomain,
                        unit: $0.unit,
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
        signoff: RoundTripReviewSignoffSummary?,
        comparison: RoundTripReviewComparisonSummary?,
        diagnostics: [String]
    ) -> RoundTripReviewSummary.Status {
        if manifest.stages.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if let signoff, !signoff.passed {
            return .failed
        }
        if let comparison, comparison.gateStatus == "failed" {
            return .failed
        }
        if !diagnostics.isEmpty {
            return .incomplete
        }
        if let signoff, !signoff.readyForPEX {
            return .incomplete
        }
        if manifest.isRoundTripComplete {
            return .passed
        }
        return .incomplete
    }

    private func readyForPEX(
        for manifest: HeadlessRoundTripService.Manifest,
        signoff: RoundTripReviewSignoffSummary?,
        comparison: RoundTripReviewComparisonSummary?,
        diagnostics: [String]
    ) -> Bool {
        guard diagnostics.isEmpty, manifest.isReadyForPEX else {
            return false
        }
        if let signoff, !signoff.readyForPEX {
            return false
        }
        if let comparison, comparison.gateStatus == "failed" {
            return false
        }
        return true
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
        if let signoff, !signoff.passed {
            recommendations.append("Review failed external signoff reports before approving or using the run for PEX.")
        } else if let signoff, signoff.passed && !signoff.approved {
            recommendations.append("Approve the passing external signoff review before using it as a PEX gate.")
        }
        if let comparison, comparison.gateStatus == "failed" {
            recommendations.append("Inspect post-layout comparison gate violations before approving the run.")
        }
        if !diagnostics.isEmpty {
            recommendations.append("Resolve missing or unreadable review artifacts to make the run fully auditable.")
        }
        if !warnings.isEmpty {
            recommendations.append("Regenerate the run to replace unverifiable artifact references with run-relative, digest-backed artifacts.")
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
        try SHA256ContentDigester().digest(fileAt: url, using: .sha256).hexadecimalValue
    }

    private func resolveVerifiedArtifact(
        _ artifact: HeadlessRoundTripService.Artifact,
        resolver: RoundTripArtifactResolver,
        diagnostics: inout [String],
        warnings: inout [String]
    ) async -> VerifiedArtifact? {
        do {
            let resolution = try resolver.resolve(artifact)
            appendUnique(resolution.warnings, to: &warnings)
            return try await ArtifactIntegrityChecker().verifiedArtifact(
                for: artifact,
                in: resolver.runDirectory
            )
        } catch {
            appendUnique([error.localizedDescription], to: &diagnostics)
            return nil
        }
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
