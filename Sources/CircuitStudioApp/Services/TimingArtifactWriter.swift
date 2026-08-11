import CircuiteFoundation
import Foundation
import STAEngine

public enum TimingArtifactWriterError: Error, LocalizedError, Equatable {
    case claimReferencesMissingArtifact(statement: String, artifactID: String)
    case claimReferencesUnavailableArtifact(statement: String, artifactID: String, status: TimingArtifactStatus)
    case modelSourceReferencesMissingArtifact(modelID: String, artifactID: String)
    case modelSourceReferencesUnavailableArtifact(modelID: String, artifactID: String, status: TimingArtifactStatus)
    case constantFixtureModelInProduction(modelID: String)
    case duplicateArtifactID(String)
    case duplicateArtifactPath(path: String, artifactID: String, existingArtifactID: String)
    case unknownPublishedArtifactKind(artifactID: String, kind: String)

    public var errorDescription: String? {
        switch self {
        case .claimReferencesMissingArtifact(let statement, let artifactID):
            return "Timing claim '\(statement)' references missing artifact '\(artifactID)'."
        case .claimReferencesUnavailableArtifact(let statement, let artifactID, let status):
            return "Timing claim '\(statement)' references artifact '\(artifactID)' with status '\(status.rawValue)'."
        case .modelSourceReferencesMissingArtifact(let modelID, let artifactID):
            return "Timing model '\(modelID)' references missing artifact '\(artifactID)'."
        case .modelSourceReferencesUnavailableArtifact(let modelID, let artifactID, let status):
            return "Timing model '\(modelID)' references artifact '\(artifactID)' with status '\(status.rawValue)'."
        case .constantFixtureModelInProduction(let modelID):
            return "Timing model '\(modelID)' uses constant-fixture source in a production timing artifact."
        case .duplicateArtifactID(let id):
            return "Timing artifact id '\(id)' is declared more than once."
        case .duplicateArtifactPath(let path, let artifactID, let existingArtifactID):
            return "Timing artifact '\(artifactID)' writes to '\(path)', already used by artifact '\(existingArtifactID)'."
        case .unknownPublishedArtifactKind(let artifactID, let kind):
            return "Timing artifact '\(artifactID)' was published with unknown kind '\(kind)'."
        }
    }
}

public struct TimingArtifactWriter: Sendable {
    private static let omittedRawEvidenceWarning = "Raw per-trial SPICE decks, waveform CSV files, and measurement JSONL are intentionally omitted; summary characterization reports contain the measured timing values."

    private struct PlannedRecord: Sendable, Hashable {
        let id: String
        let kind: TimingArtifactKind
        let path: String
        let status: TimingArtifactStatus
    }

    public struct WriteResult: Sendable, Hashable {
        public let manifest: TimingArtifactManifest
        public let manifestURL: URL
        public let records: [TimingArtifactRecord]

        public init(manifest: TimingArtifactManifest, manifestURL: URL, records: [TimingArtifactRecord]) {
            self.manifest = manifest
            self.manifestURL = manifestURL
            self.records = records
        }

        public func record(id: String) -> TimingArtifactRecord? {
            records.first { $0.id == id }
        }
    }

    public init() {}

