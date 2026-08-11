import CircuiteFoundation
import Foundation
import CircuitPhysicalDesign
import DesignFlowKernel
import LayoutCore
import STAEngine
import Testing
@testable import CircuitStudioApp

@Suite("Artifact schema contracts")
struct ArtifactSchemaContractTests {
    @Test("Antenna protection plan schema and kind are strict", .timeLimit(.minutes(1)))
    func antennaProtectionPlanSchemaAndKindAreStrict() throws {
        let plan = AntennaProtectionPlan(
            designName: "unit",
            ruleSet: AntennaProtectionRuleSet(),
            sites: []
        )

        try expectStrictSchemaEnvelope(AntennaProtectionPlan.self, plan)
    }

    @Test("Timing artifact schemas and kinds are strict", .timeLimit(.minutes(1)))
    func timingArtifactSchemasAndKindsAreStrict() throws {
        let fixtures = try ArtifactFixture()

        try expectStrictSchemaEnvelope(TimingLibraryArtifact.self, fixtures.libraryArtifact)
        try expectStrictSchemaEnvelope(TimingModelProfileSelection.self, fixtures.profileSelection)
        try expectStrictSchemaEnvelope(TimingArtifactManifest.self, fixtures.manifest)
        try expectStrictSchemaEnvelope(TimingValidationReport.self, fixtures.validationReport)
        try expectStrictSchemaEnvelope(
            CombinationalTimingCharacterizationReport.self,
            fixtures.combinationalReport
        )
        try expectStrictSchemaEnvelope(
            SequentialTimingCharacterizationReport.self,
            fixtures.sequentialReport
        )
        try expectStrictSchemaEnvelope(LayoutTrustReport.self, fixtures.layoutTrustReport)

        let staData = try JSONEncoder().encode(fixtures.staExecutionResult)
        #expect(try JSONDecoder().decode(STAExecutionResult.self, from: staData) == fixtures.staExecutionResult)
    }

    @Test("Timing artifacts encode dates as ISO-8601 strings", .timeLimit(.minutes(1)))
    func timingArtifactDatesUseISO8601Strings() throws {
        let fixtures = try ArtifactFixture()
        let manifestJSON = try topLevelJSON(fixtures.manifest)
        #expect(manifestJSON["createdAt"] is String)
        let profileSelectionJSON = try topLevelJSON(fixtures.profileSelection)
        #expect(profileSelectionJSON["selectedAt"] is String)

        let record = try timingArtifactRecord(
            id: "timing-library",
            kind: .timingLibrary,
            path: "timing/timing-library.json",
            status: .available,
            sha256: String(repeating: "a", count: 64),
            byteCount: 1
        )
        let recordJSON = try topLevelJSON(record)
        let publicationJSON = try #require(recordJSON["publication"] as? [String: Any])
        #expect(publicationJSON["createdAt"] is String)

        _ = try JSONDecoder().decode(TimingArtifactManifest.self, from: JSONEncoder().encode(fixtures.manifest))
        _ = try JSONDecoder().decode(TimingArtifactRecord.self, from: JSONEncoder().encode(record))
    }

    @Test("Available timing artifact records require digest and byte count", .timeLimit(.minutes(1)))
    func availableTimingArtifactRecordsRequireDigestAndByteCount() throws {
        let record = try timingArtifactRecord(
            id: "timing-library",
            kind: .timingLibrary,
            path: "timing/timing-library.json",
            status: .available,
            sha256: String(repeating: "a", count: 64),
            byteCount: 1
        )
        let decoder = JSONDecoder()
        let reference = try #require(record.reference)
        #expect(throws: DecodingError.self) {
            try decoder.decode(
                ArtifactReference.self,
                from: removingTopLevelKeys(["digest"], from: reference)
            )
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(
                ArtifactReference.self,
                from: removingTopLevelKeys(["byteCount"], from: reference)
            )
        }

