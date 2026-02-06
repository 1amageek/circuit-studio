import Foundation

/// Prepares a SPICE netlist for external simulation (ngspice + OSDI/OpenVAF).
public struct ExternalSpicePreprocessor: Sendable {
    public struct PreparedNetlist: Sendable {
        public let netlistURL: URL
        public let rawURL: URL
        public let workingDirectory: URL
        public let analysis: AnalysisCommand?
    }

    public init() {}

    public func prepare(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?,
        command: AnalysisCommand?
    ) throws -> PreparedNetlist {
        let includePaths = processConfiguration?.effectiveIncludePaths() ?? []
        let fileBaseURL = fileName.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }

        var osdiLibraries: [URL] = []
        var verilogaLibraries: [URL] = []
        var processedLines: [String] = []
        var lines = source.split(whereSeparator: \.isNewline).map { String($0) }
        processedLines.reserveCapacity(lines.count)

        if let extracted = extractPreOsdiPaths(from: lines, baseURL: fileBaseURL, includePaths: includePaths) {
            osdiLibraries.append(contentsOf: extracted)
        }

        let verilogAModels = collectVerilogAModelNames(from: lines)

        lines = stripControlSections(lines)
        lines = stripEnd(lines)

        let analysisCommand = command
        if analysisCommand != nil {
            lines = stripAnalysisCommands(lines)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if lower.hasPrefix(".include") || lower.hasPrefix(".lib") {
                guard let directive = parseIncludeDirective(from: trimmed) else {
                    processedLines.append(line)
                    continue
                }

                let resolved = resolveIncludePath(
                    directive.path,
                    baseURL: fileBaseURL,
                    includePaths: includePaths
                )

                let rawPath = directive.path
                let lowerPath = rawPath.lowercased()
                if lowerPath.hasSuffix(".osdi"), let resolved {
                    osdiLibraries.append(resolved)
                    continue
                }
                if lowerPath.hasSuffix(".va"), let resolved {
                    verilogaLibraries.append(resolved)
                    continue
                }

                if let resolved {
                    processedLines.append(rewriteInclude(
                        directive: directive,
                        resolvedPath: resolved.path
                    ))
                } else {
                    processedLines.append(line)
                }
                continue
            }

            processedLines.append(rewriteVerilogAInstance(line, modelNames: verilogAModels))
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("circuit-studio-ngspice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var compiledOSDI: [URL] = []
        if !verilogaLibraries.isEmpty {
            compiledOSDI = try compileVerilogA(
                sources: verilogaLibraries,
                outputDirectory: tempDir
            )
        }

        let allOSDI = osdiLibraries + compiledOSDI

        if let analysisCommand {
            processedLines.append(analysisLine(for: analysisCommand))
        } else if !containsAnalysis(lines: processedLines) {
            processedLines.append(".op")
        }

        let netlistURL = tempDir.appendingPathComponent("netlist.cir")
        let rawURL = tempDir.appendingPathComponent("output.raw")

        let controlBlock = buildControlBlock(
            rawURL: rawURL,
            osdiLibraries: allOSDI
        )

        let finalNetlist = ([
            "* External simulation netlist",
        ] + processedLines + controlBlock + [".end"]).joined(separator: "\n")

        try finalNetlist.write(to: netlistURL, atomically: true, encoding: .utf8)

        return PreparedNetlist(
            netlistURL: netlistURL,
            rawURL: rawURL,
            workingDirectory: fileBaseURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            analysis: analysisCommand
        )
    }

    private func stripControlSections(_ lines: [String]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(lines.count)
        var inControl = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.hasPrefix(".control") {
                inControl = true
                continue
            }
            if trimmed.hasPrefix(".endc") {
                inControl = false
                continue
            }
            if !inControl {
                result.append(line)
            }
        }

        return result
    }

