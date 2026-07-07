import Foundation
import Testing
@testable import CircuitStudioApp

@Suite("Sequential timing characterization")
struct SequentialTimingCharacterizerTests {
    @Test("A generated DFF characterizes clk-to-Q and setup/hold from SPICE", .timeLimit(.minutes(5)))
    func dffCharacterizes() async throws {
        let report = try await TimingCharacterizationTestCache.shared.characterizedFlipFlopReport()

        #expect(report.status == .passed)
        #expect(report.kind == "sequential-characterization-report")
        #expect(report.technology.modelProfile?.profileID == "sky130.level1-device-model.v1")
        let expectedResourceName = try Level1DeviceModel.loadBundledDefaultProfileResourceName()
        #expect(report.technology.modelProfile?.resourceName == expectedResourceName)
        let clockSlew = try #require(report.characterizationGrid.clockSlews.first)
        #expect(report.timing.clkToQRise.lookup(inputSlew: clockSlew, outputLoad: 1e-15) > 0)
        #expect(report.timing.clkToQFall.lookup(inputSlew: clockSlew, outputLoad: 1e-15) > 0)
        #expect(report.timing.clkToQRise.inputSlews == [80e-12])
        #expect(report.timing.setupTime.isFinite && report.timing.setupTime >= 0)
        #expect(report.timing.holdTime.isFinite && report.timing.holdTime >= 0)
        #expect(report.clkToQMeasurements.count == 2)
        #expect(report.setupMeasurements.count == 2)
        #expect(report.holdMeasurements.count == 2)
    }

