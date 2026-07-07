import Foundation

public struct ExternalSignoffReportParser: Sendable {
    public enum Style: String, Sendable, Hashable, Codable {
        case generic
        case calibreLike
        case magicNetgenLike
        case klayoutLike
        /// Magic DRC output normalized by the `drc.tcl` driver. Only the
        /// driver's `VIOLATION`/`ERROR rule=...` lines are diagnostics; Magic's
        /// own chatter (e.g. "No errors found.") is ignored.
        case magicDRC
        /// Netgen LVS output normalized by the `lvs.tcl` driver. Only the
        /// driver's `MISMATCH`/`ERROR rule=...` lines are diagnostics; Netgen's
        /// own chatter (e.g. the "*** MISMATCH ***" count lines) is ignored.
        case netgenLVS
        /// Magic antennacheck output normalized by the `antenna.tcl` driver.
        /// Only the driver's `VIOLATION rule=antenna`/`ERROR rule=...` lines are
        /// diagnostics; the authoritative `ANTENNA_SUMMARY total=N` count gates
        /// the verdict the same way `DRC_SUMMARY` does.
        case magicAntenna
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
        var diagnostics = rawOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { parseDiagnostic(line: String($0)) }

        let completed = completionProof(kind: kind, in: rawOutput, diagnostics: &diagnostics)

        return ExternalSignoffToolReport(
            kind: kind,
            toolName: toolName,
            success: success,
            completed: completed,
            parserStyle: style,
            logPath: logPath,
            diagnostics: diagnostics
        )
    }

    /// Positive completion proof for the normalizing driver styles. A driver prints
    /// its terminal marker only after running to a clean end, so requiring it closes
    /// the false-pass vector where a tool exits 0 with empty/truncated output.
    ///
    /// - `.magicDRC`: requires `DRC_DONE`. Additionally honors the authoritative
    ///   count — if `DRC_SUMMARY total=N` reports N>0 but no `VIOLATION` line was
    ///   enumerated, an error diagnostic is synthesized so the count (not the
    ///   enumeration) gates the verdict.
    /// - `.netgenLVS`: requires the positive `LVS_RESULT status=match` marker; a
    ///   mismatch or a truncated run lacks it and cannot pass.
    /// - `.generic`: requires `SIGNOFF_RESULT status=...`.
    /// - `.calibreLike`: requires native Calibre result markers for DRC/LVS.
    /// - ambiguous compatibility styles fall back to the generic result marker
    ///   unless they can identify an explicit native success/failure marker.
    private func completionProof(
        kind: ExternalSignoffToolReport.Kind,
        in rawOutput: String,
        diagnostics: inout [ExternalSignoffDiagnostic]
    ) -> Bool {
        switch style {
        case .magicDRC:
            guard containsStandaloneMarker("DRC_DONE", in: rawOutput) else { return false }
            if let total = summaryTotal(prefix: "DRC_SUMMARY", in: rawOutput),
               total > 0,
               !diagnostics.contains(where: { $0.severity == .error }) {
                diagnostics.append(ExternalSignoffDiagnostic(
                    severity: .error,
                    message: "DRC_SUMMARY reported total=\(total) violations but none were enumerated",
                    ruleID: "DRC_SUMMARY_MISMATCH",
                    rawLine: "DRC_SUMMARY total=\(total)"
                ))
            }
            return true
        case .netgenLVS:
            return containsStatusMarker(prefix: "LVS_RESULT", status: "match", in: rawOutput)
        case .magicAntenna:
            guard containsStandaloneMarker("ANTENNA_DONE", in: rawOutput) else { return false }
            if let total = summaryTotal(prefix: "ANTENNA_SUMMARY", in: rawOutput),
               total > 0,
               !diagnostics.contains(where: { $0.severity == .error }) {
                diagnostics.append(ExternalSignoffDiagnostic(
                    severity: .error,
                    message: "ANTENNA_SUMMARY reported total=\(total) violations but none were enumerated",
                    ruleID: "ANTENNA_SUMMARY_MISMATCH",
                    rawLine: "ANTENNA_SUMMARY total=\(total)"
                ))
            }
            return true
        case .generic, .klayoutLike:
            return genericCompletionProof(in: rawOutput, diagnostics: &diagnostics)
        case .calibreLike:
            return calibreCompletionProof(kind: kind, in: rawOutput, diagnostics: &diagnostics)
        case .magicNetgenLike:
            return magicNetgenCompletionProof(kind: kind, in: rawOutput, diagnostics: &diagnostics)
        }
    }