    public func write(
        runID: String,
        runDirectory: URL,
        technology: TimingTechnologyContext,
        library: TimingLibraryArtifact,
        profileSelection: TimingModelProfileSelection? = nil,
        staReport: STAExecutionResult?,
        combinationalReport: CombinationalTimingCharacterizationReport?,
        sequentialReport: SequentialTimingCharacterizationReport?,
        validationReports: [(id: String, fileName: String, report: TimingValidationReport)],
        claims: [TimingArtifactManifest.Claim] = [],
        warnings: [String] = [],
        allowConstantFixtureModels: Bool = false
    ) throws -> WriteResult {
        let timingDirectory = runDirectory.appending(path: "timing")
        let characterizationDirectory = timingDirectory.appending(path: "characterization")
        let validationDirectory = timingDirectory.appending(path: "validation")

        var plannedRecords = try plannedRecords(
            runDirectory: runDirectory,
            timingDirectory: timingDirectory,
            characterizationDirectory: characterizationDirectory,
            validationDirectory: validationDirectory,
            staReport: staReport,
            combinationalReport: combinationalReport,
            sequentialReport: sequentialReport,
            profileSelection: profileSelection,
            validationReports: validationReports
        )
        if combinationalReport != nil || sequentialReport != nil {
            plannedRecords += try omittedRawEvidenceRecords().map {
                PlannedRecord(id: $0.id, kind: $0.kind, path: $0.path, status: $0.status)
            }
        }

        let plannedManifestRecord = try plannedRecord(
            id: "timing-manifest",
            kind: .timingManifest,
            url: timingDirectory.appending(path: "manifest.json"),
            runDirectory: runDirectory
        )
        try validateUniqueArtifactIDs(plannedRecords + [plannedManifestRecord])
        try validateUniqueArtifactPaths(plannedRecords + [plannedManifestRecord])
        try validateModelSources(library.modelSources, records: plannedRecords, allowConstantFixtureModels: allowConstantFixtureModels)
        try validateClaims(claims, records: plannedRecords)

        var artifactItems: [ArtifactSetPublisher.Item] = []
        artifactItems.append(try artifactItem(
            id: "timing-library",
            kind: .timingLibrary,
            value: library,
            url: timingDirectory.appending(path: "timing-library.json"),
            runDirectory: runDirectory
        ))

        if let staReport {
            artifactItems.append(try artifactItem(
                id: "sta-report",
                kind: .staReport,
                value: staReport,
                url: timingDirectory.appending(path: "sta-report.json"),
                runDirectory: runDirectory
            ))
        }

        if let profileSelection {
            artifactItems.append(try artifactItem(
                id: "timing-model-profile-selection",
                kind: .modelProfileSelection,
                value: profileSelection,
                url: timingDirectory.appending(path: "model-profile-selection.json"),
                runDirectory: runDirectory
            ))
        }

        if let combinationalReport {
            artifactItems.append(try artifactItem(
                id: "combinational-characterization",
                kind: .characterizationReport,
                value: combinationalReport,
                url: characterizationDirectory.appending(path: "combinational-cells.json"),
                runDirectory: runDirectory
            ))
        }

        if let sequentialReport {
            artifactItems.append(try artifactItem(
                id: "sequential-dff-characterization",
                kind: .characterizationReport,
                value: sequentialReport,
                url: characterizationDirectory.appending(path: "sequential-dff.json"),
                runDirectory: runDirectory
            ))
        }

        for validation in validationReports {
            artifactItems.append(try artifactItem(
                id: validation.id,
                kind: .validationReport,
                value: validation.report,
                url: validationDirectory.appending(path: validation.fileName),
                runDirectory: runDirectory
            ))
        }
        let omittedRecords = (combinationalReport != nil || sequentialReport != nil)
            ? try omittedRawEvidenceRecords()
            : []
        let publisher = ArtifactSetPublisher(runDirectory: runDirectory)
        let preparedArtifacts = try publisher.prepare(artifactItems)
        let artifactRecords = try preparedArtifacts.map { try timingRecord(publicationRecord: $0.record) }

        let manifest = TimingArtifactManifest(
            runID: runID,
            technology: technology,
            artifacts: (artifactRecords + omittedRecords).sorted { $0.id < $1.id },
            claims: claims,
            warnings: warnings + (omittedRecords.isEmpty ? [] : [Self.omittedRawEvidenceWarning])
        )
        let manifestURL = timingDirectory.appending(path: "manifest.json")
        let manifestItem = try artifactItem(
            id: "timing-manifest",
            kind: .timingManifest,
            value: manifest,
            url: manifestURL,
            runDirectory: runDirectory
        )
        let preparedManifest = try publisher.prepare([manifestItem])
        let publishedRecords = try publisher.publish(preparedArtifacts + preparedManifest)
        let publishedTimingRecords = try publishedRecords.map { try timingRecord(publicationRecord: $0) }
        let allRecords = (publishedTimingRecords + omittedRecords).sorted { $0.id < $1.id }
        return WriteResult(manifest: manifest, manifestURL: manifestURL, records: allRecords)
    }

    private func plannedRecords(
        runDirectory: URL,
        timingDirectory: URL,
        characterizationDirectory: URL,
        validationDirectory: URL,
        staReport: STAExecutionResult?,
        combinationalReport: CombinationalTimingCharacterizationReport?,
        sequentialReport: SequentialTimingCharacterizationReport?,
        profileSelection: TimingModelProfileSelection?,
        validationReports: [(id: String, fileName: String, report: TimingValidationReport)]
    ) throws -> [PlannedRecord] {
        var records: [PlannedRecord] = []
        records.append(try plannedRecord(
            id: "timing-library",
            kind: .timingLibrary,
            url: timingDirectory.appending(path: "timing-library.json"),
            runDirectory: runDirectory
        ))

        if staReport != nil {
            records.append(try plannedRecord(
                id: "sta-report",
                kind: .staReport,
                url: timingDirectory.appending(path: "sta-report.json"),
                runDirectory: runDirectory
            ))
        }

        if profileSelection != nil {
            records.append(try plannedRecord(
                id: "timing-model-profile-selection",
                kind: .modelProfileSelection,
                url: timingDirectory.appending(path: "model-profile-selection.json"),
                runDirectory: runDirectory
            ))
        }

        if combinationalReport != nil {
            records.append(try plannedRecord(
                id: "combinational-characterization",
                kind: .characterizationReport,
                url: characterizationDirectory.appending(path: "combinational-cells.json"),
                runDirectory: runDirectory
            ))
        }

        if sequentialReport != nil {
            records.append(try plannedRecord(
                id: "sequential-dff-characterization",
                kind: .characterizationReport,
                url: characterizationDirectory.appending(path: "sequential-dff.json"),
                runDirectory: runDirectory
            ))
        }

        for validation in validationReports {
            records.append(try plannedRecord(
                id: validation.id,
                kind: .validationReport,
                url: validationDirectory.appending(path: validation.fileName),
                runDirectory: runDirectory
            ))
        }

        return records
    }

