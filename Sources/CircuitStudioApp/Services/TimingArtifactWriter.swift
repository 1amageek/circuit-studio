import Foundation

public enum TimingArtifactWriterError: Error, LocalizedError, Equatable {
    case directoryCreationFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)
    case claimReferencesMissingArtifact(statement: String, artifactID: String)
    case claimReferencesUnavailableArtifact(statement: String, artifactID: String, status: TimingArtifactStatus)
    case modelSourceReferencesMissingArtifact(modelID: String, artifactID: String)
    case modelSourceReferencesUnavailableArtifact(modelID: String, artifactID: String, status: TimingArtifactStatus)
    case constantFixtureModelInProduction(modelID: String)
    case duplicateArtifactID(String)
    case duplicateArtifactPath(path: String, artifactID: String, existingArtifactID: String)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path, let reason):
            return "Failed to create timing artifact directory at \(path): \(reason)"
        case .writeFailed(let path, let reason):
            return "Failed to write timing artifact at \(path): \(reason)"
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
        }
    }
}

public struct TimingArtifactWriter: Sendable {
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
        staReport: STAReportArtifact?,
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
            validationReports: validationReports
        )
        if combinationalReport != nil || sequentialReport != nil {
            plannedRecords += omittedRawEvidenceRecords()
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

        try createDirectory(characterizationDirectory)
        try createDirectory(validationDirectory)

        var records: [TimingArtifactRecord] = []
        records.append(try writeArtifact(
            id: "timing-library",
            kind: .timingLibrary,
            value: library,
            url: timingDirectory.appending(path: "timing-library.json"),
            runDirectory: runDirectory
        ))

        if let staReport {
            records.append(try writeArtifact(
                id: "sta-report",
                kind: .staReport,
                value: staReport,
                url: timingDirectory.appending(path: "sta-report.json"),
                runDirectory: runDirectory
            ))
        }

        if let combinationalReport {
            records.append(try writeArtifact(
                id: "combinational-characterization",
                kind: .characterizationReport,
                value: combinationalReport,
                url: characterizationDirectory.appending(path: "combinational-cells.json"),
                runDirectory: runDirectory
            ))
        }

        if let sequentialReport {
            records.append(try writeArtifact(
                id: "sequential-dff-characterization",
                kind: .characterizationReport,
                value: sequentialReport,
                url: characterizationDirectory.appending(path: "sequential-dff.json"),
                runDirectory: runDirectory
            ))
        }

        for validation in validationReports {
            records.append(try writeArtifact(
                id: validation.id,
                kind: .validationReport,
                value: validation.report,
                url: validationDirectory.appending(path: validation.fileName),
                runDirectory: runDirectory
            ))
        }
        if combinationalReport != nil || sequentialReport != nil {
            records += omittedRawEvidenceRecords()
        }

        let manifest = TimingArtifactManifest(
            runID: runID,
            technology: technology,
            artifacts: records.sorted { $0.id < $1.id },
            claims: claims,
            warnings: warnings
        )
        let manifestURL = timingDirectory.appending(path: "manifest.json")
        try writeJSON(manifest, to: manifestURL)
        let manifestRecord = try artifactRecord(
            id: "timing-manifest",
            kind: .timingManifest,
            url: manifestURL,
            runDirectory: runDirectory
        )
        let allRecords = (records + [manifestRecord]).sorted { $0.id < $1.id }
        return WriteResult(manifest: manifest, manifestURL: manifestURL, records: allRecords)
    }

    private func plannedRecords(
        runDirectory: URL,
        timingDirectory: URL,
        characterizationDirectory: URL,
        validationDirectory: URL,
        staReport: STAReportArtifact?,
        combinationalReport: CombinationalTimingCharacterizationReport?,
        sequentialReport: SequentialTimingCharacterizationReport?,
        validationReports: [(id: String, fileName: String, report: TimingValidationReport)]
    ) throws -> [TimingArtifactRecord] {
        var records: [TimingArtifactRecord] = []
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
    ) throws -> TimingArtifactRecord {
        TimingArtifactRecord(
            id: id,
            kind: kind,
            path: try RoundTripArtifactResolver(runDirectory: runDirectory).relativePath(for: url),
            status: .available
        )
    }

    private func writeArtifact<T: Encodable>(
        id: String,
        kind: TimingArtifactKind,
        value: T,
        url: URL,
        runDirectory: URL
    ) throws -> TimingArtifactRecord {
        try writeJSON(value, to: url)
        return try artifactRecord(id: id, kind: kind, url: url, runDirectory: runDirectory)
    }

    private func artifactRecord(
        id: String,
        kind: TimingArtifactKind,
        url: URL,
        runDirectory: URL
    ) throws -> TimingArtifactRecord {
        let digest = try RoundTripArtifactDigest.compute(url: url)
        return TimingArtifactRecord(
            id: id,
            kind: kind,
            path: try RoundTripArtifactResolver(runDirectory: runDirectory).relativePath(for: url),
            status: .available,
            sha256: digest.sha256,
            byteCount: digest.byteCount
        )
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw TimingArtifactWriterError.directoryCreationFailed(
                path: url.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            throw TimingArtifactWriterError.writeFailed(
                path: url.path(percentEncoded: false),
                reason: error.localizedDescription
            )
        }
    }

    private func validateClaims(
        _ claims: [TimingArtifactManifest.Claim],
        records: [TimingArtifactRecord]
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
        records: [TimingArtifactRecord],
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

    private func validateUniqueArtifactIDs(_ records: [TimingArtifactRecord]) throws {
        _ = try recordDictionary(records)
    }

    private func validateUniqueArtifactPaths(_ records: [TimingArtifactRecord]) throws {
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

    private func recordDictionary(_ records: [TimingArtifactRecord]) throws -> [String: TimingArtifactRecord] {
        var result: [String: TimingArtifactRecord] = [:]
        for record in records {
            guard result[record.id] == nil else {
                throw TimingArtifactWriterError.duplicateArtifactID(record.id)
            }
            result[record.id] = record
        }
        return result
    }

    private func omittedRawEvidenceRecords() -> [TimingArtifactRecord] {
        let provenance = TimingArtifactProvenance(
            generator: "TimingArtifactWriter",
            note: "Raw per-trial SPICE decks and waveform CSV emission is intentionally omitted; summary characterization reports contain the measured timing values."
        )
        return [
            TimingArtifactRecord(
                id: "timing-measurement-log",
                kind: .measurementLog,
                path: "timing/characterization/measurements.jsonl",
                status: .omitted,
                provenance: provenance
            ),
            TimingArtifactRecord(
                id: "timing-spice-decks",
                kind: .spiceDeck,
                path: "timing/characterization/decks/",
                status: .omitted,
                provenance: provenance
            ),
            TimingArtifactRecord(
                id: "timing-waveform-csv",
                kind: .waveformCSV,
                path: "timing/characterization/waveforms/",
                status: .omitted,
                provenance: provenance
            ),
        ]
    }
}
