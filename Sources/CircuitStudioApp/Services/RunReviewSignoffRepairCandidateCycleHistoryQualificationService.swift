import Foundation
import CircuiteFoundation
import DesignFlowKernel

public struct RunReviewSignoffRepairCandidateCycleHistoryQualificationService: Sendable {
    public static let reportArtifactID = "planning-candidate-cycle-history-qualification"
    public static let reportRelativePath = "retained/signoff-repair-cycle-history-qualification.json"

    public enum QualificationError: Error, LocalizedError, Equatable {
        case readProfileFailed(path: String, reason: String)
        case decodeProfileFailed(path: String, reason: String)
        case unsupportedProfileSchemaVersion(path: String, version: Int)

        public var errorDescription: String? {
            switch self {
            case .readProfileFailed(let path, let reason):
                return "Failed to read signoff repair history qualification profile at \(path): \(reason)"
            case .decodeProfileFailed(let path, let reason):
                return "Failed to decode signoff repair history qualification profile at \(path): \(reason)"
            case .unsupportedProfileSchemaVersion(let path, let version):
                return "Unsupported signoff repair history qualification profile schema version \(version) at \(path)."
            }
        }
    }

    public enum Status: String, Sendable, Hashable, Codable {
        case passed
        case failed
    }

    public struct Request: Sendable, Hashable, Codable {
        public let minimumRunCount: Int
        public let minimumCycleCount: Int
        public let minimumAcceptedCount: Int
        public let minimumFeedbackRankChangeCount: Int
        public let minimumFeedbackScoreDeltaCount: Int
        public let minimumAcceptedCountPerSelectedObjectiveDomain: Int
        public let requiredSelectedActionDomainIDs: [String]
        public let requiredSelectedObjectiveDomainIDs: [String]

        public init(
            minimumRunCount: Int = 1,
            minimumCycleCount: Int = 1,
            minimumAcceptedCount: Int = 0,
            minimumFeedbackRankChangeCount: Int = 0,
            minimumFeedbackScoreDeltaCount: Int = 0,
            minimumAcceptedCountPerSelectedObjectiveDomain: Int = 0,
            requiredSelectedActionDomainIDs: [String] = [],
            requiredSelectedObjectiveDomainIDs: [String] = []
        ) {
            self.minimumRunCount = max(0, minimumRunCount)
            self.minimumCycleCount = max(0, minimumCycleCount)
            self.minimumAcceptedCount = max(0, minimumAcceptedCount)
            self.minimumFeedbackRankChangeCount = max(0, minimumFeedbackRankChangeCount)
            self.minimumFeedbackScoreDeltaCount = max(0, minimumFeedbackScoreDeltaCount)
            self.minimumAcceptedCountPerSelectedObjectiveDomain =
                max(0, minimumAcceptedCountPerSelectedObjectiveDomain)
            self.requiredSelectedActionDomainIDs = Self.uniquePreservingOrder(requiredSelectedActionDomainIDs)
            self.requiredSelectedObjectiveDomainIDs = Self.uniquePreservingOrder(requiredSelectedObjectiveDomainIDs)
        }

        private enum CodingKeys: String, CodingKey {
            case minimumRunCount
            case minimumCycleCount
            case minimumAcceptedCount
            case minimumFeedbackRankChangeCount
            case minimumFeedbackScoreDeltaCount
            case minimumAcceptedCountPerSelectedObjectiveDomain
            case requiredSelectedActionDomainIDs
            case requiredSelectedObjectiveDomainIDs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                minimumRunCount: try container.decodeIfPresent(Int.self, forKey: .minimumRunCount) ?? 1,
                minimumCycleCount: try container.decodeIfPresent(Int.self, forKey: .minimumCycleCount) ?? 1,
                minimumAcceptedCount: try container.decodeIfPresent(Int.self, forKey: .minimumAcceptedCount) ?? 0,
                minimumFeedbackRankChangeCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .minimumFeedbackRankChangeCount
                ) ?? 0,
                minimumFeedbackScoreDeltaCount: try container.decodeIfPresent(
                    Int.self,
                    forKey: .minimumFeedbackScoreDeltaCount
                ) ?? 0,
                minimumAcceptedCountPerSelectedObjectiveDomain: try container.decodeIfPresent(
                    Int.self,
                    forKey: .minimumAcceptedCountPerSelectedObjectiveDomain
                ) ?? 0,
                requiredSelectedActionDomainIDs: try container.decodeIfPresent(
                    [String].self,
                    forKey: .requiredSelectedActionDomainIDs
                ) ?? [],
                requiredSelectedObjectiveDomainIDs: try container.decodeIfPresent(
                    [String].self,
                    forKey: .requiredSelectedObjectiveDomainIDs
                ) ?? []
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(minimumRunCount, forKey: .minimumRunCount)
            try container.encode(minimumCycleCount, forKey: .minimumCycleCount)
            try container.encode(minimumAcceptedCount, forKey: .minimumAcceptedCount)
            try container.encode(minimumFeedbackRankChangeCount, forKey: .minimumFeedbackRankChangeCount)
            try container.encode(minimumFeedbackScoreDeltaCount, forKey: .minimumFeedbackScoreDeltaCount)
            try container.encode(
                minimumAcceptedCountPerSelectedObjectiveDomain,
                forKey: .minimumAcceptedCountPerSelectedObjectiveDomain
            )
            try container.encode(requiredSelectedActionDomainIDs, forKey: .requiredSelectedActionDomainIDs)
            try container.encode(requiredSelectedObjectiveDomainIDs, forKey: .requiredSelectedObjectiveDomainIDs)
        }

