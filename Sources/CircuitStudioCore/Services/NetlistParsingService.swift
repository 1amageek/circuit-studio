import Foundation
import CoreSpiceIO

/// Parses SPICE source into a UI-friendly ``NetlistInfo``.
///
/// Uses `SPICEIO.parse()` (parse-only, no lowering/compilation) for
/// lightweight, fast feedback suitable for live editing.
public final class NetlistParsingService: Sendable {

    public init() {}

    /// Parse SPICE source and return a UI-facing summary.
    public func parse(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration? = nil
    ) async -> NetlistInfo {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NetlistInfo(
                title: nil, components: [], nodes: [],
                analyses: [], models: [], diagnostics: [],
                hasErrors: false
            )
        }

        let result = await parseNetlist(
            source: source,
            fileName: fileName,
            processConfiguration: processConfiguration
        )

        let diagnostics = result.diagnostics.map { d in
            NetlistDiagnostic(
                severity: mapSeverity(d.severity),
                message: d.message,
                line: d.location?.line
            )
        }

        guard let netlist = result.netlist else {
            return NetlistInfo(
                title: nil, components: [], nodes: [],
                analyses: [], models: [], diagnostics: diagnostics,
                hasErrors: true
            )
        }

        let components = netlist.components.map { c in
            ComponentSummary(
                name: c.name,
                type: c.type.rawValue,
                nodes: c.nodes.map(\.name),
                modelName: c.modelName,
                primaryValue: Self.extractPrimaryValue(c)
            )
        }

        var nodeSet = Set<String>()
        for c in netlist.components {
            for n in c.nodes where !n.isGround {
                nodeSet.insert(n.name)
            }
        }
        let nodes = nodeSet.sorted()

        let analyses = netlist.analyses.map { Self.formatAnalysis($0) }

        let models = netlist.models.map { m in
            ModelSummary(
                name: m.name,
                type: m.type.rawValue,
                parameterCount: m.parameters.count
            )
        }

        return NetlistInfo(
            title: netlist.title,
            components: components,
            nodes: nodes,
            analyses: analyses,
            models: models,
            diagnostics: diagnostics,
            hasErrors: result.hasErrors
        )
    }

    private func parseNetlist(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?
    ) async -> ParseResult {
        var parserConfig = ParserConfiguration.default
        let includePaths = processConfiguration?.effectiveIncludePaths() ?? []
        let hasLibraries = (processConfiguration?.technology?.libraries.contains { $0.isEnabled }) == true
        let resolveIncludes = processConfiguration?.resolveIncludes == true
            || hasLibraries
            || !includePaths.isEmpty

        parserConfig.resolveIncludes = resolveIncludes
        parserConfig.includePaths = includePaths
        if let processConfiguration {
            parserConfig.defaultTemperature = processConfiguration.effectiveTemperature(
                defaultValue: parserConfig.defaultTemperature
            )
        }

        let resolver = LocalFileResolver(
            searchPaths: parserConfig.includePaths,
            maxDepth: parserConfig.maxIncludeDepth
        )
        let parser = SPICEParser()
        return await parser.parse(
            source: source,
            fileName: fileName,
            configuration: parserConfig,
            fileResolver: resolver
        )
    }

    // MARK: - Private Helpers

    private func mapSeverity(_ severity: DiagnosticSeverity) -> NetlistDiagnostic.Severity {
        switch severity {
        case .error: return .error
        case .warning: return .warning
        case .info: return .info
        case .hint: return .hint
        }
    }

    private static func extractPrimaryValue(_ component: ParsedComponent) -> String? {
        let key: String?
        switch component.type {
        case .resistor: key = "r"
        case .capacitor: key = "c"
        case .inductor: key = "l"
        case .voltageSource: key = "v"
        case .currentSource: key = "i"
        case .vcvs: key = "e"
        case .vccs: key = "g"
        case .cccs: key = "f"
        case .ccvs: key = "h"
        default: key = nil
        }

        guard let key else { return nil }

        if let value = component.parameters[key] {
            return formatParameterValue(value)
        }

        // Try case-insensitive lookup
        for (k, v) in component.parameters {
            if k.lowercased() == key {
                return formatParameterValue(v)
            }
        }

        return nil
    }

    private static func formatParameterValue(_ value: ParsedParameterValue) -> String {
        switch value {
        case .numeric(let n):
            return formatEngineering(n)
        case .string(let s):
            return s
        case .expression(let expr):
            return "{\(expr)}"
        case .boolean(let b):
            return b ? "true" : "false"
        }
    }

    private static func formatEngineering(_ value: Double) -> String {
        let absVal = abs(value)
        let sign = value < 0 ? "-" : ""

        if absVal == 0 { return "0" }

        let prefixes: [(threshold: Double, suffix: String)] = [
            (1e15, "P"),
            (1e12, "T"),
            (1e9, "G"),
            (1e6, "M"),
            (1e3, "k"),
            (1, ""),
            (1e-3, "m"),
            (1e-6, "u"),
            (1e-9, "n"),
            (1e-12, "p"),
            (1e-15, "f"),
        ]

        for (threshold, suffix) in prefixes {
            if absVal >= threshold {
                let scaled = absVal / threshold
                if scaled == scaled.rounded() && scaled < 10000 {
                    return "\(sign)\(Int(scaled))\(suffix)"
                }
                return "\(sign)\(String(format: "%.3g", scaled))\(suffix)"
            }
        }

        return String(format: "%g", value)
    }

    private static func formatAnalysis(_ cmd: ParsedAnalysisCommand) -> AnalysisSummary {
        switch cmd {
        case .op:
            return AnalysisSummary(label: ".op", type: "OP")

        case .dc(let spec):
            return AnalysisSummary(
                label: ".dc \(spec.source) \(spec.startValue) \(spec.stopValue) \(spec.stepValue)",
                type: "DC"
            )

        case .ac(let spec):
            return AnalysisSummary(
                label: ".ac \(spec.scaleType.rawValue) \(spec.numberOfPoints) \(spec.startFrequency) \(spec.stopFrequency)",
                type: "AC"
            )

        case .transient(let spec):
            var label = ".tran"
            if let step = spec.stepTime { label += " \(step)" }
            label += " \(spec.stopTime)"
            return AnalysisSummary(label: label, type: "Tran")

        case .noise(let spec):
            return AnalysisSummary(
                label: ".noise V(\(spec.outputNode)) \(spec.inputSource)",
                type: "Noise"
            )

        case .transferFunction(let spec):
            return AnalysisSummary(
                label: ".tf \(spec.output) \(spec.input)",
                type: "TF"
            )

        case .sensitivity(let spec):
            return AnalysisSummary(
                label: ".sens \(spec.output)",
                type: "Sens"
            )

        case .monteCarlo(let spec):
            return AnalysisSummary(
                label: ".mc \(spec.iterations)",
                type: "MC"
            )

        case .poleZero(let spec):
            return AnalysisSummary(
                label: ".pz \(spec.inputNode) \(spec.outputNode)",
                type: "PZ"
            )

        case .fourier(let spec):
            return AnalysisSummary(
                label: ".four \(spec.frequency)",
                type: "Fourier"
            )
        }
    }
}