    private func plannedRecord(
        id: String,
        kind: TimingArtifactKind,
        url: URL,
        runDirectory: URL
    ) throws -> PlannedRecord {
        PlannedRecord(
            id: id,
            kind: kind,
            path: try RoundTripArtifactResolver(runDirectory: runDirectory).relativePath(for: url),
            status: .available
        )
    }

    private func artifactItem<T: Encodable>(
        id: String,
        kind: TimingArtifactKind,
        value: T,
        url: URL,
        runDirectory: URL
    ) throws -> ArtifactSetPublisher.Item {
        let relativePath = try RoundTripArtifactResolver(runDirectory: runDirectory).relativePath(for: url)
        return try ArtifactSetPublisher.jsonItem(
            value,
            id: id,
            kind: kind.rawValue,
            relativePath: relativePath
        )
    }

    private func timingRecord(publicationRecord: ArtifactPublicationRecord) throws -> TimingArtifactRecord {
        guard let kind = TimingArtifactKind(rawValue: publicationRecord.kind) else {
            throw TimingArtifactWriterError.unknownPublishedArtifactKind(
                artifactID: publicationRecord.id,
                kind: publicationRecord.kind
            )
        }
        return TimingArtifactRecord(publicationRecord: publicationRecord, kind: kind)
    }

    private func validateClaims(
        _ claims: [TimingArtifactManifest.Claim],
        records: [PlannedRecord]
    ) throws {
        let recordByID = try recordDictionary(records)
        for claim in claims {
            for artifactID in claim.artifactIDs {
                guard let record = recordByID[artifactID] else {
                    throw TimingArtifactWriterError.claimReferencesMissingArtifact(
                        statement: claim.statement,
                        artifactID: artifactID
                    )
                }
                guard record.status == .available else {
                    throw TimingArtifactWriterError.claimReferencesUnavailableArtifact(
                        statement: claim.statement,
                        artifactID: artifactID,
                        status: record.status
                    )
                }
            }
        }
    }

    private func validateModelSources(
        _ sources: [TimingModelSource],
        records: [PlannedRecord],
        allowConstantFixtureModels: Bool
    ) throws {
        let recordByID = try recordDictionary(records)
        for source in sources {
            if source.sourceType == .constantFixture && !allowConstantFixtureModels {
                throw TimingArtifactWriterError.constantFixtureModelInProduction(modelID: source.modelID)
            }
            for artifactID in source.artifactIDs {
                guard let record = recordByID[artifactID] else {
                    throw TimingArtifactWriterError.modelSourceReferencesMissingArtifact(
                        modelID: source.modelID,
                        artifactID: artifactID
                    )
                }
                guard record.status == .available else {
                    throw TimingArtifactWriterError.modelSourceReferencesUnavailableArtifact(
                        modelID: source.modelID,
                        artifactID: artifactID,
                        status: record.status
                    )
                }
            }
        }
    }

    private func validateUniqueArtifactIDs(_ records: [PlannedRecord]) throws {
        _ = try recordDictionary(records)
    }

    private func validateUniqueArtifactPaths(_ records: [PlannedRecord]) throws {
        var artifactIDByPath: [String: String] = [:]
        for record in records {
            if let existing = artifactIDByPath[record.path] {
                throw TimingArtifactWriterError.duplicateArtifactPath(
                    path: record.path,
                    artifactID: record.id,
                    existingArtifactID: existing
                )
            }
            artifactIDByPath[record.path] = record.id
        }
    }

    private func recordDictionary(_ records: [PlannedRecord]) throws -> [String: PlannedRecord] {
        var result: [String: PlannedRecord] = [:]
        for record in records {
            guard result[record.id] == nil else {
                throw TimingArtifactWriterError.duplicateArtifactID(record.id)
            }
            result[record.id] = record
        }
        return result
    }

    private func omittedRawEvidenceRecords() throws -> [TimingArtifactRecord] {
        let declarations: [(String, TimingArtifactKind, String)] = [
            ("timing-measurement-log", .measurementLog, "timing/characterization/measurements.jsonl"),
            ("timing-spice-decks", .spiceDeck, "timing/characterization/decks"),
            ("timing-waveform-csv", .waveformCSV, "timing/characterization/waveforms"),
        ]
        return try declarations.map { id, kind, path in
            let locator = try ArtifactReference.circuitStudioLocator(
                kind: kind.rawValue,
                relativePath: path
            )
            return try TimingArtifactRecord(
                logicalID: id,
                descriptor: locator.descriptor,
                relativePath: ArtifactRelativePath(
                    segments: path.split(separator: "/").map(String.init)
                ),
                kind: kind,
                status: .omitted
            )
        }
    }
}