    private func stripEnd(_ lines: [String]) -> [String] {
        lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed == ".end" { return false }
            if trimmed.hasPrefix(".end ") { return false }
            return true
        }
    }

    private func stripAnalysisCommands(_ lines: [String]) -> [String] {
        lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard trimmed.hasPrefix(".") else { return true }
            if trimmed.hasPrefix(".op") { return false }
            if trimmed.hasPrefix(".tran") { return false }
            if trimmed.hasPrefix(".ac") { return false }
            if trimmed.hasPrefix(".dc") { return false }
            if trimmed.hasPrefix(".noise") { return false }
            if trimmed.hasPrefix(".tf") { return false }
            if trimmed.hasPrefix(".pz") { return false }
            return true
        }
    }

    private func containsAnalysis(lines: [String]) -> Bool {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.hasPrefix(".op")
                || trimmed.hasPrefix(".tran")
                || trimmed.hasPrefix(".ac")
                || trimmed.hasPrefix(".dc")
                || trimmed.hasPrefix(".noise")
                || trimmed.hasPrefix(".tf")
                || trimmed.hasPrefix(".pz") {
                return true
            }
        }
        return false
    }

    private func extractPreOsdiPaths(
        from lines: [String],
        baseURL: URL?,
        includePaths: [String]
    ) -> [URL]? {
        var results: [URL] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            guard lower.hasPrefix(".pre_osdi") else { continue }
            let tokens = tokenizePreservingQuotes(trimmed)
            guard tokens.count >= 2 else { continue }
            let path = tokens[1]
            if let resolved = resolveIncludePath(path, baseURL: baseURL, includePaths: includePaths) {
                results.append(resolved)
            }
        }
        return results.isEmpty ? nil : results
    }

    private func collectVerilogAModelNames(from lines: [String]) -> Set<String> {
        let builtInModelTypes: Set<String> = [
            "d", "npn", "pnp", "nmos", "pmos",
            "njf", "pjf", "nmf", "pmf",
            "ltra", "sw", "csw",
        ]

        var names: Set<String> = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            guard lower.hasPrefix(".model") else { continue }
            let tokens = tokenizePreservingQuotes(trimmed)
            guard tokens.count >= 3 else { continue }
            let modelName = tokens[1]
            let modelType = tokens[2].lowercased()
            if !builtInModelTypes.contains(modelType) {
                names.insert(modelName)
            }
        }
        return names
    }

    private func rewriteVerilogAInstance(_ line: String, modelNames: Set<String>) -> String {
        guard !modelNames.isEmpty else { return line }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("*") || trimmed.hasPrefix(";") || trimmed.hasPrefix(".") {
            return line
        }
        guard let firstChar = trimmed.first, firstChar == "M" || firstChar == "m" else {
            return line
        }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map { String($0) }
        guard tokens.count >= 2 else { return line }

        let modelTokenIndex = tokens.lastIndex { !$0.contains("=") } ?? -1
        guard modelTokenIndex > 0, modelTokenIndex < tokens.count else { return line }
        let modelName = tokens[modelTokenIndex]

        guard modelNames.contains(modelName) else { return line }

        var newTokens = tokens
        let instance = newTokens[0]
        let suffix = instance.dropFirst()
        newTokens[0] = "N" + suffix
        return newTokens.joined(separator: " ")
    }

    private func parseIncludeDirective(from line: String) -> (kind: String, path: String, section: String?)? {
        let tokens = tokenizePreservingQuotes(line)
        guard tokens.count >= 2 else { return nil }
        let kind = tokens[0]
        let path = tokens[1]
        let section = tokens.count >= 3 ? tokens[2] : nil
        return (kind: kind, path: path, section: section)
    }

    private func resolveIncludePath(
        _ rawPath: String,
        baseURL: URL?,
        includePaths: [String]
    ) -> URL? {
        let unquoted = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let candidate = URL(fileURLWithPath: unquoted)
        if unquoted.hasPrefix("/"), FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        if let baseURL {
            let resolved = baseURL.appendingPathComponent(unquoted)
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }

        for path in includePaths {
            let resolved = URL(fileURLWithPath: path).appendingPathComponent(unquoted)
            if FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }

        return nil
    }

    private func rewriteInclude(directive: (kind: String, path: String, section: String?), resolvedPath: String) -> String {
        if directive.kind.lowercased() == ".lib", let section = directive.section {
            return ".lib \"\(resolvedPath)\" \(section)"
        }
        return ".include \"\(resolvedPath)\""
    }

    private func compileVerilogA(sources: [URL], outputDirectory: URL) throws -> [URL] {
        var outputs: [URL] = []
        outputs.reserveCapacity(sources.count)

        let openvafPath = ProcessInfo.processInfo.environment["OPENVAF_BIN"] ?? "openvaf"

        for source in sources {
            let dest = outputDirectory.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: openvafPath)
            process.currentDirectoryURL = outputDirectory
            process.arguments = [dest.lastPathComponent]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                throw StudioError.simulationFailure("OpenVAF not found or failed to launch: \(error.localizedDescription)")
            }
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                throw StudioError.simulationFailure("OpenVAF failed: \(output)")
            }

            let osdiName = dest.deletingPathExtension().lastPathComponent + ".osdi"
            let osdiURL = outputDirectory.appendingPathComponent(osdiName)
            guard FileManager.default.fileExists(atPath: osdiURL.path) else {
                throw StudioError.simulationFailure("OpenVAF did not produce \(osdiName)")
            }
            outputs.append(osdiURL)
        }

        return outputs
    }

    private func buildControlBlock(rawURL: URL, osdiLibraries: [URL]) -> [String] {
        var lines: [String] = []
        lines.append(".control")
        lines.append("set filetype=ascii")
        lines.append("set noaskquit")
        for library in osdiLibraries {
            lines.append("pre_osdi \"\(library.path)\"")
        }
        lines.append("run")
        lines.append("write \"\(rawURL.path)\"")
        lines.append("quit")
        lines.append(".endc")
        return lines
    }

    private func analysisLine(for command: AnalysisCommand) -> String {
        switch command {
        case .op:
            return ".op"
        case .tran(let spec):
            let step = spec.stepTime ?? spec.stopTime / 100.0
            if let start = spec.startTime, let maxStep = spec.maxStep {
                return ".tran \(formatEngineering(step)) \(formatEngineering(spec.stopTime)) \(formatEngineering(start)) \(formatEngineering(maxStep))"
            } else if let start = spec.startTime {
                return ".tran \(formatEngineering(step)) \(formatEngineering(spec.stopTime)) \(formatEngineering(start))"
            } else {
                return ".tran \(formatEngineering(step)) \(formatEngineering(spec.stopTime))"
            }
        case .ac(let spec):
            let scaleStr: String
            switch spec.scaleType {
            case .decade: scaleStr = "dec"
            case .octave: scaleStr = "oct"
            case .linear: scaleStr = "lin"
            }
            return ".ac \(scaleStr) \(spec.numberOfPoints) \(formatEngineering(spec.startFrequency)) \(formatEngineering(spec.stopFrequency))"
        case .dcSweep(let spec):
            return ".dc \(spec.source) \(formatValue(spec.startValue)) \(formatValue(spec.stopValue)) \(formatValue(spec.stepValue))"
        case .noise(let spec):
            let scaleStr: String
            switch spec.scaleType {
            case .decade: scaleStr = "dec"
            case .octave: scaleStr = "oct"
            case .linear: scaleStr = "lin"
            }
            let out = spec.referenceNode.map { "v(\(spec.outputNode),\($0))" } ?? "v(\(spec.outputNode))"
            return ".noise \(out) \(spec.inputSource) \(scaleStr) \(spec.numberOfPoints) \(formatEngineering(spec.startFrequency)) \(formatEngineering(spec.stopFrequency))"
        case .tf(let spec):
            return ".tf \(spec.output) \(spec.input)"
        case .pz(let spec):
            return ".pz \(spec.inputNode) \(spec.inputReference) \(spec.outputNode) \(spec.outputReference) vol pz"
        }
    }

    private func formatValue(_ value: Double) -> String {
        if value == Double(Int(value)) && abs(value) < 1e9 {
            return "\(Int(value))"
        }
        return "\(value)"
    }

    private func formatEngineering(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue == 0 { return "0" }
        if absValue >= 1e12 { return String(format: "%.4gT", value / 1e12) }
        if absValue >= 1e9 { return String(format: "%.4gG", value / 1e9) }
        if absValue >= 1e6 { return String(format: "%.4gMeg", value / 1e6) }
        if absValue >= 1e3 { return String(format: "%.4gk", value / 1e3) }
        if absValue >= 1 { return String(format: "%.4g", value) }
        if absValue >= 1e-3 { return String(format: "%.4gm", value * 1e3) }
        if absValue >= 1e-6 { return String(format: "%.4gu", value * 1e6) }
        if absValue >= 1e-9 { return String(format: "%.4gn", value * 1e9) }
        if absValue >= 1e-12 { return String(format: "%.4gp", value * 1e12) }
        return String(format: "%.4gf", value * 1e15)
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
}
