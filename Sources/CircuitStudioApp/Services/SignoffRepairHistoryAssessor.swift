import Foundation
import CircuiteFoundation
import DesignFlowKernel
import Xcircuite

/// Assesses retained candidate-cycle history against promotion thresholds.
///
/// This service does not qualify tools and does not produce ToolQualification
/// records. Its report is historical evidence for a separate promotion policy.
public struct SignoffRepairHistoryAssessor: Sendable {
    public static let reportArtifactID = "signoff-repair-history-assessment"
    public static let reportRelativePath = "retained/history-assessment.json"

    public enum AssessmentError: Error, LocalizedError, Equatable {
        case readProfileFailed(path: String, reason: String)
        case decodeProfileFailed(path: String, reason: String)
        case invalidProfile(reason: String)
        case invalidRequest(reason: String)

        public var errorDescription: String? {
            switch self {
            case .readProfileFailed(let path, let reason):
                return "Failed to read signoff repair history assessment profile at \(path): \(reason)"
            case .decodeProfileFailed(let path, let reason):
                return "Failed to decode signoff repair history assessment profile at \(path): \(reason)"
            case .invalidProfile(let reason):
                return "Invalid signoff repair history assessment profile: \(reason)"
            case .invalidRequest(let reason):
                return "Invalid signoff repair history assessment request: \(reason)"
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
            self.minimumRunCount = minimumRunCount
            self.minimumCycleCount = minimumCycleCount
            self.minimumAcceptedCount = minimumAcceptedCount
            self.minimumFeedbackRankChangeCount = minimumFeedbackRankChangeCount
            self.minimumFeedbackScoreDeltaCount = minimumFeedbackScoreDeltaCount
            self.minimumAcceptedCountPerSelectedObjectiveDomain = minimumAcceptedCountPerSelectedObjectiveDomain
            self.requiredSelectedActionDomainIDs = requiredSelectedActionDomainIDs
            self.requiredSelectedObjectiveDomainIDs = requiredSelectedObjectiveDomainIDs
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
            let minimumRunCount = try container.decode(Int.self, forKey: .minimumRunCount)
            let minimumCycleCount = try container.decode(Int.self, forKey: .minimumCycleCount)
            let minimumAcceptedCount = try container.decode(Int.self, forKey: .minimumAcceptedCount)
            let minimumFeedbackRankChangeCount = try container.decode(
                Int.self,
                forKey: .minimumFeedbackRankChangeCount
            )
            let minimumFeedbackScoreDeltaCount = try container.decode(
                Int.self,
                forKey: .minimumFeedbackScoreDeltaCount
            )
            let minimumAcceptedCountPerSelectedObjectiveDomain = try container.decode(
                Int.self,
                forKey: .minimumAcceptedCountPerSelectedObjectiveDomain
            )
            let requiredSelectedActionDomainIDs = try container.decode(
                [String].self,
                forKey: .requiredSelectedActionDomainIDs
            )
            let requiredSelectedObjectiveDomainIDs = try container.decode(
                [String].self,
                forKey: .requiredSelectedObjectiveDomainIDs
            )
            let counts = [
                minimumRunCount,
                minimumCycleCount,
                minimumAcceptedCount,
                minimumFeedbackRankChangeCount,
                minimumFeedbackScoreDeltaCount,
                minimumAcceptedCountPerSelectedObjectiveDomain,
            ]
            guard counts.allSatisfy({ $0 >= 0 }) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .minimumRunCount,
                    in: container,
                    debugDescription: "History assessment thresholds must be nonnegative."
                )
            }
            guard Self.hasValidUniqueDomainIDs(requiredSelectedActionDomainIDs),
                  Self.hasValidUniqueDomainIDs(requiredSelectedObjectiveDomainIDs) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .requiredSelectedActionDomainIDs,
                    in: container,
                    debugDescription: "Required history assessment domain identifiers must be nonempty and unique."
                )
            }
            self.init(
                minimumRunCount: minimumRunCount,
                minimumCycleCount: minimumCycleCount,
                minimumAcceptedCount: minimumAcceptedCount,
                minimumFeedbackRankChangeCount: minimumFeedbackRankChangeCount,
                minimumFeedbackScoreDeltaCount: minimumFeedbackScoreDeltaCount,
                minimumAcceptedCountPerSelectedObjectiveDomain: minimumAcceptedCountPerSelectedObjectiveDomain,
                requiredSelectedActionDomainIDs: requiredSelectedActionDomainIDs,
                requiredSelectedObjectiveDomainIDs: requiredSelectedObjectiveDomainIDs
            )
        }

        public func encode(to encoder: Encoder) throws {
            if let validationFailure {
                throw EncodingError.invalidValue(
                    self,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: validationFailure
                    )
                )
            }
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

        public func validate() throws {
            if let validationFailure {
                throw AssessmentError.invalidRequest(reason: validationFailure)
            }
        }

        private var validationFailure: String? {
            let counts = [
                minimumRunCount,
                minimumCycleCount,
                minimumAcceptedCount,
                minimumFeedbackRankChangeCount,
                minimumFeedbackScoreDeltaCount,
                minimumAcceptedCountPerSelectedObjectiveDomain,
            ]
            guard counts.allSatisfy({ $0 >= 0 }) else {
                return "Thresholds must be nonnegative."
            }
            guard Self.hasValidUniqueDomainIDs(requiredSelectedActionDomainIDs),
                  Self.hasValidUniqueDomainIDs(requiredSelectedObjectiveDomainIDs) else {
                return "Required domain identifiers must be trimmed, nonempty, and unique."
            }
            return nil
        }

        private static func hasValidUniqueDomainIDs(_ values: [String]) -> Bool {
            values.allSatisfy {
                !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
            } && Set(values).count == values.count
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
            profileID: String,
            title: String,
            description: String? = nil,
            request: Request
        ) throws {
            guard !profileID.isEmpty,
                  profileID == profileID.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  title == title.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw AssessmentError.invalidProfile(
                    reason: "Profile ID and title must be trimmed and nonempty."
                )
            }
            try request.validate()
            self.schemaVersion = Self.currentSchemaVersion
            self.profileID = profileID
            self.title = title
            self.description = description
            self.request = request
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case profileID
            case title
            case description
            case request
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == Self.currentSchemaVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription: "Unsupported history assessment profile schema version \(schemaVersion)."
                )
            }
            profileID = try container.decode(String.self, forKey: .profileID)
            title = try container.decode(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            request = try container.decode(Request.self, forKey: .request)
            guard !profileID.isEmpty,
                  profileID == profileID.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  title == title.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .profileID,
                    in: container,
                    debugDescription: "History assessment profile ID and title must not be empty."
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            guard !profileID.isEmpty,
                  profileID == profileID.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  title == title.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw EncodingError.invalidValue(
                    self,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "History assessment profile ID and title must not be empty."
                    )
                )
            }
            try request.validate()
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(profileID, forKey: .profileID)
            try container.encode(title, forKey: .title)
            try container.encode(description, forKey: .description)
            try container.encode(request, forKey: .request)
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
        public static let currentSchemaVersion = 1

        public let schemaVersion: Int
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
        public let belowThresholdSelectedObjectiveDomainIDs: [String]
        public let recommendations: [String]
        /// Canonical identity of the persisted report, attached after the
        /// report payload has been written. This metadata is intentionally
        /// excluded from the report payload to avoid a self-referential digest.
        public let artifactReference: ArtifactReference?

        fileprivate init(
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
            let belowThresholdSelectedObjectiveDomainIDs = Self.belowThresholdSelectedObjectiveDomains(
                request: request,
                summary: summary
            )
            self.schemaVersion = Self.currentSchemaVersion
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
            self.belowThresholdSelectedObjectiveDomainIDs = belowThresholdSelectedObjectiveDomainIDs
            self.recommendations = Self.recommendations(
                failedGateIDs: failedGateIDs,
                missingSelectedActionDomainIDs: missingSelectedActionDomainIDs,
                missingSelectedObjectiveDomainIDs: missingSelectedObjectiveDomainIDs,
                belowThresholdSelectedObjectiveDomainIDs: belowThresholdSelectedObjectiveDomainIDs,
                summaryRecommendations: summary.recommendations
            )
            self.artifactReference = artifactReference
        }

        /// Returns the report with the identity of its persisted payload.
        /// The identity is response metadata and is not encoded into the
        /// payload whose digest it describes.
        public func attachingArtifactReference(_ reference: ArtifactReference) -> Report {
            Report(
                schemaVersion: schemaVersion,
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
                belowThresholdSelectedObjectiveDomainIDs: belowThresholdSelectedObjectiveDomainIDs,
                recommendations: recommendations,
                artifactReference: reference
            )
        }

        private init(
            schemaVersion: Int,
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
            belowThresholdSelectedObjectiveDomainIDs: [String],
            recommendations: [String],
            artifactReference: ArtifactReference?
        ) {
            self.schemaVersion = schemaVersion
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
            self.belowThresholdSelectedObjectiveDomainIDs = belowThresholdSelectedObjectiveDomainIDs
            self.recommendations = recommendations
            self.artifactReference = artifactReference
        }

        public static func == (lhs: Report, rhs: Report) -> Bool {
            lhs.schemaVersion == rhs.schemaVersion
                && lhs.status == rhs.status
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
                && lhs.belowThresholdSelectedObjectiveDomainIDs == rhs.belowThresholdSelectedObjectiveDomainIDs
                && lhs.recommendations == rhs.recommendations
                && lhs.artifactReference == rhs.artifactReference
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(schemaVersion)
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
            hasher.combine(belowThresholdSelectedObjectiveDomainIDs)
            hasher.combine(recommendations)
            hasher.combine(artifactReference)
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
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
            case belowThresholdSelectedObjectiveDomainIDs
            case recommendations
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == Self.currentSchemaVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription: "Unsupported history assessment report schema version \(schemaVersion)."
                )
            }
            let request = try container.decode(Request.self, forKey: .request)
            let summary = try container.decode(
                RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary.self,
                forKey: .summary
            )
            let decodedGates = try container.decode([Gate].self, forKey: .gates)
            let failedGateIDs = try container.decode([String].self, forKey: .failedGateIDs)
            let missingSelectedActionDomainIDs = try container.decode(
                [String].self,
                forKey: .missingSelectedActionDomainIDs
            )
            let missingSelectedObjectiveDomainIDs = try container.decode(
                [String].self,
                forKey: .missingSelectedObjectiveDomainIDs
            )
            let belowThresholdSelectedObjectiveDomainIDs = try container.decode(
                [String].self,
                forKey: .belowThresholdSelectedObjectiveDomainIDs
            )
            let decodedStatus = try container.decode(Status.self, forKey: .status)
            let decodedPassed = try container.decode(Bool.self, forKey: .passed)
            guard container.contains(.profileID),
                  container.contains(.profileTitle),
                  container.contains(.profilePath) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.profileID,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "History assessment report profile metadata must be explicit."
                    )
                )
            }
            let decodedProfileID = try container.decodeIfPresent(String.self, forKey: .profileID)
            let decodedProfileTitle = try container.decodeIfPresent(String.self, forKey: .profileTitle)
            let decodedProfilePath = try container.decodeIfPresent(String.self, forKey: .profilePath)
            let decodedRecommendations = try container.decode([String].self, forKey: .recommendations)
            let canonicalGates = SignoffRepairHistoryAssessor.gates(request: request, summary: summary)
            let canonical = Report(
                request: request,
                summary: summary,
                gates: canonicalGates,
                profile: nil,
                profilePath: nil
            )
            guard decodedStatus == canonical.status,
                  decodedPassed == canonical.passed,
                  decodedGates == canonical.gates,
                  failedGateIDs == canonical.failedGateIDs,
                  missingSelectedActionDomainIDs == canonical.missingSelectedActionDomainIDs,
                  missingSelectedObjectiveDomainIDs == canonical.missingSelectedObjectiveDomainIDs,
                  belowThresholdSelectedObjectiveDomainIDs == canonical.belowThresholdSelectedObjectiveDomainIDs,
                  decodedRecommendations == canonical.recommendations else {
                throw DecodingError.dataCorruptedError(
                    forKey: .gates,
                    in: container,
                    debugDescription: "History assessment report decisions do not match its request and summary."
                )
            }
            self.schemaVersion = schemaVersion
            self.status = canonical.status
            self.passed = canonical.passed
            self.profileID = decodedProfileID
            self.profileTitle = decodedProfileTitle
            self.profilePath = decodedProfilePath
            self.request = request
            self.summary = summary
            self.gates = canonical.gates
            self.failedGateIDs = canonical.failedGateIDs
            self.missingSelectedActionDomainIDs = canonical.missingSelectedActionDomainIDs
            self.missingSelectedObjectiveDomainIDs = canonical.missingSelectedObjectiveDomainIDs
            self.belowThresholdSelectedObjectiveDomainIDs = canonical.belowThresholdSelectedObjectiveDomainIDs
            self.recommendations = canonical.recommendations
            self.artifactReference = nil
        }

        public func encode(to encoder: Encoder) throws {
            try request.validate()
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(status, forKey: .status)
            try container.encode(passed, forKey: .passed)
            try container.encode(profileID, forKey: .profileID)
            try container.encode(profileTitle, forKey: .profileTitle)
            try container.encode(profilePath, forKey: .profilePath)
            try container.encode(request, forKey: .request)
            try container.encode(summary, forKey: .summary)
            try container.encode(gates, forKey: .gates)
            try container.encode(failedGateIDs, forKey: .failedGateIDs)
            try container.encode(missingSelectedActionDomainIDs, forKey: .missingSelectedActionDomainIDs)
            try container.encode(missingSelectedObjectiveDomainIDs, forKey: .missingSelectedObjectiveDomainIDs)
            try container.encode(
                belowThresholdSelectedObjectiveDomainIDs,
                forKey: .belowThresholdSelectedObjectiveDomainIDs
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
            belowThresholdSelectedObjectiveDomainIDs: [String],
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
            if !belowThresholdSelectedObjectiveDomainIDs.isEmpty {
                values.append(
                    "Retain accepted candidate-cycle evidence for selected objective domains: \(belowThresholdSelectedObjectiveDomainIDs.joined(separator: ","))."
                )
            }
            return values + summaryRecommendations
        }

        private static func belowThresholdSelectedObjectiveDomains(
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

    public init(
        indexService: RunReviewSignoffRepairCandidateCycleHistoryIndexService =
            RunReviewSignoffRepairCandidateCycleHistoryIndexService()
    ) {
        self.indexService = indexService
    }

    public func assess(
        forProjectAt projectRoot: URL,
        request: Request = Request(),
        profile: Profile? = nil,
        profilePath: String? = nil
    ) async throws -> Report {
        let summary = try await indexService.summarize(forProjectAt: projectRoot)
        return try assess(summary: summary, request: request, profile: profile, profilePath: profilePath)
    }

    public func assess(
        summary: RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary,
        request: Request = Request(),
        profile: Profile? = nil,
        profilePath: String? = nil
    ) throws -> Report {
        try request.validate()
        try summary.validate()
        return Report(
            request: request,
            summary: summary,
            gates: Self.gates(request: request, summary: summary),
            profile: profile,
            profilePath: profilePath
        )
    }

    private static func gates(
        request: Request,
        summary: RunReviewSignoffRepairCandidateCycleHistoryIndexService.Summary
    ) -> [Gate] {
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
        return [
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
        ]
    }

    private static func missingRequiredDomains(
        required: [String],
        observed: [String]
    ) -> [String] {
        let observedSet = Set(observed)
        return required.filter { !observedSet.contains($0) }
    }

    private static func minimumAcceptedCountPerObjectiveDomain(
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
            throw AssessmentError.readProfileFailed(path: path, reason: error.localizedDescription)
        }

        let profile: Profile
        do {
            profile = try JSONDecoder().decode(Profile.self, from: data)
        } catch {
            throw AssessmentError.decodeProfileFailed(path: path, reason: error.localizedDescription)
        }

        return profile
    }

    public func persist(
        _ report: Report,
        forProjectAt projectRoot: URL
    ) async throws -> FlowArtifactBinding {
        let workspaceStore = try XcircuiteWorkspaceStore(projectRoot: projectRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let projectRelativePath = "\(XcircuiteWorkspaceLayout.directoryName)/\(Self.reportRelativePath)"
        let binding = try await workspaceStore.persistProjectArtifact(
            content: encoder.encode(report),
            logicalID: Self.reportArtifactID,
            relativePath: ArtifactRelativePath(
                segments: projectRelativePath.split(separator: "/").map(String.init)
            ),
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: .report,
                format: .json
            ),
            mode: .replaceable
        )
        return binding
    }
}
