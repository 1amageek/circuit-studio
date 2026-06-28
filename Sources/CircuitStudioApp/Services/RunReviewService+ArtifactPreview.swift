import DesignFlowKernel
import Foundation

extension RunReviewService {
    public func loadArtifactPreview(
        runID: String,
        artifactPath: String,
        projectRoot: URL,
        maxBytes: Int = 4096
    ) throws -> RunReviewArtifactPreview {
        guard maxBytes > 0 else {
            throw RunReviewServiceError.artifactPreviewInvalidLimit(limit: maxBytes)
        }
        let bundle = try reviewBundler.makeReviewBundle(runID: runID, projectRoot: projectRoot)
        guard let artifact = bundle.artifacts.first(where: { $0.path == artifactPath }) else {
            throw RunReviewServiceError.artifactPreviewNotFound(
                runID: runID,
                artifactPath: artifactPath
            )
        }
        let url = try previewURL(for: artifact, projectRoot: projectRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw RunReviewServiceError.artifactPreviewInputMissing(path: artifact.path)
        }
        let result = try previewData(
            at: url,
            artifactPath: artifact.path,
            maxBytes: maxBytes
        )
        let text = String(data: result.data, encoding: .utf8)
        let structured = structuredPreview(
            data: result.data,
            artifact: artifact,
            truncated: result.truncated
        )
        return RunReviewArtifactPreview(
            artifact: artifact,
            resolvedPath: url.path(percentEncoded: false),
            byteCount: artifact.byteCount,
            previewByteCount: result.data.count,
            truncated: result.truncated,
            isText: text != nil,
            text: text ?? "",
            lineCount: text.map(lineCount) ?? 0,
            structuredPreview: structured.preview,
            parseIssue: structured.issue,
            waveformPreview: structured.waveform
        )
    }

    private func previewURL(
        for artifact: FlowRunReviewArtifact,
        projectRoot: URL
    ) throws -> URL {
        let rootPath = (projectRoot.path(percentEncoded: false) as NSString).standardizingPath
        let artifactPath = if artifact.path.hasPrefix("/") {
            (artifact.path as NSString).standardizingPath
        } else {
            ((rootPath as NSString).appendingPathComponent(artifact.path) as NSString).standardizingPath
        }
        let canonicalRootPath = URL(filePath: rootPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path(percentEncoded: false)
        let canonicalArtifactPath = URL(filePath: artifactPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path(percentEncoded: false)
        guard isContained(path: canonicalArtifactPath, byRootPath: canonicalRootPath) else {
            throw RunReviewServiceError.artifactPreviewEscapesProject(path: artifact.path)
        }
        return URL(filePath: artifactPath)
    }

    private func isContained(path: String, byRootPath rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func previewData(
        at url: URL,
        artifactPath: String,
        maxBytes: Int
    ) throws -> (data: Data, truncated: Bool) {
        let readLimit = maxBytes + 1
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw RunReviewServiceError.artifactPreviewUnreadable(
                path: artifactPath,
                message: error.localizedDescription
            )
        }

        let readResult: Result<Data, Error>
        do {
            readResult = .success(try handle.read(upToCount: readLimit) ?? Data())
        } catch {
            readResult = .failure(error)
        }

        do {
            try handle.close()
        } catch {
            throw RunReviewServiceError.artifactPreviewUnreadable(
                path: artifactPath,
                message: error.localizedDescription
            )
        }

        switch readResult {
        case .success(let data):
            if data.count > maxBytes {
                return (Data(data.prefix(maxBytes)), true)
            }
            return (data, false)
        case .failure(let error):
            throw RunReviewServiceError.artifactPreviewUnreadable(
                path: artifactPath,
                message: error.localizedDescription
            )
        }
    }

    private func structuredPreview(
        data: Data,
        artifact: FlowRunReviewArtifact,
        truncated: Bool
    ) -> (preview: String?, issue: String?, waveform: RunReviewWaveformPreview?) {
        if artifact.format == .json {
            let preview = jsonStructuredPreview(data: data, truncated: truncated)
            return (preview.preview, preview.issue, nil)
        }
        if artifact.format == .csv || artifact.kind == .waveform {
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
                artifact.kind == .waveform
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
                samples: Array(samples.prefix(256))
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
