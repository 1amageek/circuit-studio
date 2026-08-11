import DesignFlowKernel
import Foundation
import CircuiteFoundation
import Xcircuite

extension RunReviewService {
    public func loadArtifactPreview(
        runID: String,
        artifactPath: String,
        projectRoot: URL,
        maxBytes: Int = 4096
    ) async throws -> RunReviewArtifactPreview {
        guard maxBytes > 0 else {
            throw RunReviewServiceError.artifactPreviewInvalidLimit(limit: maxBytes)
        }
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredReviewLedgerLoader(store: store)
        let bundle = try await configuredReviewBundler(store: store, loader: loader)
            .makeReviewBundle(
                runID: runID,
                workspaceID: try await workspaceID(store: store)
            )
        guard let artifact = bundle.artifacts.first(where: { $0.binding.circuitStudioPresentationPath == artifactPath }) else {
            throw RunReviewServiceError.artifactPreviewNotFound(
                runID: runID,
                artifactPath: artifactPath
            )
        }
        return try await makeArtifactPreview(
            artifact: artifact,
            projectRoot: projectRoot,
            artifactReader: store,
            maxBytes: maxBytes
        )
    }

    public func loadArtifactPreview(
        runID: String,
        artifact: FlowRunReviewArtifact,
        projectRoot: URL,
        maxBytes: Int = 4096
    ) async throws -> RunReviewArtifactPreview {
        guard maxBytes > 0 else {
            throw RunReviewServiceError.artifactPreviewInvalidLimit(limit: maxBytes)
        }
        let store = try workspaceStore(projectRoot: projectRoot)
        let loader = configuredReviewLedgerLoader(store: store)
        let bundle = try await configuredReviewBundler(store: store, loader: loader)
            .makeReviewBundle(
                runID: runID,
                workspaceID: try await workspaceID(store: store)
            )
        guard let resolvedArtifact = bundle.artifacts.first(where: { isSameArtifact($0, as: artifact) }) else {
            throw RunReviewServiceError.artifactPreviewNotFound(
                runID: runID,
                artifactPath: artifact.binding.circuitStudioPresentationPath
            )
        }
        return try await makeArtifactPreview(
            artifact: resolvedArtifact,
            projectRoot: projectRoot,
            artifactReader: store,
            maxBytes: maxBytes
        )
    }

    private func makeArtifactPreview(
        artifact: FlowRunReviewArtifact,
        projectRoot: URL,
        artifactReader: any XcircuiteArtifactBindingReading,
        maxBytes: Int
    ) async throws -> RunReviewArtifactPreview {
        let url = try verifiedArtifactURL(for: artifact, projectRoot: projectRoot)
        try validateArtifactIntegrity(artifact)
        let verifiedData = try await artifactReader.loadArtifactContent(for: artifact.binding)
        let truncated = verifiedData.count > maxBytes
        let data = truncated ? Data(verifiedData.prefix(maxBytes)) : verifiedData
        let text = String(data: data, encoding: .utf8)
        let structured = structuredPreview(
            data: data,
            artifact: artifact,
            truncated: truncated
        )
        return RunReviewArtifactPreview(
            artifact: artifact,
            resolvedPath: url.path(percentEncoded: false),
            byteCount: artifact.reference.byteCount,
            previewByteCount: data.count,
            truncated: truncated,
            isText: text != nil,
            text: text ?? "",
            lineCount: text.map(lineCount) ?? 0,
            structuredPreview: structured.preview,
            parseIssue: structured.issue,
            waveformPreview: structured.waveform
        )
    }

    func isSameArtifact(
        _ candidate: FlowRunReviewArtifact,
        as artifact: FlowRunReviewArtifact
    ) -> Bool {
        candidate.binding.circuitStudioPresentationPath == artifact.binding.circuitStudioPresentationPath
            && candidate.purpose == artifact.purpose
            && candidate.reference.id == artifact.reference.id
            && candidate.stageID == artifact.stageID
            && candidate.binding.kind == artifact.binding.kind
            && candidate.binding.format == artifact.binding.format
    }

    func validateArtifactIntegrity(
        _ artifact: FlowRunReviewArtifact
    ) throws {
        guard let integrity = artifact.integrity else {
            throw RunReviewServiceError.artifactPreviewIntegrityUnverified(
                path: artifact.binding.circuitStudioPresentationPath,
                status: "missing",
                message: "No recorded artifact integrity state is available."
            )
        }
        guard integrity.status == .verified else {
            throw RunReviewServiceError.artifactPreviewIntegrityUnverified(
                path: artifact.binding.circuitStudioPresentationPath,
                status: integrity.status.rawValue,
                message: integrity.message
            )
        }
    }

