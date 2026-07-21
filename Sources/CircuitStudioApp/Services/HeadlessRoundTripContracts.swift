import CircuitSignoff
import CircuiteFoundation
import Foundation
import CircuitStudioCore
import CoreSpiceWaveform
import LayoutTech
import DesignFlowKernel
import PEXEngine

extension HeadlessRoundTripService {
    public struct Configuration {
        public let projectRoot: URL
        public let runID: String
        public let title: String
        public let actor: FlowRunActor
        public let testbench: Testbench
        public let postLayoutCommand: AnalysisCommand
        public let pexIR: ParasiticIR
        public let designArtifactPaths: [String]
        public let pexArtifactPaths: [String]
        public let postLayoutComparisonLimits: PostLayoutComparisonLimits?
        public let externalSignoffCommands: [ExternalSignoffCommand]
        public let externalSignoffReview: ExternalSignoffReview?
        public let approvedBy: String?
        public let approvedAt: Date?
        public let approvalKind: ExternalSignoffReview.ApprovalKind?
        public let waiverIDs: [String]
        public let createdAt: Date
        public let catalog: DeviceCatalog
        public let processConfiguration: ProcessConfiguration?
        public let layoutTech: LayoutTechDatabase?
        /// Probe nodes to cross-check post-layout against the ngspice oracle. `nil`
        /// disables the cross-check. A non-`nil` value requests a required gate, so
        /// an empty set, unavailable oracle, or failed agreement fails the run.
        public let oracleProbes: [String]?

        public init(
            projectRoot: URL,
            runID: String = UUID().uuidString,
            title: String,
            actor: FlowRunActor = FlowRunActor(
                kind: .system,
                identifier: "headless-round-trip"
            ),
            testbench: Testbench,
            postLayoutCommand: AnalysisCommand,
            pexIR: ParasiticIR,
            designArtifactPaths: [String] = [],
            pexArtifactPaths: [String] = [],
            postLayoutComparisonLimits: PostLayoutComparisonLimits? = nil,
            externalSignoffCommands: [ExternalSignoffCommand] = [],
            externalSignoffReview: ExternalSignoffReview? = nil,
            approvedBy: String? = nil,
            approvedAt: Date? = nil,
            approvalKind: ExternalSignoffReview.ApprovalKind? = nil,
            waiverIDs: [String] = [],
            createdAt: Date = Date(),
            catalog: DeviceCatalog = .standard(),
            processConfiguration: ProcessConfiguration? = nil,
            layoutTech: LayoutTechDatabase? = nil,
            oracleProbes: [String]? = nil
        ) {
            self.projectRoot = projectRoot
            self.runID = runID
            self.title = title
            self.actor = actor
            self.testbench = testbench
            self.postLayoutCommand = postLayoutCommand
            self.pexIR = pexIR
            self.designArtifactPaths = designArtifactPaths
            self.pexArtifactPaths = pexArtifactPaths
            self.postLayoutComparisonLimits = postLayoutComparisonLimits
            self.externalSignoffCommands = externalSignoffCommands
            self.externalSignoffReview = externalSignoffReview
            self.approvedBy = approvedBy
            self.approvedAt = approvedAt
            self.approvalKind = approvalKind
            self.waiverIDs = waiverIDs
            self.createdAt = createdAt
            self.catalog = catalog
            self.processConfiguration = processConfiguration
            self.layoutTech = layoutTech
            self.oracleProbes = oracleProbes
        }
    }

    public struct Result {
        public let manifest: Manifest
        public let manifestURL: URL
        public let verification: PhysicalVerificationReport
        public let preLayoutResult: SimulationResult
        public let postLayoutResult: SimulationResult
        public let externalSignoff: ExternalSignoffReview?

        public init(
            manifest: Manifest,
            manifestURL: URL,
            verification: PhysicalVerificationReport,
            preLayoutResult: SimulationResult,
            postLayoutResult: SimulationResult,
            externalSignoff: ExternalSignoffReview?
        ) {
            self.manifest = manifest
            self.manifestURL = manifestURL
            self.verification = verification
            self.preLayoutResult = preLayoutResult
            self.postLayoutResult = postLayoutResult
            self.externalSignoff = externalSignoff
        }
    }

    public struct Manifest: Sendable, Hashable, Codable {
        public let runID: String
        public let title: String
        public let createdAt: Date
        public let isRoundTripComplete: Bool
        public let isReadyForPEX: Bool
        public let stages: [Stage]
        public let artifacts: [Artifact]
        public let bottleneckSummary: BottleneckSummary?

        public init(
            runID: String,
            title: String,
            createdAt: Date,
            isRoundTripComplete: Bool,
            isReadyForPEX: Bool,
            stages: [Stage],
            artifacts: [Artifact],
            bottleneckSummary: BottleneckSummary? = nil
        ) {
            self.runID = runID
            self.title = title
            self.createdAt = createdAt
            self.isRoundTripComplete = isRoundTripComplete
            self.isReadyForPEX = isReadyForPEX
            self.stages = stages
            self.artifacts = artifacts
            self.bottleneckSummary = bottleneckSummary
        }
    }

    public struct Stage: Sendable, Hashable, Codable {
        public enum Status: String, Sendable, Hashable, Codable {
            case passed
            case failed
            case skipped
        }

        public let name: String
        public let status: Status
        public let message: String?
        public let durationSeconds: Double?

        public init(
            name: String,
            status: Status,
            message: String? = nil,
            durationSeconds: Double? = nil
        ) {
            self.name = name
            self.status = status
            self.message = message
            self.durationSeconds = durationSeconds
        }
    }

    public struct BottleneckSummary: Sendable, Hashable, Codable {
        public let totalMeasuredDurationSeconds: Double
        public let longestStageName: String?
        public let longestStageDurationSeconds: Double?
        public let failedStageName: String?
        public let recommendations: [String]

        public init(
            totalMeasuredDurationSeconds: Double,
            longestStageName: String?,
            longestStageDurationSeconds: Double?,
            failedStageName: String?,
            recommendations: [String]
        ) {
            self.totalMeasuredDurationSeconds = totalMeasuredDurationSeconds
            self.longestStageName = longestStageName
            self.longestStageDurationSeconds = longestStageDurationSeconds
            self.failedStageName = failedStageName
            self.recommendations = recommendations
        }
    }

    public struct Artifact: Sendable, Hashable, Codable {
        public let reference: ArtifactReference
        public let sourcePath: String?

        public init(
            reference: ArtifactReference,
            sourcePath: String? = nil
        ) {
            self.reference = reference
            self.sourcePath = sourcePath
        }

        public var kind: String { reference.locator.kind.rawValue }
        public var path: String { reference.locator.location.value }
        public var sha256: String { reference.digest.hexadecimalValue }
        public var byteCount: Int64 { Int64(reference.byteCount) }
    }
}
