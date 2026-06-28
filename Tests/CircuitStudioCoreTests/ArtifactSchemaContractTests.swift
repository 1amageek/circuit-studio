import Foundation
import CircuitPhysicalDesign
import LayoutCore
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
        let fixtures = ArtifactFixture()

        try expectStrictSchemaEnvelope(TimingLibraryArtifact.self, fixtures.libraryArtifact)
        try expectStrictSchemaEnvelope(STAReportArtifact.self, fixtures.staReportArtifact)
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
    }

    @Test("Timing artifacts encode dates as ISO-8601 strings", .timeLimit(.minutes(1)))
    func timingArtifactDatesUseISO8601Strings() throws {
        let fixtures = ArtifactFixture()
        let manifestJSON = try topLevelJSON(fixtures.manifest)
        #expect(manifestJSON["createdAt"] is String)
        let profileSelectionJSON = try topLevelJSON(fixtures.profileSelection)
        #expect(profileSelectionJSON["selectedAt"] is String)

        let record = TimingArtifactRecord(
            id: "timing-library",
            kind: .timingLibrary,
            path: "timing/timing-library.json",
            status: .available,
            sha256: String(repeating: "a", count: 64),
            byteCount: 1
        )
        let recordJSON = try topLevelJSON(record)
        #expect(recordJSON["createdAt"] is String)

        _ = try JSONDecoder().decode(TimingArtifactManifest.self, from: JSONEncoder().encode(fixtures.manifest))
        _ = try JSONDecoder().decode(TimingArtifactRecord.self, from: JSONEncoder().encode(record))
    }

    @Test("Available timing artifact records require digest and byte count", .timeLimit(.minutes(1)))
    func availableTimingArtifactRecordsRequireDigestAndByteCount() throws {
        let record = TimingArtifactRecord(
            id: "timing-library",
            kind: .timingLibrary,
            path: "timing/timing-library.json",
            status: .available,
            sha256: String(repeating: "a", count: 64),
            byteCount: 1
        )
        let decoder = JSONDecoder()

        #expect(throws: DecodingError.self) {
            try decoder.decode(
                TimingArtifactRecord.self,
                from: removingTopLevelKeys(["sha256"], from: record)
            )
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(
                TimingArtifactRecord.self,
                from: removingTopLevelKeys(["byteCount"], from: record)
            )
        }

        let negativeByteCount = try mutatedTopLevelJSON(record, key: "byteCount", value: -1)
        #expect(throws: DecodingError.self) {
            try decoder.decode(TimingArtifactRecord.self, from: negativeByteCount)
        }

        let invalidDigest = try mutatedTopLevelJSON(record, key: "sha256", value: "not-a-sha256-digest")
        #expect(throws: DecodingError.self) {
            try decoder.decode(TimingArtifactRecord.self, from: invalidDigest)
        }

        let missingRecord = TimingArtifactRecord(
            id: "optional",
            kind: .measurementLog,
            path: "timing/optional.json",
            status: .missing
        )
        _ = try decoder.decode(TimingArtifactRecord.self, from: JSONEncoder().encode(missingRecord))
    }

    @Test("Layout trust report rejects inconsistent derived fields", .timeLimit(.minutes(1)))
    func layoutTrustReportRejectsInconsistentDerivedFields() throws {
        let fixtures = ArtifactFixture()
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
    func artifactIntegrityCheckerVerifiesBytesBeforeJSONDecode() throws {
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
        let decoded = try ArtifactIntegrityChecker().decodeVerifiedJSON(
            AntennaProtectionPlan.self,
            for: record,
            in: runDirectory
        )
        #expect(decoded.siteIDs == ["site0"])

        try Data(#"{"tampered":true}"#.utf8).write(
            to: runDirectory.appending(path: record.path),
            options: .atomic
        )
        #expect(throws: ArtifactIntegrityError.self) {
            try ArtifactIntegrityChecker().decodeVerifiedJSON(
                AntennaProtectionPlan.self,
                for: record,
                in: runDirectory
            )
        }
    }

    @Test("Timing library payload is read through artifact integrity", .timeLimit(.minutes(1)))
    func timingLibraryPayloadIsReadThroughArtifactIntegrity() throws {
        let fixtures = ArtifactFixture()
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
        _ = try ArtifactIntegrityChecker().decodeVerifiedJSON(
            TimingLibraryArtifact.self,
            for: libraryRecord,
            in: runDirectory
        )

        try Data(#"{"tampered":true}"#.utf8).write(
            to: runDirectory.appending(path: libraryRecord.path),
            options: .atomic
        )
        #expect(throws: ArtifactIntegrityError.self) {
            try ArtifactIntegrityChecker().decodeVerifiedJSON(
                TimingLibraryArtifact.self,
                for: libraryRecord,
                in: runDirectory
            )
        }
    }

    @Test("Timing artifact optional collections default to empty when omitted", .timeLimit(.minutes(1)))
    func timingArtifactOptionalCollectionsDefaultToEmptyWhenOmitted() throws {
        let fixtures = ArtifactFixture()

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
        let fixtures = ArtifactFixture()
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
            staReport: fixtures.staReportArtifact,
            combinationalReport: fixtures.combinationalReport,
            sequentialReport: fixtures.sequentialReport,
            validationReports: [
                (id: "clocked-validation", fileName: "clocked-validation.json", report: fixtures.validationReport),
            ]
        )

        _ = try JSONDecoder().decode(
            TimingArtifactManifest.self,
            from: Data(contentsOf: result.manifestURL)
        )
        for record in result.records where record.status == .available {
            let url = runDirectory.appending(path: record.path)
            let data = try Data(contentsOf: url)
            switch record.id {
            case "timing-manifest":
                _ = try JSONDecoder().decode(TimingArtifactManifest.self, from: data)
            case "timing-library":
                _ = try JSONDecoder().decode(TimingLibraryArtifact.self, from: data)
            case "timing-model-profile-selection":
                _ = try JSONDecoder().decode(TimingModelProfileSelection.self, from: data)
            case "sta-report":
                _ = try JSONDecoder().decode(STAReportArtifact.self, from: data)
            case "combinational-characterization":
                _ = try JSONDecoder().decode(CombinationalTimingCharacterizationReport.self, from: data)
            case "sequential-dff-characterization":
                _ = try JSONDecoder().decode(SequentialTimingCharacterizationReport.self, from: data)
            case "clocked-validation":
                _ = try JSONDecoder().decode(TimingValidationReport.self, from: data)
            default:
                Issue.record("Unexpected available timing artifact record \(record.id)")
            }
        }
    }

    @Test("Layout trust artifact set does not leave partial final artifacts on preflight failure", .timeLimit(.minutes(1)))
    func layoutTrustArtifactSetDoesNotLeavePartialFinalArtifacts() throws {
        let fixtures = ArtifactFixture()
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
        let fixtures = ArtifactFixture()
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
                staReport: fixtures.staReportArtifact,
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
    let staReportArtifact: STAReportArtifact
    let manifest: TimingArtifactManifest
    let validationReport: TimingValidationReport
    let combinationalReport: CombinationalTimingCharacterizationReport
    let sequentialReport: SequentialTimingCharacterizationReport
    let layoutTrustReport: LayoutTrustReport

    init() {
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

        let timingPath = TimingPath(
            startpoint: "ff0/Q",
            endpoint: "ff1/D",
            launchDelay: 10e-12,
            launchSlew: 20e-12,
            startEdge: .rise,
            stages: [],
            arrival: 10e-12
        )
        let timingReport = TimingReport(
            clockPeriod: 1e-9,
            worstSetupSlack: 900e-12,
            worstHoldSlack: 5e-12,
            minPeriod: 100e-12,
            criticalPath: timingPath,
            endpoints: []
        )
        staReportArtifact = STAReportArtifact(
            runID: "unit",
            designName: "unit",
            timingLibraryArtifactID: "timing-library",
            report: timingReport,
            status: .passed
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
                        shapeID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
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