        let invalidDigest = try mutatedTopLevelJSON(
            reference.digest,
            key: "hexadecimalValue",
            value: "not-a-sha256-digest"
        )
        #expect(throws: ContentDigestError.invalidHexadecimalValue("not-a-sha256-digest")) {
            try decoder.decode(ContentDigest.self, from: invalidDigest)
        }

        let missingRecord = try timingArtifactRecord(
            id: "optional",
            kind: .measurementLog,
            path: "timing/optional.json",
            status: .missing
        )
        _ = try decoder.decode(TimingArtifactRecord.self, from: JSONEncoder().encode(missingRecord))
    }

    @Test("Layout trust report rejects inconsistent derived fields", .timeLimit(.minutes(1)))
    func layoutTrustReportRejectsInconsistentDerivedFields() throws {
        let fixtures = try ArtifactFixture()
        let inconsistentCount = try mutatedTopLevelJSON(
            fixtures.layoutTrustReport,
            key: "ownedShapeCount",
            value: 99
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LayoutTrustReport.self, from: inconsistentCount)
        }

        let inconsistentTopCellName = try mutatedTopLevelJSON(
            fixtures.layoutTrustReport,
            key: "topCellName",
            value: "other"
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LayoutTrustReport.self, from: inconsistentTopCellName)
        }
    }

    @Test("Artifact publisher validates before creating output", .timeLimit(.minutes(1)))
    func artifactPublisherValidatesBeforeCreatingOutput() throws {
        let runDirectory = FileManager.default.temporaryDirectory
            .appending(path: "artifact-publisher-validation-\(UUID().uuidString)")
        let invalidPlan = AntennaProtectionPlan(
            designName: "unit",
            ruleSet: AntennaProtectionRuleSet(),
            sites: [
                antennaPlanSite(id: "duplicate"),
                antennaPlanSite(id: "duplicate"),
            ]
        )

        #expect(throws: AntennaProtectionPlanValidationError.duplicateSiteID("duplicate")) {
            try ArtifactPublisher(runDirectory: runDirectory).publishJSON(
                invalidPlan,
                id: AntennaProtectionPlan.artifactKind,
                kind: AntennaProtectionPlan.artifactKind,
                relativePath: "antenna/plan.json"
            )
        }
        #expect(!FileManager.default.fileExists(atPath: runDirectory.path(percentEncoded: false)))
    }

    @Test("Artifact integrity checker verifies bytes before JSON decode", .timeLimit(.minutes(1)))
    func artifactIntegrityCheckerVerifiesBytesBeforeJSONDecode() async throws {
        let runDirectory = FileManager.default.temporaryDirectory
            .appending(path: "artifact-integrity-\(UUID().uuidString)")
        defer { removeTemporaryDirectory(runDirectory) }

        let plan = AntennaProtectionPlan(
            designName: "unit",
            ruleSet: AntennaProtectionRuleSet(),
            sites: [antennaPlanSite(id: "site0")]
        )
        let record = try ArtifactPublisher(runDirectory: runDirectory).publishJSON(
            plan,
            id: AntennaProtectionPlan.artifactKind,
            kind: AntennaProtectionPlan.artifactKind,
            relativePath: "antenna/plan.json"
        )
        let decoded = try await ArtifactIntegrityChecker().decodeVerifiedJSON(
            AntennaProtectionPlan.self,
            for: record,
            in: runDirectory
        )
        #expect(decoded.siteIDs == ["site0"])

        try Data(#"{"tampered":true}"#.utf8).write(
            to: runDirectory.appending(path: record.path),
            options: .atomic
        )
        await #expect(throws: ArtifactIntegrityError.self) {
            try await ArtifactIntegrityChecker().decodeVerifiedJSON(
                AntennaProtectionPlan.self,
                for: record,
                in: runDirectory
            )
        }
    }

    @Test("Available artifact publication records require a Foundation reference", .timeLimit(.minutes(1)))
    func availableArtifactPublicationRecordsRequireAFoundationReference() throws {
        let locator = try ArtifactReference.circuitStudioLocator(
            kind: "layout-summary",
            relativePath: "layout/summary.json"
        )
        #expect(throws: ArtifactPublicationRecordValidationError.unavailableStatusRequired) {
            _ = try ArtifactPublicationRecord(
                logicalID: "layout-summary",
                descriptor: locator.descriptor,
                relativePath: ArtifactRelativePath(segments: ["layout", "summary.json"]),
                status: .available
            )
        }
        #expect(throws: ContentDigestError.self) {
            _ = try ContentDigest(algorithm: .sha256, hexadecimalValue: "invalid")
        }
    }

    @Test("Timing library payload is read through artifact integrity", .timeLimit(.minutes(1)))
    func timingLibraryPayloadIsReadThroughArtifactIntegrity() async throws {
        let fixtures = try ArtifactFixture()
        let runDirectory = FileManager.default.temporaryDirectory
            .appending(path: "timing-integrity-\(UUID().uuidString)")
        defer { removeTemporaryDirectory(runDirectory) }

        let result = try TimingArtifactWriter().write(
            runID: "unit",
            runDirectory: runDirectory,
            technology: fixtures.technology,
            library: fixtures.libraryArtifact,
            staReport: nil,
            combinationalReport: nil,
            sequentialReport: fixtures.sequentialReport,
            validationReports: []
        )
        let libraryRecord = try #require(result.record(id: "timing-library"))
        _ = try await ArtifactIntegrityChecker().decodeVerifiedJSON(
            TimingLibraryArtifact.self,
            for: libraryRecord,
            in: runDirectory
        )

        try Data(#"{"tampered":true}"#.utf8).write(
            to: runDirectory.appending(path: libraryRecord.path),
            options: .atomic
        )
        await #expect(throws: ArtifactIntegrityError.self) {
            try await ArtifactIntegrityChecker().decodeVerifiedJSON(
                TimingLibraryArtifact.self,
                for: libraryRecord,
                in: runDirectory
            )
        }
    }

    @Test("Timing artifact optional collections default to empty when omitted", .timeLimit(.minutes(1)))
    func timingArtifactOptionalCollectionsDefaultToEmptyWhenOmitted() throws {
        let fixtures = try ArtifactFixture()

        let manifest = try JSONDecoder().decode(
            TimingArtifactManifest.self,
            from: removingTopLevelKeys(["claims", "warnings"], from: fixtures.manifest)
        )
        #expect(manifest.claims.isEmpty)
        #expect(manifest.warnings.isEmpty)

        let library = try JSONDecoder().decode(
            TimingLibraryArtifact.self,
            from: removingTopLevelKeys(["warnings"], from: fixtures.libraryArtifact)
        )
        #expect(library.warnings.isEmpty)

        let validation = try JSONDecoder().decode(
            TimingValidationReport.self,
            from: removingTopLevelKeys(["warnings"], from: fixtures.validationReport)
        )
        #expect(validation.warnings.isEmpty)

        let combinational = try JSONDecoder().decode(
            CombinationalTimingCharacterizationReport.self,
            from: removingTopLevelKeys(["warnings"], from: fixtures.combinationalReport)
        )
        #expect(combinational.warnings.isEmpty)

        let sequential = try JSONDecoder().decode(
            SequentialTimingCharacterizationReport.self,
            from: removingTopLevelKeys(["warnings"], from: fixtures.sequentialReport)
        )
        #expect(sequential.warnings.isEmpty)
    }

    @Test("Timing artifact writer output decodes with schema wrappers", .timeLimit(.minutes(1)))
    func timingArtifactWriterOutputDecodesWithSchemaWrappers() throws {
        let fixtures = try ArtifactFixture()
        let runDirectory = FileManager.default.temporaryDirectory
            .appending(path: "artifact-schema-contract-\(UUID().uuidString)")
        defer {
            do {
                try FileManager.default.removeItem(at: runDirectory)
            } catch {
                Issue.record("Failed to remove temporary directory \(runDirectory.path(percentEncoded: false)): \(error)")
            }
        }

        let result = try TimingArtifactWriter().write(
            runID: "unit",
            runDirectory: runDirectory,
            technology: fixtures.technology,
            library: fixtures.libraryArtifact,
            profileSelection: fixtures.profileSelection,
            staReport: fixtures.staExecutionResult,
            combinationalReport: fixtures.combinationalReport,
            sequentialReport: fixtures.sequentialReport,
            validationReports: [
                (id: "clocked-validation", fileName: "clocked-validation.json", report: fixtures.validationReport),
            ]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        _ = try decoder.decode(
            TimingArtifactManifest.self,
            from: Data(contentsOf: result.manifestURL)
        )
        for record in result.records where record.status == .available {
            let url = runDirectory.appending(path: record.path)
            let data = try Data(contentsOf: url)
            switch record.id {
            case "timing-manifest":
                _ = try decoder.decode(TimingArtifactManifest.self, from: data)
            case "timing-library":
                _ = try decoder.decode(TimingLibraryArtifact.self, from: data)
            case "timing-model-profile-selection":
                _ = try decoder.decode(TimingModelProfileSelection.self, from: data)
            case "sta-report":
                _ = try decoder.decode(STAExecutionResult.self, from: data)
            case "combinational-characterization":
                _ = try decoder.decode(CombinationalTimingCharacterizationReport.self, from: data)
            case "sequential-dff-characterization":
                _ = try decoder.decode(SequentialTimingCharacterizationReport.self, from: data)
            case "clocked-validation":
                _ = try decoder.decode(TimingValidationReport.self, from: data)
            default:
                Issue.record("Unexpected available timing artifact record \(record.id)")
            }
        }
    }

    @Test("Layout trust artifact set does not leave partial final artifacts on preflight failure", .timeLimit(.minutes(1)))
    func layoutTrustArtifactSetDoesNotLeavePartialFinalArtifacts() throws {
        let fixtures = try ArtifactFixture()
        let runDirectory = FileManager.default.temporaryDirectory
            .appending(path: "layout-trust-atomic-\(UUID().uuidString)")
        defer { removeTemporaryDirectory(runDirectory) }
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let occupiedURL = runDirectory.appending(path: "ownership-map.json")
        try Data("occupied".utf8).write(to: occupiedURL)

        #expect(throws: ArtifactSetPublisherError.self) {
            _ = try LayoutTrustArtifactWriter().write(
                document: LayoutDocument(name: "unit", cells: []),
                report: fixtures.layoutTrustReport,
                to: runDirectory
            )
        }

        #expect(!FileManager.default.fileExists(atPath: runDirectory.appending(path: "canonical-layout.json").path))
        #expect(!FileManager.default.fileExists(atPath: runDirectory.appending(path: "net-aware-report.json").path))
        #expect(!FileManager.default.fileExists(atPath: runDirectory.appending(path: "layout-trust-report.json").path))
        #expect(!FileManager.default.fileExists(atPath: runDirectory.appending(path: "layout-artifact-manifest.json").path))
        #expect(String(decoding: try Data(contentsOf: occupiedURL), as: UTF8.self) == "occupied")
    }

    @Test("Timing artifact set does not leave partial final artifacts on preflight failure", .timeLimit(.minutes(1)))
    func timingArtifactSetDoesNotLeavePartialFinalArtifacts() throws {
        let fixtures = try ArtifactFixture()
        let runDirectory = FileManager.default.temporaryDirectory
            .appending(path: "timing-atomic-\(UUID().uuidString)")
        defer { removeTemporaryDirectory(runDirectory) }
        let timingDirectory = runDirectory.appending(path: "timing")
        try FileManager.default.createDirectory(at: timingDirectory, withIntermediateDirectories: true)
        let occupiedURL = timingDirectory.appending(path: "sta-report.json")
        try Data("occupied".utf8).write(to: occupiedURL)

        #expect(throws: ArtifactSetPublisherError.self) {
            _ = try TimingArtifactWriter().write(
                runID: "unit",
                runDirectory: runDirectory,
                technology: fixtures.technology,
                library: fixtures.libraryArtifact,
                staReport: fixtures.staExecutionResult,
                combinationalReport: fixtures.combinationalReport,
                sequentialReport: fixtures.sequentialReport,
                validationReports: []
            )
        }

        #expect(!FileManager.default.fileExists(atPath: timingDirectory.appending(path: "timing-library.json").path))
        #expect(!FileManager.default.fileExists(atPath: timingDirectory.appending(path: "manifest.json").path))
        #expect(!FileManager.default.fileExists(
            atPath: timingDirectory.appending(path: "characterization/combinational-cells.json").path
        ))
        #expect(String(decoding: try Data(contentsOf: occupiedURL), as: UTF8.self) == "occupied")
    }

    @Test("Artifact set publisher rejects prepared records whose digest no longer matches payload", .timeLimit(.minutes(1)))
    func artifactSetPublisherRejectsPreparedRecordPayloadMismatch() throws {
        let runDirectory = FileManager.default.temporaryDirectory
            .appending(path: "artifact-set-mismatch-\(UUID().uuidString)")
        defer { removeTemporaryDirectory(runDirectory) }
        let publisher = ArtifactSetPublisher(runDirectory: runDirectory)
        let prepared = try publisher.prepare([
            ArtifactSetPublisher.Item(
                id: "payload",
                kind: "unit-json",
                relativePath: "payload.json",
                data: Data(#"{"value":"original"}"#.utf8)
            ),
        ])
        let original = try #require(prepared.first)
        let tampered = ArtifactSetPublisher.PreparedItem(
            item: ArtifactSetPublisher.Item(
                id: original.item.id,
                kind: original.item.kind,
                relativePath: original.item.relativePath,
                data: Data(#"{"value":"tampered"}"#.utf8)
            ),
            record: original.record
        )

        #expect(throws: ArtifactSetPublisherError.self) {
            _ = try publisher.publish([tampered])
        }
        #expect(!FileManager.default.fileExists(atPath: runDirectory.path(percentEncoded: false)))
    }

    private func expectStrictSchemaEnvelope<T: Codable>(
        _ type: T.Type,
        _ value: T
    ) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode(value)
        _ = try decoder.decode(type, from: encoded)

        let wrongSchema = try mutatedTopLevelJSON(value, key: "schemaVersion", value: 999)
        #expect(throws: DecodingError.self) {
            try decoder.decode(type, from: wrongSchema)
        }

        let wrongKind = try mutatedTopLevelJSON(value, key: "kind", value: "wrong-kind")
        #expect(throws: DecodingError.self) {
            try decoder.decode(type, from: wrongKind)
        }
    }

    private func mutatedTopLevelJSON<T: Encodable>(
        _ value: T,
        key: String,
        value replacement: Any
    ) throws -> Data {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard var object = decoded as? [String: Any] else {
            throw FixtureError.invalidJSONObject
        }
        object[key] = replacement
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func removingTopLevelKeys<T: Encodable>(_ keys: Set<String>, from value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard var object = decoded as? [String: Any] else {
            throw FixtureError.invalidJSONObject
        }
        for key in keys {
            object.removeValue(forKey: key)
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func topLevelJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let object = decoded as? [String: Any] else {
            throw FixtureError.invalidJSONObject
        }
        return object
    }

    private func timingArtifactRecord(
        id: String,
        kind: TimingArtifactKind,
        path: String,
        status: TimingArtifactStatus,
        sha256: String? = nil,
        byteCount: Int64? = nil
    ) throws -> TimingArtifactRecord {
        let locator = try ArtifactReference.circuitStudioLocator(
            kind: kind.rawValue,
            relativePath: path
        )
        switch status {
        case .available:
            let digest = try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: try #require(sha256)
            )
            let count = try #require(byteCount)
            let unsignedCount = try #require(UInt64(exactly: count))
            let reference = try ArtifactReference(
                    digest: digest,
                    byteCount: unsignedCount,
                    descriptor: locator.descriptor
            )
            let binding = try FlowArtifactBinding(
                logicalID: id,
                reference: reference,
                availability: .local(
                    artifactID: reference.id,
                    rootID: ArtifactRootID(rawValue: "artifact-schema-tests"),
                    relativePath: ArtifactRelativePath(
                        segments: path.split(separator: "/").map(String.init)
                    )
                )
            )
            return try TimingArtifactRecord(
                binding: binding,
                kind: kind
            )
        case .omitted, .missing:
            return try TimingArtifactRecord(
                logicalID: id,
                descriptor: locator.descriptor,
                relativePath: ArtifactRelativePath(
                    segments: path.split(separator: "/").map(String.init)
                ),
                kind: kind,
                status: status
            )
        }
    }
}