    @Test("Unsupported sequential topology is rejected before simulation", .timeLimit(.minutes(1)))
    func unsupportedSequentialTopologyThrows() async throws {
        let characterizer = try SequentialTimingCharacterizer(outputLoads: [1e-15])
        let unsupportedNetlist = try GateLevelNetlist.and2(name: "not_dff")

        await #expect(throws: SequentialTimingCharacterizer.CharacterizeError.self) {
            _ = try await characterizer.characterizeFlipFlop(
                unsupportedNetlist,
                cellName: "not_dff"
            )
        }
    }

    @Test("Mismatched technology context is rejected before simulation", .timeLimit(.minutes(1)))
    func mismatchedTechnologyContextThrows() async throws {
        let model = try Level1DeviceModel.loadBundledDefault()
        let expectedHash = try TimingTopologyHasher.hashModel(model)
        let mismatchedTechnology = TimingTechnologyContext(
            processName: "unit",
            cornerID: "tt",
            supplyVoltage: model.supplyVoltage,
            deviceModelID: "wrong",
            deviceModelHash: "wrong-hash",
            modelProfile: TimingModelProfileReference(profileID: "wrong-profile")
        )
        let characterizer = try SequentialTimingCharacterizer(
            model: model,
            technologyContext: mismatchedTechnology,
            outputLoads: [1e-15]
        )

        await #expect(throws: SequentialTimingCharacterizer.CharacterizeError.technologyModelHashMismatch(
            expectedModelHash: expectedHash,
            actualModelHash: "wrong-hash"
        )) {
            _ = try await characterizer.characterizeFlipFlop()
        }
    }

    @Test("Timing artifacts persist run-relative manifest records", .timeLimit(.minutes(1)))
    func timingArtifactsPersist() throws {
        let fixture = timingArtifactFixture()
        let runDirectory = FileManager.default.temporaryDirectory.appending(path: "timing-artifacts-\(UUID().uuidString)")
        defer {
            removeTemporaryDirectoryIfPresent(runDirectory)
        }

        let result = try TimingArtifactWriter().write(
            runID: "unit",
            runDirectory: runDirectory,
            technology: fixture.technology,
            library: fixture.libraryArtifact,
            staReport: nil,
            combinationalReport: nil,
            sequentialReport: fixture.sequentialReport,
            validationReports: []
        )

        #expect(FileManager.default.fileExists(atPath: result.manifestURL.path))
        let libraryRecord = try #require(result.record(id: "timing-library"))
        #expect(libraryRecord.path == "timing/timing-library.json")
        #expect(libraryRecord.sha256?.isEmpty == false)
        #expect(libraryRecord.byteCount ?? 0 > 0)
        let sequentialRecord = try #require(result.record(id: "sequential-dff-characterization"))
        #expect(sequentialRecord.path == "timing/characterization/sequential-dff.json")
        let measurementLogRecord = try #require(result.record(id: "timing-measurement-log"))
        #expect(measurementLogRecord.status == .omitted)
    }

    @Test("Timing artifact writer rejects missing claim references", .timeLimit(.minutes(1)))
    func timingArtifactWriterRejectsMissingClaimReferences() {
        let fixture = timingArtifactFixture()
        let runDirectory = FileManager.default.temporaryDirectory.appending(path: "timing-artifacts-bad-claim-\(UUID().uuidString)")
        defer {
            removeTemporaryDirectoryIfPresent(runDirectory)
        }

        #expect(throws: TimingArtifactWriterError.claimReferencesMissingArtifact(
            statement: "bad claim",
            artifactID: "missing-artifact"
        )) {
            _ = try TimingArtifactWriter().write(
                runID: "unit",
                runDirectory: runDirectory,
                technology: fixture.technology,
                library: fixture.libraryArtifact,
                staReport: nil,
                combinationalReport: nil,
                sequentialReport: fixture.sequentialReport,
                validationReports: [],
                claims: [
                    .init(statement: "bad claim", passed: true, artifactIDs: ["missing-artifact"]),
                ]
            )
        }
        #expect(!FileManager.default.fileExists(atPath: runDirectory.appending(path: "timing/timing-library.json").path))
    }

    @Test("Timing artifact writer rejects omitted claim references", .timeLimit(.minutes(1)))
    func timingArtifactWriterRejectsOmittedClaimReferences() {
        let fixture = timingArtifactFixture()
        let runDirectory = FileManager.default.temporaryDirectory.appending(path: "timing-artifacts-omitted-claim-\(UUID().uuidString)")
        defer {
            removeTemporaryDirectoryIfPresent(runDirectory)
        }

        #expect(throws: TimingArtifactWriterError.claimReferencesUnavailableArtifact(
            statement: "raw evidence claim",
            artifactID: "timing-measurement-log",
            status: .omitted
        )) {
            _ = try TimingArtifactWriter().write(
                runID: "unit",
                runDirectory: runDirectory,
                technology: fixture.technology,
                library: fixture.libraryArtifact,
                staReport: nil,
                combinationalReport: nil,
                sequentialReport: fixture.sequentialReport,
                validationReports: [],
                claims: [
                    .init(statement: "raw evidence claim", passed: true, artifactIDs: ["timing-measurement-log"]),
                ]
            )
        }
    }

    @Test("Timing artifact writer rejects production constant-fixture models", .timeLimit(.minutes(1)))
    func timingArtifactWriterRejectsProductionConstantFixtureModels() {
        var fixture = timingArtifactFixture()
        fixture.libraryArtifact = TimingLibraryArtifact(
            runID: "unit",
            technology: fixture.technology,
            library: fixture.libraryArtifact.library,
            modelSources: [
                TimingModelSource(
                    modelID: "dff",
                    modelKind: .sequentialCell,
                    sourceType: .constantFixture,
                    artifactIDs: ["sequential-dff-characterization"]
                ),
            ]
        )
        let runDirectory = FileManager.default.temporaryDirectory.appending(path: "timing-artifacts-fixture-\(UUID().uuidString)")
        defer {
            removeTemporaryDirectoryIfPresent(runDirectory)
        }

        #expect(throws: TimingArtifactWriterError.constantFixtureModelInProduction(modelID: "dff")) {
            _ = try TimingArtifactWriter().write(
                runID: "unit",
                runDirectory: runDirectory,
                technology: fixture.technology,
                library: fixture.libraryArtifact,
                staReport: nil,
                combinationalReport: nil,
                sequentialReport: fixture.sequentialReport,
                validationReports: []
            )
        }
        #expect(!FileManager.default.fileExists(atPath: runDirectory.appending(path: "timing/timing-library.json").path))
    }

    @Test("Timing artifact writer rejects duplicate artifact IDs before writing files", .timeLimit(.minutes(1)))
    func timingArtifactWriterRejectsDuplicateArtifactIDsBeforeWriting() {
        let fixture = timingArtifactFixture()
        let runDirectory = FileManager.default.temporaryDirectory.appending(path: "timing-artifacts-duplicate-\(UUID().uuidString)")
        defer {
            removeTemporaryDirectoryIfPresent(runDirectory)
        }

        #expect(throws: TimingArtifactWriterError.duplicateArtifactID("timing-library")) {
            _ = try TimingArtifactWriter().write(
                runID: "unit",
                runDirectory: runDirectory,
                technology: fixture.technology,
                library: fixture.libraryArtifact,
                staReport: nil,
                combinationalReport: nil,
                sequentialReport: fixture.sequentialReport,
                validationReports: [
                    (id: "timing-library", fileName: "duplicate.json", report: timingValidationFixture()),
                ]
            )
        }
        #expect(!FileManager.default.fileExists(atPath: runDirectory.appending(path: "timing/timing-library.json").path))
    }

    @Test("Timing artifact writer reserves the manifest artifact ID", .timeLimit(.minutes(1)))
    func timingArtifactWriterRejectsManifestArtifactIDCollisionBeforeWriting() {
        let fixture = timingArtifactFixture()
        let runDirectory = FileManager.default.temporaryDirectory.appending(path: "timing-artifacts-manifest-duplicate-\(UUID().uuidString)")
        defer {
            removeTemporaryDirectoryIfPresent(runDirectory)
        }

        #expect(throws: TimingArtifactWriterError.duplicateArtifactID("timing-manifest")) {
            _ = try TimingArtifactWriter().write(
                runID: "unit",
                runDirectory: runDirectory,
                technology: fixture.technology,
                library: fixture.libraryArtifact,
                staReport: nil,
                combinationalReport: nil,
                sequentialReport: fixture.sequentialReport,
                validationReports: [
                    (id: "timing-manifest", fileName: "manifest-collision.json", report: timingValidationFixture()),
                ]
            )
        }
        #expect(!FileManager.default.fileExists(atPath: runDirectory.appending(path: "timing/manifest.json").path))
    }

    @Test("Timing artifact writer rejects duplicate artifact paths before writing files", .timeLimit(.minutes(1)))
    func timingArtifactWriterRejectsDuplicateArtifactPathsBeforeWriting() {
        let fixture = timingArtifactFixture()
        let runDirectory = FileManager.default.temporaryDirectory.appending(path: "timing-artifacts-path-duplicate-\(UUID().uuidString)")
        defer {
            removeTemporaryDirectoryIfPresent(runDirectory)
        }

        #expect(throws: TimingArtifactWriterError.duplicateArtifactPath(
            path: "timing/validation/duplicate.json",
            artifactID: "validation-b",
            existingArtifactID: "validation-a"
        )) {
            _ = try TimingArtifactWriter().write(
                runID: "unit",
                runDirectory: runDirectory,
                technology: fixture.technology,
                library: fixture.libraryArtifact,
                staReport: nil,
                combinationalReport: nil,
                sequentialReport: fixture.sequentialReport,
                validationReports: [
                    (id: "validation-a", fileName: "duplicate.json", report: timingValidationFixture()),
                    (id: "validation-b", fileName: "duplicate.json", report: timingValidationFixture()),
                ]
            )
        }
        #expect(!FileManager.default.fileExists(atPath: runDirectory.appending(path: "timing/timing-library.json").path))
    }

    private func timingArtifactFixture() -> (
        technology: TimingTechnologyContext,
        libraryArtifact: TimingLibraryArtifact,
        sequentialReport: SequentialTimingCharacterizationReport
    ) {
        let technology = TimingTechnologyContext(
            processName: "test",
            cornerID: "tt",
            supplyVoltage: 1.8,
            deviceModelID: "unit"
        )
        let ff = SequentialTiming(
            clkToQRise: .constant(100e-12),
            clkToQFall: .constant(120e-12),
            qTransitionRise: .constant(30e-12),
            qTransitionFall: .constant(35e-12),
            setupTime: 20e-12,
            holdTime: 5e-12,
            dataCapacitance: 1e-15,
            clockCapacitance: 2e-15
        )
        let library = TimingLibrary(flipFlop: ff)
        let libraryArtifact = TimingLibraryArtifact(
            runID: "unit",
            technology: technology,
            library: library,
            modelSources: [
                TimingModelSource(
                    modelID: "dff",
                    modelKind: .sequentialCell,
                    sourceType: .characterized,
                    artifactIDs: ["sequential-dff-characterization"]
                ),
            ]
        )
        let sequentialReport = SequentialTimingCharacterizationReport(
            cellName: "dff",
            topologyHash: "hash",
            activeClockEdge: .rising,
            technology: technology,
            characterizationGrid: SequentialTimingCharacterizationGrid(
                clockSlews: [80e-12],
                dataSlews: [80e-12],
                outputLoads: [1e-15],
                setupHoldSearchResolution: 10e-12,
                setupHoldSearchWindow: 100e-12
            ),
            timing: ff,
            clkToQMeasurements: [],
            qTransitionMeasurements: [],
            setupMeasurements: [],
            holdMeasurements: [],
            status: .passed
        )
        return (technology, libraryArtifact, sequentialReport)
    }

    private func timingValidationFixture() -> TimingValidationReport {
        TimingValidationReport(
            scope: .combinationalPath,
            runID: "unit",
            designName: "unit",
            sourceArtifacts: ["timing-library"],
            comparisons: [
                TimingValidationComparison(
                    id: "delay",
                    metric: "combinationalDelay",
                    predictedSeconds: 10e-12,
                    measuredSeconds: 10e-12,
                    absoluteErrorSeconds: 0,
                    relativeError: 0,
                    tolerance: 0.1,
                    passed: true,
                    artifactIDs: ["timing-library"]
                ),
            ],
            status: .passed
        )
    }

    private func removeTemporaryDirectoryIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove temporary timing artifact directory: \(error)")
        }
    }
}
