import Foundation

/// Detects when a netlist requires an external simulator (e.g. OSDI/Verilog-A models).
public struct ExternalModelDetector: Sendable {
    private static let advancedModelTokens = [
        "bsimcmg",
        "bsim-cmg",
        "bsimimg",
        "bsim-img",
    ]

    public init() {}

    public func requiresExternalSimulation(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?
    ) -> Bool {
        let includePaths = processConfiguration?.effectiveIncludePaths() ?? []
        let lines = source.split(whereSeparator: \.isNewline).map { String($0) }

        var includePathsToScan: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("*") || trimmed.hasPrefix(";") {
                continue
            }

            let lower = trimmed.lowercased()
            if lower.hasPrefix(".pre_osdi") {
                return true
            }

            if lower.hasPrefix(".model") {
                if modelLineRequiresExternal(trimmed) {
                    return true
                }
            }

            if lower.hasPrefix(".include") || lower.hasPrefix(".lib") {
                if let include = parseIncludeDirective(from: trimmed) {
                    includePathsToScan.append(include.path)
                    if include.path.lowercased().hasSuffix(".osdi")
                        || include.path.lowercased().hasSuffix(".va") {
                        return true
                    }
                }
            }
        }

        if includePathsToScan.isEmpty {
            return false
        }

        for rawPath in includePathsToScan {
            guard let resolved = resolvePath(
                rawPath,
                fileName: fileName,
                includePaths: includePaths
            ) else {
                // Conservative: unknown include -> route to external
                return true
            }

            if fileContainsAdvancedModels(resolved) {
                return true
            }
        }

        return false
    }

    private func modelLineRequiresExternal(_ line: String) -> Bool {
        let tokens = tokenize(line)
        guard tokens.count >= 3 else { return false }

        let modelType = tokens[2].lowercased()
        if Self.advancedModelTokens.contains(where: { modelType.contains($0) }) {
            return true
        }

        if modelType == "nmos" || modelType == "pmos" {
            if let level = extractLevel(from: tokens), level >= 70 {
                return true
            }
        }

        return false
    }

    private func parseIncludeDirective(from line: String) -> (path: String, section: String?)? {
        let lower = line.lowercased()
        guard lower.hasPrefix(".include") || lower.hasPrefix(".lib") else { return nil }

        let tokens = tokenizePreservingQuotes(line)
        guard tokens.count >= 2 else { return nil }

        let pathToken = tokens[1]
        let section = tokens.count >= 3 ? tokens[2] : nil
        return (path: pathToken, section: section)
    }

    private func resolvePath(
        _ rawPath: String,
        fileName: String?,
        includePaths: [String]
    ) -> URL? {
        let unquoted = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let candidate = URL(fileURLWithPath: unquoted)
        if unquoted.hasPrefix("/"), FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        if let fileName {
            let base = URL(fileURLWithPath: fileName).deletingLastPathComponent()
            let resolved = base.appendingPathComponent(unquoted)
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }

        for path in includePaths {
            let base = URL(fileURLWithPath: path)
            let resolved = base.appendingPathComponent(unquoted)
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resolved = cwd.appendingPathComponent(unquoted)
        if FileManager.default.fileExists(atPath: resolved.path) {
            return resolved
        }

        return nil
    }

    private func fileContainsAdvancedModels(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        let maxBytes = 5 * 1024 * 1024
        let data = try? handle.read(upToCount: maxBytes)
        guard let data, let text = String(data: data, encoding: .utf8) else { return false }

        let lower = text.lowercased()
        if Self.advancedModelTokens.contains(where: { lower.contains($0) }) {
            return true
        }

        if lower.contains("level=72") || lower.contains("level=107") {
            return true
        }

        return false
    }

    private func tokenize(_ line: String) -> [String] {
        line.split { $0.isWhitespace || $0 == "(" || $0 == ")" }
            .map { String($0) }
    }

    private func tokenizePreservingQuotes(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes: Character?

        for char in line {
            if let q = inQuotes {
                if char == q {
                    inQuotes = nil
                    tokens.append(current)
                    current = ""
                } else {
                    current.append(char)
                }
                continue
            }

            if char == "\"" || char == "'" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                inQuotes = char
                continue
            }

            if char.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    private func extractLevel(from tokens: [String]) -> Double? {
        for (index, token) in tokens.enumerated() {
            let lower = token.lowercased()
            if lower.hasPrefix("level=") {
                let value = lower.replacingOccurrences(of: "level=", with: "")
                return Double(value)
            }
            if lower == "level", index + 1 < tokens.count {
                return Double(tokens[index + 1])
            }
        }
        return nil
    }
}
