import Foundation

public struct ExternalSignoffReportParser: Sendable {
    public enum Style: String, Sendable, Hashable, Codable {
        case generic
        case calibreLike
        case magicNetgenLike
        case klayoutLike
    }

    public let style: Style

    public init(style: Style = .generic) {
        self.style = style
    }

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
        if let diagnostic = styleSpecificDiagnostic(
            line: trimmed,
            severity: severity,
            fields: fields
        ) {
            return diagnostic
        }
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
        if style == .calibreLike && uppercased.contains("INCORRECT") {
            return .error
        }
        if style == .magicNetgenLike &&
            (uppercased.contains("DO NOT MATCH") || uppercased.contains("NOT EQUIVALENT")) {
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

    private func styleSpecificDiagnostic(
        line: String,
        severity: ExternalSignoffDiagnostic.Severity,
        fields: [String: String]
    ) -> ExternalSignoffDiagnostic? {
        switch style {
        case .generic:
            return nil
        case .calibreLike:
            return calibreDiagnostic(line: line, severity: severity, fields: fields)
        case .magicNetgenLike:
            return magicNetgenDiagnostic(line: line, severity: severity, fields: fields)
        case .klayoutLike:
            return klayoutDiagnostic(line: line, severity: severity, fields: fields)
        }
    }

    private func calibreDiagnostic(
        line: String,
        severity: ExternalSignoffDiagnostic.Severity,
        fields: [String: String]
    ) -> ExternalSignoffDiagnostic? {
        let uppercased = line.uppercased()
        if uppercased.contains("INCORRECT") && fields.isEmpty {
            return ExternalSignoffDiagnostic(
                severity: severity,
                message: strippedMessage(from: line),
                ruleID: "CALIBRE_SIGNOFF_INCORRECT",
                rawLine: line
            )
        }
        if let ruleID = fields["rule"] ?? fields["ruleID"] ?? fields["check"] {
            return ExternalSignoffDiagnostic(
                severity: severity,
                message: fields["message"] ?? strippedMessage(from: line),
                ruleID: ruleID,
                componentName: fields["component"] ?? fields["instance"],
                netName: fields["net"],
                rawLine: line
            )
        }
        return nil
    }

    private func magicNetgenDiagnostic(
        line: String,
        severity: ExternalSignoffDiagnostic.Severity,
        fields: [String: String]
    ) -> ExternalSignoffDiagnostic? {
        let uppercased = line.uppercased()
        if uppercased.contains("NETLISTS DO NOT MATCH") {
            return ExternalSignoffDiagnostic(
                severity: severity,
                message: strippedMessage(from: line),
                ruleID: "NETGEN_LVS_MISMATCH",
                componentName: fields["device"] ?? fields["instance"] ?? fields["component"],
                netName: fields["net"],
                rawLine: line
            )
        }
        if uppercased.contains("PROPERTY") && uppercased.contains("ERROR") {
            return ExternalSignoffDiagnostic(
                severity: severity,
                message: fields["message"] ?? strippedMessage(from: line),
                ruleID: "NETGEN_PROPERTY_MISMATCH",
                componentName: fields["device"] ?? fields["instance"] ?? fields["component"],
                netName: fields["net"],
                rawLine: line
            )
        }
        return nil
    }

    private func klayoutDiagnostic(
        line: String,
        severity: ExternalSignoffDiagnostic.Severity,
        fields: [String: String]
    ) -> ExternalSignoffDiagnostic? {
        let parts = line.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else {
            return nil
        }
        let severityToken = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard severityToken == "ERROR" || severityToken == "WARNING" || severityToken == "WARN" || severityToken == "INFO" else {
            return nil
        }
        let ruleID = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let message = parts.count == 3
            ? parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            : strippedMessage(from: line)
        return ExternalSignoffDiagnostic(
            severity: severity,
            message: fields["message"] ?? message,
            ruleID: ruleID.isEmpty ? nil : ruleID,
            componentName: fields["component"] ?? fields["instance"],
            netName: fields["net"],
            rawLine: line
        )
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