private enum FixtureError: Error {
    case invalidJSONObject
}

private func removeTemporaryDirectory(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return
    }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory \(url.path(percentEncoded: false)): \(error)")
    }
}

private func antennaPlanSite(id: String) -> AntennaProtectionPlan.Site {
    AntennaProtectionPlan.Site(
        id: id,
        net: "a",
        instanceName: "g0",
        gateName: "A",
        centerXMicrons: 1.0,
        trackYMicrons: 2.0,
        gateLoadCount: 1,
        hasDiffusionDischargeAnchor: false,
        spanMicrons: 10.0,
        spanPerGateMicrons: 10.0,
        strategy: .diffusionTie,
        reason: "unit fixture"
    )
}

private struct ArtifactFixture {
    let technology: TimingTechnologyContext
    let sequentialTiming: SequentialTiming
    let libraryArtifact: TimingLibraryArtifact
    let profileSelection: TimingModelProfileSelection
    let staExecutionResult: STAExecutionResult
    let manifest: TimingArtifactManifest
    let validationReport: TimingValidationReport
    let combinationalReport: CombinationalTimingCharacterizationReport
    let sequentialReport: SequentialTimingCharacterizationReport
    let layoutTrustReport: LayoutTrustReport

    init() throws {
        let profileReference = TimingModelProfileReference(
            profileID: "unit-profile",
            resourceName: "unit-profile.json"
        )
        let context = TimingTechnologyContext(
            processName: "test",
            cornerID: "tt",
            supplyVoltage: 1.8,
            deviceModelID: "unit",
            modelProfile: profileReference
        )
        let timing = SequentialTiming(
            clkToQRise: .constant(100e-12),
            clkToQFall: .constant(120e-12),
            qTransitionRise: .constant(30e-12),
            qTransitionFall: .constant(35e-12),
            setupTime: 20e-12,
            holdTime: 5e-12,
            dataCapacitance: 1e-15,
            clockCapacitance: 2e-15
        )
        technology = context
        sequentialTiming = timing
        libraryArtifact = TimingLibraryArtifact(
            runID: "unit",
            technology: context,
            library: TimingLibrary(flipFlop: timing),
            modelSources: [
                TimingModelSource(
                    modelID: "dff",
                    modelKind: .sequentialCell,
                    sourceType: .characterized,
                    artifactIDs: ["sequential-dff-characterization"]
                ),
            ]
        )
        profileSelection = TimingModelProfileSelection(
            runID: "unit",
            sourceKind: .bundledResource,
            selectionReason: "unit fixture",
            profileSchemaVersion: 1,
            profile: profileReference,
            technology: context
        )

        let timingPath = STAPath(
            modeID: "functional",
            cornerID: "tt",
            startpoint: "ff0/Q",
            endpoint: "ff1/D",
            arrival: 10e-12,
            required: 910e-12,
            slack: 900e-12,
            stages: [],
        )
        let timingPayload = STAPayload(
            worstSetupSlack: 900e-12,
            worstHoldSlack: 5e-12,
            analyzedCorners: ["tt"],
            analyzedModes: ["functional"],
            criticalPaths: [timingPath]
        )
        let timestamp = Date(timeIntervalSince1970: 1)
        staExecutionResult = try STAExecutionResult(
            runID: "unit",
            status: .completed,
            payload: timingPayload,
            provenance: try ExecutionProvenance(
                producer: ProducerIdentity(
                    kind: .engine,
                    identifier: "timing.sta",
                    version: "1"
                ),
                startedAt: timestamp,
                completedAt: timestamp
            )
        )
        manifest = TimingArtifactManifest(
            runID: "unit",
            technology: context,
            artifacts: [],
            claims: [],
            warnings: []
        )
        validationReport = TimingValidationReport(
            scope: .clockedPath,
            runID: "unit",
            designName: "unit",
            sourceArtifacts: ["timing-library"],
            comparisons: [
                TimingValidationComparison(
                    id: "clk2q",
                    metric: "clkToQ",
                    predictedSeconds: 100e-12,
                    measuredSeconds: 100e-12,
                    absoluteErrorSeconds: 0,
                    relativeError: 0,
                    tolerance: 0.1,
                    passed: true,
                    artifactIDs: ["timing-library"]
                ),
            ],
            status: .passed
        )
        combinationalReport = CombinationalTimingCharacterizationReport(
            technology: context,
            inputSlews: [50e-12],
            outputLoads: [1e-15],
            cells: [],
            status: .passed
        )
        sequentialReport = SequentialTimingCharacterizationReport(
            cellName: "dff",
            topologyHash: "hash",
            activeClockEdge: .rising,
            technology: context,
            characterizationGrid: SequentialTimingCharacterizationGrid(
                clockSlews: [80e-12],
                dataSlews: [80e-12],
                outputLoads: [1e-15],
                setupHoldSearchResolution: 10e-12,
                setupHoldSearchWindow: 100e-12
            ),
            timing: timing,
            clkToQMeasurements: [],
            qTransitionMeasurements: [],
            setupMeasurements: [],
            holdMeasurements: [],
            status: .passed
        )
        layoutTrustReport = LayoutTrustReport(
            topCellName: "unit",
            ownershipMap: LayoutOwnershipMap(
                topCellName: "unit",
                records: [
                    LayoutOwnershipRecord(
                        cellName: "unit",
                        shapeID: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
                        layerName: "met1",
                        netID: nil,
                        netName: "a",
                        status: .owned,
                        reason: "unit fixture"
                    ),
                ]
            ),
            netAwareReport: NetAwareLayoutEvaluator.Report(
                shorts: [],
                opens: [],
                unownedShapes: []
            )
        )
    }
}