    private func genericCompletionProof(
        in rawOutput: String,
        diagnostics: inout [ExternalSignoffDiagnostic]
    ) -> Bool {
        for line in rawOutput.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard firstToken(in: text) == "SIGNOFF_RESULT" else { continue }
            guard let status = keyValueFields(in: text)["status"]?.lowercased() else {
                diagnostics.append(genericResultDiagnostic(
                    message: "SIGNOFF_RESULT is missing a status field.",
                    rawLine: text
                ))
                return false
            }
            if isPassingStatus(status) {
                return true
            }
            if isFailingStatus(status) {
                diagnostics.append(genericResultDiagnostic(
                    message: "SIGNOFF_RESULT reported status=\(status).",
                    rawLine: text
                ))
                return true
            }
            diagnostics.append(genericResultDiagnostic(
                message: "SIGNOFF_RESULT reported unsupported status=\(status).",
                rawLine: text
            ))
            return false
        }
        return false
    }

    private func calibreCompletionProof(
        kind: ExternalSignoffToolReport.Kind,
        in rawOutput: String,
        diagnostics: inout [ExternalSignoffDiagnostic]
    ) -> Bool {
        switch kind {
        case .drc:
            guard let count = calibreDRCResultCount(in: rawOutput) else {
                return genericCompletionProof(in: rawOutput, diagnostics: &diagnostics)
            }
            if count > 0, !diagnostics.contains(where: { $0.severity == .error }) {
                diagnostics.append(ExternalSignoffDiagnostic(
                    severity: .error,
                    message: "Calibre DRC reported \(count) result(s).",
                    ruleID: "CALIBRE_DRC_RESULTS",
                    rawLine: "TOTAL DRC RESULTS GENERATED = \(count)"
                ))
            }
            return true
        case .lvs:
            let uppercased = rawOutput.uppercased()
            if uppercased.contains("LVS INCORRECT") {
                return true
            }
            if uppercased.contains("LVS") && uppercased.contains("CORRECT") {
                return true
            }
            return genericCompletionProof(in: rawOutput, diagnostics: &diagnostics)
        case .antenna, .density:
            return genericCompletionProof(in: rawOutput, diagnostics: &diagnostics)
        }
    }

    private func magicNetgenCompletionProof(
        kind: ExternalSignoffToolReport.Kind,
        in rawOutput: String,
        diagnostics: inout [ExternalSignoffDiagnostic]
    ) -> Bool {
        let uppercased = rawOutput.uppercased()
        if kind == .lvs {
            if uppercased.contains("NETLISTS MATCH") || uppercased.contains("CIRCUITS MATCH") {
                return true
            }
            if uppercased.contains("NETLISTS DO NOT MATCH")
                || uppercased.contains("DO NOT MATCH")
                || uppercased.contains("NOT EQUIVALENT") {
                return true
            }
        }
        return genericCompletionProof(in: rawOutput, diagnostics: &diagnostics)
    }

    private func genericResultDiagnostic(message: String, rawLine: String) -> ExternalSignoffDiagnostic {
        ExternalSignoffDiagnostic(
            severity: .error,
            message: message,
            ruleID: "SIGNOFF_RESULT",
            rawLine: rawLine
        )
    }

    private func isPassingStatus(_ status: String) -> Bool {
        ["pass", "passed", "clean", "match", "matched", "success", "ok"].contains(status)
    }

    private func isFailingStatus(_ status: String) -> Bool {
        ["fail", "failed", "error", "mismatch", "violation", "violations", "incorrect", "not_equivalent"].contains(status)
    }

    private func calibreDRCResultCount(in rawOutput: String) -> Int? {
        for line in rawOutput.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard text.uppercased().contains("TOTAL DRC RESULTS GENERATED") else { continue }
            let separator: Character = text.contains("=") ? "=" : ":"
            guard let value = text.split(separator: separator, maxSplits: 1).last else { return nil }
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    /// The authoritative violation count from a driver's `<PREFIX> total=<n>` summary
    /// line (`DRC_SUMMARY`, `ANTENNA_SUMMARY`), or nil when absent.
    private func summaryTotal(prefix: String, in rawOutput: String) -> Int? {
        for line in rawOutput.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard firstToken(in: text) == prefix else { continue }
            if let total = keyValueFields(in: text)["total"], let n = Int(total) {
                return n
            }
        }
        return nil
    }

    private func containsStandaloneMarker(_ marker: String, in rawOutput: String) -> Bool {
        rawOutput
            .split(whereSeparator: \.isNewline)
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == marker }
    }

    private func containsStatusMarker(prefix: String, status: String, in rawOutput: String) -> Bool {
        for line in rawOutput.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard firstToken(in: text) == prefix else { continue }
            guard keyValueFields(in: text)["status"] == status else { continue }
            return true
        }
        return false
    }

    private func firstToken(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmed.split(whereSeparator: isFieldSeparator).first else {
            return nil
        }
        return String(token)
    }

    private func parseDiagnostic(line: String) -> ExternalSignoffDiagnostic? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let severity = severity(in: trimmed) else {
            return nil
        }
        if style == .generic, firstToken(in: trimmed) == "SIGNOFF_RESULT" {
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
        // Styles that fully delegate to their style-specific handler must not
        // fall back to the permissive generic parse — it would misread incidental
        // tool chatter (e.g. Magic's "No errors found.") as a diagnostic.
        if style == .magicDRC || style == .netgenLVS || style == .magicAntenna {
            return nil
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
        case .magicDRC, .netgenLVS, .magicAntenna:
            return normalizedDriverDiagnostic(line: line, severity: severity, fields: fields)
        }
    }

    /// Parses a line emitted by one of the normalizing tool drivers (`drc.tcl`,
    /// `lvs.tcl`). Every diagnostic the drivers emit carries a `rule=` field
    /// (`VIOLATION rule=<code> ...`, `MISMATCH rule=LVS_MISMATCH ...`, or
    /// `ERROR rule=DRIVER ...`), so a line without a `rule` field is incidental
    /// tool output and is not a diagnostic.
    private func normalizedDriverDiagnostic(
        line: String,
        severity: ExternalSignoffDiagnostic.Severity,
        fields: [String: String]
    ) -> ExternalSignoffDiagnostic? {
        guard let ruleID = fields["rule"] else { return nil }
        return ExternalSignoffDiagnostic(
            severity: severity,
            message: fields["message"] ?? strippedMessage(from: line),
            ruleID: ruleID,
            componentName: fields["component"] ?? fields["instance"],
            netName: fields["net"],
            rawLine: line
        )
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