    func verifiedArtifactURL(
        for artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) throws -> URL {
        let rootPath = (projectRoot.path(percentEncoded: false) as NSString).standardizingPath
        let artifactURL: URL
        do {
            artifactURL = projectRoot.appending(
                path: try artifact.binding.requireLocalRelativePath().stringValue
            )
        } catch {
            throw RunReviewServiceError.artifactPreviewEscapesProject(
                path: artifact.binding.circuitStudioPresentationPath
            )
        }
        let canonicalRootPath = URL(filePath: rootPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path(percentEncoded: false)
        let canonicalArtifactPath = artifactURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path(percentEncoded: false)
        guard isContained(path: canonicalArtifactPath, byRootPath: canonicalRootPath) else {
            throw RunReviewServiceError.artifactPreviewEscapesProject(path: artifact.binding.circuitStudioPresentationPath)
        }
        return URL(filePath: canonicalArtifactPath)
    }

    func loadVerifiedArtifactData(
        _ artifact: FlowRunReviewArtifact,
        projectRoot: URL,
        maxBytes: Int
    ) async throws -> Data {
        guard maxBytes > 0 else {
            throw RunReviewServiceError.artifactPreviewInvalidLimit(limit: maxBytes)
        }
        try validateArtifactIntegrity(artifact)
        _ = try verifiedArtifactURL(for: artifact, projectRoot: projectRoot)
        let byteCount = artifact.reference.byteCount
        guard byteCount <= UInt64(maxBytes) else {
            throw RunReviewServiceError.artifactPreviewTooLarge(
                path: artifact.binding.circuitStudioPresentationPath,
                byteCount: byteCount,
                limit: maxBytes
            )
        }
        do {
            return try await workspaceStore(projectRoot: projectRoot)
                .loadArtifactContent(for: artifact.binding)
        } catch XcircuiteWorkspaceStoreError.artifactIntegrityFailed(_, let issues) {
            let message = issues.contains { $0.code == .digestMismatch }
                ? "Recorded SHA-256 does not match the current artifact."
                : issues.map(\.code.rawValue).joined(separator: ", ")
            throw RunReviewServiceError.artifactPreviewIntegrityUnverified(
                path: artifact.binding.circuitStudioPresentationPath,
                status: issues.first?.code.rawValue ?? "integrity-failure",
                message: message
            )
        } catch let error as RunReviewServiceError {
            throw error
        } catch {
            throw RunReviewServiceError.artifactPreviewUnreadable(
                path: artifact.binding.circuitStudioPresentationPath,
                message: error.localizedDescription
            )
        }
    }

    private func isContained(path: String, byRootPath rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func structuredPreview(
        data: Data,
        artifact: FlowRunReviewArtifact,
        truncated: Bool
    ) -> (preview: String?, issue: String?, waveform: RunReviewWaveformPreview?) {
        if artifact.binding.format == .json {
            let preview = jsonStructuredPreview(data: data, truncated: truncated)
            return (preview.preview, preview.issue, nil)
        }
        if artifact.binding.format == .csv || artifact.binding.kind == .waveform {
            return csvStructuredPreview(
                data: data,
                artifact: artifact,
                truncated: truncated
            )
        }
        return (nil, nil, nil)
    }

    private func jsonStructuredPreview(
        data: Data,
        truncated: Bool
    ) -> (preview: String?, issue: String?) {
        guard !truncated else {
            return (nil, "JSON preview is truncated before parsing.")
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            return (jsonOutline(object), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func csvStructuredPreview(
        data: Data,
        artifact: FlowRunReviewArtifact,
        truncated: Bool
    ) -> (preview: String?, issue: String?, waveform: RunReviewWaveformPreview?) {
        guard !truncated else {
            return (nil, "CSV preview is truncated before parsing.", nil)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return (nil, "CSV preview is not valid UTF-8.", nil)
        }
        do {
            let rows = try csvRows(text)
            guard let header = rows.first else {
                return ("CSV rows=0 columns=0", nil, nil)
            }
            let dataRows = rows.dropFirst().filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            let visibleColumns = header.prefix(6).joined(separator: ",")
            let suffix = header.count > 6 ? ",..." : ""
            return (
                "CSV rows=\(dataRows.count) columns=\(header.count) [\(visibleColumns)\(suffix)]",
                nil,
                artifact.binding.kind == .waveform
                    ? waveformPreview(header: header, dataRows: Array(dataRows))
                    : nil
            )
        } catch {
            return (nil, error.localizedDescription, nil)
        }
    }

    private func waveformPreview(
        header: [String],
        dataRows: [[String]]
    ) -> RunReviewWaveformPreview? {
        guard let sweepColumn = header.first, header.count > 1 else {
            return nil
        }
        let sweepValues = dataRows.compactMap { row in
            numericValue(field(at: 0, in: row))
        }
        let signals = header.dropFirst().enumerated().compactMap { pair -> RunReviewWaveformSignalPreview? in
            let columnIndex = pair.offset + 1
            let values = dataRows.compactMap { row in
                numericValue(field(at: columnIndex, in: row))
            }
            let samples = dataRows.compactMap { row -> RunReviewWaveformSamplePreview? in
                guard let sweepValue = numericValue(field(at: 0, in: row)),
                      let signalValue = numericValue(field(at: columnIndex, in: row))
                else {
                    return nil
                }
                return RunReviewWaveformSamplePreview(
                    sweepValue: sweepValue,
                    signalValue: signalValue
                )
            }
            guard !values.isEmpty else {
                return nil
            }
            return RunReviewWaveformSignalPreview(
                name: pair.element,
                numericSampleCount: values.count,
                firstValue: values.first,
                lastValue: values.last,
                minValue: values.min(),
                maxValue: values.max(),
                samples: waveformDisplaySamples(samples)
            )
        }
        guard !signals.isEmpty else {
            return nil
        }
        return RunReviewWaveformPreview(
            sweepColumn: sweepColumn,
            sampleCount: dataRows.count,
            signalCount: signals.count,
            sweepStart: sweepValues.first,
            sweepEnd: sweepValues.last,
            signals: signals
        )
    }

    private func waveformDisplaySamples(
        _ samples: [RunReviewWaveformSamplePreview],
        limit: Int = 1024
    ) -> [RunReviewWaveformSamplePreview] {
        guard samples.count > limit, limit >= 4 else {
            return samples
        }
        let bucketCount = max(1, limit / 2)
        let bucketSize = Int(ceil(Double(samples.count) / Double(bucketCount)))
        var selected: [(index: Int, sample: RunReviewWaveformSamplePreview)] = []
        selected.reserveCapacity(limit + 2)

        for start in stride(from: 0, to: samples.count, by: bucketSize) {
            let end = min(start + bucketSize, samples.count)
            guard start < end else { continue }
            let indices = start..<end
            guard let minIndex = indices.min(by: {
                samples[$0].signalValue < samples[$1].signalValue
            }), let maxIndex = indices.max(by: {
                samples[$0].signalValue < samples[$1].signalValue
            }) else {
                continue
            }
            selected.append((minIndex, samples[minIndex]))
            if maxIndex != minIndex {
                selected.append((maxIndex, samples[maxIndex]))
            }
        }

        selected.append((0, samples[0]))
        selected.append((samples.count - 1, samples[samples.count - 1]))
        return Dictionary(selected.map { ($0.index, $0.sample) }, uniquingKeysWith: { first, _ in first })
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    private func jsonOutline(_ value: Any) -> String {
        if let object = value as? [String: Any] {
            let keys = object.keys.sorted()
            return "{\(keys.prefix(8).joined(separator: ", "))\(keys.count > 8 ? ", ..." : "")}"
        }
        if let array = value as? [Any] {
            return "[\(array.count) item(s)]"
        }
        return String(describing: value)
    }

    private func lineCount(_ text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private func csvRows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            if character == "\"" {
                if isQuoted, nextIndex < text.endIndex, text[nextIndex] == "\"" {
                    field.append(character)
                    index = text.index(after: nextIndex)
                    continue
                }
                isQuoted.toggle()
            } else if character == ",", !isQuoted {
                row.append(field)
                field.removeAll(keepingCapacity: true)
            } else if character == "\n", !isQuoted {
                row.append(field)
                rows.append(row)
                row.removeAll(keepingCapacity: true)
                field.removeAll(keepingCapacity: true)
            } else if character != "\r" || isQuoted {
                field.append(character)
            }
            index = nextIndex
        }

        guard !isQuoted else {
            throw RunReviewArtifactPreviewParseError.unclosedCSVQuote
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    private func field(at index: Int, in row: [String]) -> String? {
        guard index < row.count else {
            return nil
        }
        return row[index]
    }

    private func numericValue(_ field: String?) -> Double? {
        guard let field else {
            return nil
        }
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return Double(trimmed)
    }
}

private enum RunReviewArtifactPreviewParseError: Error, LocalizedError {
    case unclosedCSVQuote

    var errorDescription: String? {
        switch self {
        case .unclosedCSVQuote:
            "CSV preview contains an unclosed quoted field."
        }
    }
}