        private static func uniquePreservingOrder(_ values: [String]) -> [String] {
            var seen: Set<String> = []
            var result: [String] = []
            for value in values where !value.isEmpty && !seen.contains(value) {
                seen.insert(value)
                result.append(value)
            }
            return result
        }
    }

    public struct Profile: Sendable, Hashable, Codable {
        public static let currentSchemaVersion = 1

        public let schemaVersion: Int
        public let profileID: String
        public let title: String
        public let description: String?
        public let request: Request

        public init(
            schemaVersion: Int = Self.currentSchemaVersion,
            profileID: String,
            title: String,
            description: String? = nil,
            request: Request
        ) {
            self.schemaVersion = schemaVersion
            self.profileID = profileID
            self.title = title
            self.description = description
            self.request = request
        }
    }

    public struct Gate: Sendable, Hashable, Codable {
        public let gateID: String
        public let title: String
        public let observed: Int
        public let required: Int
        public let passed: Bool
        public let message: String

        public init(
            gateID: String,
            title: String,
            observed: Int,
            required: Int
        ) {
            self.gateID = gateID
            self.title = title
            self.observed = observed
            self.required = required
            self.passed = observed >= required
            if self.passed {
                self.message = "\(title) satisfied: observed \(observed), required \(required)."
            } else {
                self.message = "\(title) below threshold: observed \(observed), required \(required)."
            }
        }
    }

    public struct Report: Sendable, Hashable, Codable {
        public let status: Status
        public let passed: Bool
        public let profileID: String?
        public let profileTitle: String?
        public let profilePath: String?
        public let request: Request
        public let summary: RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary
        public let gates: [Gate]
        public let failedGateIDs: [String]
        public let missingSelectedActionDomainIDs: [String]
        public let missingSelectedObjectiveDomainIDs: [String]
        public let underqualifiedSelectedObjectiveDomainIDs: [String]
        public let recommendations: [String]
        /// Canonical identity of the persisted report, attached after the
        /// report payload has been written. This metadata is intentionally
        /// excluded from the report payload to avoid a self-referential digest.
        public let artifactReference: ArtifactReference?

        public init(
            request: Request,
            summary: RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary,
            gates: [Gate],
            profile: Profile? = nil,
            profilePath: String? = nil,
            artifactReference: ArtifactReference? = nil
        ) {
            let failedGateIDs = gates
                .filter { !$0.passed }
                .map(\.gateID)
            let missingSelectedActionDomainIDs = Self.missingRequiredDomains(
                required: request.requiredSelectedActionDomainIDs,
                observed: summary.selectedActionDomainIDs
            )
            let missingSelectedObjectiveDomainIDs = Self.missingRequiredDomains(
                required: request.requiredSelectedObjectiveDomainIDs,
                observed: summary.selectedObjectiveDomainIDs
            )
            let underqualifiedSelectedObjectiveDomainIDs = Self.underqualifiedSelectedObjectiveDomains(
                request: request,
                summary: summary
            )
            self.status = failedGateIDs.isEmpty ? .passed : .failed
            self.passed = failedGateIDs.isEmpty
            self.profileID = profile?.profileID
            self.profileTitle = profile?.title
            self.profilePath = profilePath
            self.request = request
            self.summary = summary
            self.gates = gates
            self.failedGateIDs = failedGateIDs
            self.missingSelectedActionDomainIDs = missingSelectedActionDomainIDs
            self.missingSelectedObjectiveDomainIDs = missingSelectedObjectiveDomainIDs
            self.underqualifiedSelectedObjectiveDomainIDs = underqualifiedSelectedObjectiveDomainIDs
            self.recommendations = Self.recommendations(
                failedGateIDs: failedGateIDs,
                missingSelectedActionDomainIDs: missingSelectedActionDomainIDs,
                missingSelectedObjectiveDomainIDs: missingSelectedObjectiveDomainIDs,
                underqualifiedSelectedObjectiveDomainIDs: underqualifiedSelectedObjectiveDomainIDs,
                summaryRecommendations: summary.recommendations
            )
            self.artifactReference = artifactReference
        }

        /// Returns the report with the identity of its persisted payload.
        /// The identity is response metadata and is not encoded into the
        /// payload whose digest it describes.
        public func attachingArtifactReference(_ reference: ArtifactReference) -> Report {
            Report(
                status: status,
                passed: passed,
                profileID: profileID,
                profileTitle: profileTitle,
                profilePath: profilePath,
                request: request,
                summary: summary,
                gates: gates,
                failedGateIDs: failedGateIDs,
                missingSelectedActionDomainIDs: missingSelectedActionDomainIDs,
                missingSelectedObjectiveDomainIDs: missingSelectedObjectiveDomainIDs,
                underqualifiedSelectedObjectiveDomainIDs: underqualifiedSelectedObjectiveDomainIDs,
                recommendations: recommendations,
                artifactReference: reference
            )
        }

        private init(
            status: Status,
            passed: Bool,
            profileID: String?,
            profileTitle: String?,
            profilePath: String?,
            request: Request,
            summary: RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary,
            gates: [Gate],
            failedGateIDs: [String],
            missingSelectedActionDomainIDs: [String],
            missingSelectedObjectiveDomainIDs: [String],
            underqualifiedSelectedObjectiveDomainIDs: [String],
            recommendations: [String],
            artifactReference: ArtifactReference?
        ) {
            self.status = status
            self.passed = passed
            self.profileID = profileID
            self.profileTitle = profileTitle
            self.profilePath = profilePath
            self.request = request
            self.summary = summary
            self.gates = gates
            self.failedGateIDs = failedGateIDs
            self.missingSelectedActionDomainIDs = missingSelectedActionDomainIDs
            self.missingSelectedObjectiveDomainIDs = missingSelectedObjectiveDomainIDs
            self.underqualifiedSelectedObjectiveDomainIDs = underqualifiedSelectedObjectiveDomainIDs
            self.recommendations = recommendations
            self.artifactReference = artifactReference
        }

        public static func == (lhs: Report, rhs: Report) -> Bool {
            lhs.status == rhs.status
                && lhs.passed == rhs.passed
                && lhs.profileID == rhs.profileID
                && lhs.profileTitle == rhs.profileTitle
                && lhs.profilePath == rhs.profilePath
                && lhs.request == rhs.request
                && lhs.summary == rhs.summary
                && lhs.gates == rhs.gates
                && lhs.failedGateIDs == rhs.failedGateIDs
                && lhs.missingSelectedActionDomainIDs == rhs.missingSelectedActionDomainIDs
                && lhs.missingSelectedObjectiveDomainIDs == rhs.missingSelectedObjectiveDomainIDs
                && lhs.underqualifiedSelectedObjectiveDomainIDs == rhs.underqualifiedSelectedObjectiveDomainIDs
                && lhs.recommendations == rhs.recommendations
                && lhs.artifactReference == rhs.artifactReference
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(status)
            hasher.combine(passed)
            hasher.combine(profileID)
            hasher.combine(profileTitle)
            hasher.combine(profilePath)
            hasher.combine(request)
            hasher.combine(summary)
            hasher.combine(gates)
            hasher.combine(failedGateIDs)
            hasher.combine(missingSelectedActionDomainIDs)
            hasher.combine(missingSelectedObjectiveDomainIDs)
            hasher.combine(underqualifiedSelectedObjectiveDomainIDs)
            hasher.combine(recommendations)
            hasher.combine(artifactReference)
        }

        private enum CodingKeys: String, CodingKey {
            case status
            case passed
            case profileID
            case profileTitle
            case profilePath
            case request
            case summary
            case gates
            case failedGateIDs
            case missingSelectedActionDomainIDs
            case missingSelectedObjectiveDomainIDs
            case underqualifiedSelectedObjectiveDomainIDs
            case recommendations
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let request = try container.decode(Request.self, forKey: .request)
            let summary = try container.decode(
                RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary.self,
                forKey: .summary
            )
            let gates = try container.decode([Gate].self, forKey: .gates)
            let failedGateIDs = try container.decodeIfPresent([String].self, forKey: .failedGateIDs)
                ?? gates.filter { !$0.passed }.map(\.gateID)
            let missingSelectedActionDomainIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .missingSelectedActionDomainIDs
            ) ?? Self.missingRequiredDomains(
                required: request.requiredSelectedActionDomainIDs,
                observed: summary.selectedActionDomainIDs
            )
            let missingSelectedObjectiveDomainIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .missingSelectedObjectiveDomainIDs
            ) ?? Self.missingRequiredDomains(
                required: request.requiredSelectedObjectiveDomainIDs,
                observed: summary.selectedObjectiveDomainIDs
            )
            let underqualifiedSelectedObjectiveDomainIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .underqualifiedSelectedObjectiveDomainIDs
            ) ?? Self.underqualifiedSelectedObjectiveDomains(
                request: request,
                summary: summary
            )
            self.status = try container.decodeIfPresent(Status.self, forKey: .status)
                ?? (failedGateIDs.isEmpty ? .passed : .failed)
            self.passed = try container.decodeIfPresent(Bool.self, forKey: .passed)
                ?? failedGateIDs.isEmpty
            self.profileID = try container.decodeIfPresent(String.self, forKey: .profileID)
            self.profileTitle = try container.decodeIfPresent(String.self, forKey: .profileTitle)
            self.profilePath = try container.decodeIfPresent(String.self, forKey: .profilePath)
            self.request = request
            self.summary = summary
            self.gates = gates
            self.failedGateIDs = failedGateIDs
            self.missingSelectedActionDomainIDs = missingSelectedActionDomainIDs
            self.missingSelectedObjectiveDomainIDs = missingSelectedObjectiveDomainIDs
            self.underqualifiedSelectedObjectiveDomainIDs = underqualifiedSelectedObjectiveDomainIDs
            self.recommendations = try container.decodeIfPresent([String].self, forKey: .recommendations)
                ?? Self.recommendations(
                    failedGateIDs: failedGateIDs,
                    missingSelectedActionDomainIDs: missingSelectedActionDomainIDs,
                    missingSelectedObjectiveDomainIDs: missingSelectedObjectiveDomainIDs,
                    underqualifiedSelectedObjectiveDomainIDs: underqualifiedSelectedObjectiveDomainIDs,
                    summaryRecommendations: summary.recommendations
                )
            self.artifactReference = nil
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encode(passed, forKey: .passed)
            try container.encodeIfPresent(profileID, forKey: .profileID)
            try container.encodeIfPresent(profileTitle, forKey: .profileTitle)
            try container.encodeIfPresent(profilePath, forKey: .profilePath)
            try container.encode(request, forKey: .request)
            try container.encode(summary, forKey: .summary)
            try container.encode(gates, forKey: .gates)
            try container.encode(failedGateIDs, forKey: .failedGateIDs)
            try container.encode(missingSelectedActionDomainIDs, forKey: .missingSelectedActionDomainIDs)
            try container.encode(missingSelectedObjectiveDomainIDs, forKey: .missingSelectedObjectiveDomainIDs)
            try container.encode(
                underqualifiedSelectedObjectiveDomainIDs,
                forKey: .underqualifiedSelectedObjectiveDomainIDs
            )
            try container.encode(recommendations, forKey: .recommendations)
        }

        private static func missingRequiredDomains(
            required: [String],
            observed: [String]
        ) -> [String] {
            let observedSet = Set(observed)
            return required.filter { !observedSet.contains($0) }
        }

        private static func recommendations(
            failedGateIDs: [String],
            missingSelectedActionDomainIDs: [String],
            missingSelectedObjectiveDomainIDs: [String],
            underqualifiedSelectedObjectiveDomainIDs: [String],
            summaryRecommendations: [String]
        ) -> [String] {
            guard !failedGateIDs.isEmpty else {
                return summaryRecommendations
            }
            var values = [
                "Increase retained signoff repair candidate-cycle corpus before promoting this capability gate.",
                "Failed gates: \(failedGateIDs.joined(separator: ","))",
            ]
            if !missingSelectedActionDomainIDs.isEmpty {
                values.append(
                    "Retain candidate-cycle evidence for selected action domains: \(missingSelectedActionDomainIDs.joined(separator: ","))."
                )
            }
            if !missingSelectedObjectiveDomainIDs.isEmpty {
                values.append(
                    "Retain candidate-cycle evidence for selected objective domains: \(missingSelectedObjectiveDomainIDs.joined(separator: ","))."
                )
            }
            if !underqualifiedSelectedObjectiveDomainIDs.isEmpty {
                values.append(
                    "Retain accepted candidate-cycle evidence for selected objective domains: \(underqualifiedSelectedObjectiveDomainIDs.joined(separator: ","))."
                )
            }
            return values + summaryRecommendations
        }

        private static func underqualifiedSelectedObjectiveDomains(
            request: Request,
            summary: RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary
        ) -> [String] {
            guard request.minimumAcceptedCountPerSelectedObjectiveDomain > 0 else {
                return []
            }
            let requiredDomainIDs: [String]
            if request.requiredSelectedObjectiveDomainIDs.isEmpty {
                requiredDomainIDs = summary.selectedObjectiveDomainIDs
            } else {
                requiredDomainIDs = request.requiredSelectedObjectiveDomainIDs
            }
            let acceptedCountByDomain = Self.acceptedCountByDomain(summary.objectiveDomainSummaries)
            return requiredDomainIDs.filter { domainID in
                (acceptedCountByDomain[domainID] ?? 0)
                    < request.minimumAcceptedCountPerSelectedObjectiveDomain
            }
        }

        private static func acceptedCountByDomain(
            _ summaries: [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary]
        ) -> [String: Int] {
            var counts: [String: Int] = [:]
            for summary in summaries where counts[summary.domainID] == nil {
                counts[summary.domainID] = summary.acceptedCount
            }
            return counts
        }
    }

    private let indexService: RunReviewSignoffRepairCandidateCycleHistoryIndexService
    private let packageStore: XcircuitePackageStore

    public init(
        indexService: RunReviewSignoffRepairCandidateCycleHistoryIndexService =
            RunReviewSignoffRepairCandidateCycleHistoryIndexService(),
        packageStore: XcircuitePackageStore = XcircuitePackageStore()
    ) {
        self.indexService = indexService
        self.packageStore = packageStore
    }

    public func qualify(
        forProjectAt projectRoot: URL,
        request: Request = Request(),
        profile: Profile? = nil,
        profilePath: String? = nil
    ) throws -> Report {
        let summary = try indexService.summarize(forProjectAt: projectRoot)
        return qualify(summary: summary, request: request, profile: profile, profilePath: profilePath)
    }

    public func qualify(
        summary: RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary,
        request: Request = Request(),
        profile: Profile? = nil,
        profilePath: String? = nil
    ) -> Report {
        let missingDomainIDs = missingRequiredDomains(
            required: request.requiredSelectedActionDomainIDs,
            observed: summary.selectedActionDomainIDs
        )
        let observedRequiredDomainCount = request.requiredSelectedActionDomainIDs.count - missingDomainIDs.count
        let missingObjectiveDomainIDs = missingRequiredDomains(
            required: request.requiredSelectedObjectiveDomainIDs,
            observed: summary.selectedObjectiveDomainIDs
        )
        let observedRequiredObjectiveDomainCount =
            request.requiredSelectedObjectiveDomainIDs.count - missingObjectiveDomainIDs.count
        let objectiveDomainsForAcceptedGate: [String]
        if request.requiredSelectedObjectiveDomainIDs.isEmpty {
            objectiveDomainsForAcceptedGate = summary.selectedObjectiveDomainIDs
        } else {
            objectiveDomainsForAcceptedGate = request.requiredSelectedObjectiveDomainIDs
        }
        let minimumAcceptedCountPerObjectiveDomain = minimumAcceptedCountPerObjectiveDomain(
            domainIDs: objectiveDomainsForAcceptedGate,
            summaries: summary.objectiveDomainSummaries
        )
        return Report(
            request: request,
            summary: summary,
            gates: [
                Gate(
                    gateID: "minimum-run-count",
                    title: "Retained run count",
                    observed: summary.runCount,
                    required: request.minimumRunCount
                ),
                Gate(
                    gateID: "minimum-cycle-count",
                    title: "Retained candidate-cycle count",
                    observed: summary.cycleCount,
                    required: request.minimumCycleCount
                ),
                Gate(
                    gateID: "minimum-accepted-count",
                    title: "Accepted candidate-cycle count",
                    observed: summary.acceptedCount,
                    required: request.minimumAcceptedCount
                ),
                Gate(
                    gateID: "minimum-feedback-rank-change-count",
                    title: "Rejected-feedback rank-change count",
                    observed: summary.feedbackRankChangeCount,
                    required: request.minimumFeedbackRankChangeCount
                ),
                Gate(
                    gateID: "minimum-feedback-score-delta-count",
                    title: "Rejected-feedback score-delta count",
                    observed: summary.feedbackScoreDeltaCount,
                    required: request.minimumFeedbackScoreDeltaCount
                ),
                Gate(
                    gateID: "required-selected-action-domains",
                    title: "Required selected action domains",
                    observed: observedRequiredDomainCount,
                    required: request.requiredSelectedActionDomainIDs.count
                ),
                Gate(
                    gateID: "required-selected-objective-domains",
                    title: "Required selected objective domains",
                    observed: observedRequiredObjectiveDomainCount,
                    required: request.requiredSelectedObjectiveDomainIDs.count
                ),
                Gate(
                    gateID: "minimum-accepted-count-per-selected-objective-domain",
                    title: "Accepted candidate-cycle count per selected objective domain",
                    observed: minimumAcceptedCountPerObjectiveDomain,
                    required: request.minimumAcceptedCountPerSelectedObjectiveDomain
                ),
            ],
            profile: profile,
            profilePath: profilePath
        )
    }

    private func missingRequiredDomains(
        required: [String],
        observed: [String]
    ) -> [String] {
        let observedSet = Set(observed)
        return required.filter { !observedSet.contains($0) }
    }

    private func minimumAcceptedCountPerObjectiveDomain(
        domainIDs: [String],
        summaries: [RunReviewSignoffRepairCandidateCycleObjectiveDomainSummary]
    ) -> Int {
        guard !domainIDs.isEmpty else {
            return 0
        }
        var acceptedCountByDomain: [String: Int] = [:]
        for summary in summaries where acceptedCountByDomain[summary.domainID] == nil {
            acceptedCountByDomain[summary.domainID] = summary.acceptedCount
        }
        return domainIDs
            .map { acceptedCountByDomain[$0] ?? 0 }
            .min() ?? 0
    }

    public func loadProfile(from url: URL) throws -> Profile {
        let path = url.path(percentEncoded: false)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw QualificationError.readProfileFailed(path: path, reason: error.localizedDescription)
        }

        let profile: Profile
        do {
            profile = try JSONDecoder().decode(Profile.self, from: data)
        } catch {
            throw QualificationError.decodeProfileFailed(path: path, reason: error.localizedDescription)
        }

        guard profile.schemaVersion == Profile.currentSchemaVersion else {
            throw QualificationError.unsupportedProfileSchemaVersion(
                path: path,
                version: profile.schemaVersion
            )
        }
        return profile
    }

    public func persist(
        _ report: Report,
        forProjectAt projectRoot: URL
    ) throws -> ArtifactReference {
        try packageStore.createPackage(at: projectRoot)
        let packageURL = packageStore.packageURL(forProjectAt: projectRoot)
        let retainedDirectory = packageURL.appending(path: "retained")
        try packageStore.ensureDirectory(at: retainedDirectory)

        let reportURL = retainedDirectory.appending(path: "signoff-repair-cycle-history-qualification.json")
        try packageStore.writeJSON(report, to: reportURL, forProjectAt: projectRoot)

        let projectRelativePath = "\(XcircuitePackage.directoryName)/\(Self.reportRelativePath)"
        let legacyReference = try packageStore.fileReference(
            forProjectRelativePath: projectRelativePath,
            artifactID: Self.reportArtifactID,
            kind: .other,
            format: .json,
            inProjectAt: projectRoot
        )
        try packageStore.upsertFileReference(legacyReference, forProjectAt: projectRoot)
        guard let reference = FoundationArtifactTypeProjection.reference(legacyReference) else {
            throw RunReviewServiceError.artifactReferenceProjectionFailed(
                path: legacyReference.path,
                message: "Persisted qualification artifact has invalid integrity, kind, or format metadata."
            )
        }
        return reference
    }
}
