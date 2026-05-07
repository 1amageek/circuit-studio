import Foundation

public struct ExternalSignoffReportParser: Sendable {
    public init() {}

    public func parse(
        kind: ExternalSignoffToolReport.Kind,
        toolName: String,
        logPath: String,
        rawOutput: String,
        success: Bool
    ) -> ExternalSignoffToolReport {
        let diagnostics = rawOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { parseDiagnostic(line: String($0)) }

        return ExternalSignoffToolReport(
            kind: kind,
            toolName: toolName,
            success: success,
            logPath: logPath,
            diagnostics: diagnostics
        )
    }

    private func parseDiagnostic(line: String) -> ExternalSignoffDiagnostic? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let severity = severity(in: trimmed) else {
            return nil
        }

        let fields = keyValueFields(in: trimmed)
        return ExternalSignoffDiagnostic(
            severity: severity,
            message: fields["message"] ?? strippedMessage(from: trimmed),
            ruleID: fields["rule"] ?? fields["ruleID"] ?? fields["check"],
            componentName: fields["component"] ?? fields["instance"],
            netName: fields["net"],
            rawLine: trimmed
        )
    }

    private func severity(in line: String) -> ExternalSignoffDiagnostic.Severity? {
        let uppercased = line.uppercased()
        if uppercased.contains("ERROR")
            || uppercased.contains("FAIL")
            || uppercased.contains("VIOLATION")
            || uppercased.contains("MISMATCH") {
            return .error
        }
        if uppercased.contains("WARN") {
            return .warning
        }
        if uppercased.contains("INFO") {
            return .info
        }
        return nil
    }

    private func keyValueFields(in line: String) -> [String: String] {
        var result: [String: String] = [:]
        var index = line.startIndex
        while index < line.endIndex {
            while index < line.endIndex, isFieldSeparator(line[index]) {
                index = line.index(after: index)
            }
            let keyStart = index
            while index < line.endIndex, line[index] != "=", !isFieldSeparator(line[index]) {
                index = line.index(after: index)
            }
            guard index < line.endIndex, line[index] == "=" else {
                while index < line.endIndex, !isFieldSeparator(line[index]) {
                    index = line.index(after: index)
                }
                continue
            }
            let key = String(line[keyStart..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
            index = line.index(after: index)

            let value: String
            if index < line.endIndex && (line[index] == "\"" || line[index] == "'") {
                let quote = line[index]
                index = line.index(after: index)
                let valueStart = index
                while index < line.endIndex, line[index] != quote {
                    index = line.index(after: index)
                }
                value = String(line[valueStart..<index])
                if index < line.endIndex {
                    index = line.index(after: index)
                }
            } else {
                let valueStart = index
                while index < line.endIndex, !isFieldSeparator(line[index]) {
                    index = line.index(after: index)
                }
                value = String(line[valueStart..<index])
            }

            guard !key.isEmpty, !value.isEmpty else { continue }
            result[key] = value
        }
        return result
    }

    private func isFieldSeparator(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "," || character == ";"
    }

    private func strippedMessage(from line: String) -> String {
        var result = line
        for prefix in ["[ERROR]", "[WARNING]", "[WARN]", "[INFO]", "ERROR:", "WARNING:", "WARN:", "INFO:"] {
            if result.uppercased().hasPrefix(prefix) {
                result.removeFirst(prefix.count)
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
