import Foundation
import PEXEngine

public struct PostLayoutSimulationService: Sendable {
    public init() {}

    public func buildPostLayoutNetlist(
        baseNetlist: String,
        parasitics: PEXParasiticIR,
        title: String = "Post-layout simulation"
    ) -> String {
        var lines: [String] = []
        lines.append("* \(title)")
        lines.append("* PEX corner: \(parasitics.cornerID)")
        lines.append("")

        let baseLines = baseNetlist
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        for line in baseLines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == ".end" {
                continue
            }
            lines.append(line)
        }

        lines.append("")
        lines.append("* --- Extracted parasitics ---")
        lines.append(contentsOf: renderParasitics(parasitics.elements))
        lines.append("")
        lines.append(".end")
        return lines.joined(separator: "\n")
    }

    public func runPostLayoutAnalysis(
        baseNetlist: String,
        parasitics: PEXParasiticIR,
        command: AnalysisCommand,
        processConfiguration: ProcessConfiguration? = nil,
        simulationService: SimulationService = SimulationService()
    ) async throws -> SimulationResult {
        let netlist = buildPostLayoutNetlist(baseNetlist: baseNetlist, parasitics: parasitics)
        return try await simulationService.runAnalysis(
            source: netlist,
            fileName: "post_pex.cir",
            processConfiguration: processConfiguration,
            command: command
        )
    }

    /// Builds a hierarchy-aware deck from the canonical PEX artifact. The
    /// existing `PEXParasiticIR` overload remains available for legacy flat
    /// callers; this overload preserves the source `.subckt` boundary and
    /// validates generated ports before simulation.
    public func buildHierarchicalPostLayoutNetlist(
        baseNetlist: String,
        canonicalIR: ParasiticIR,
        topCell: String? = nil
    ) throws -> String {
        try PEXSPICEBackannotationComposer(
            options: PEXSPICEBackannotationOptions(topCell: topCell)
        ).compose(sourceNetlist: baseNetlist, ir: canonicalIR)
    }

    public func runHierarchicalPostLayoutAnalysis(
        baseNetlist: String,
        canonicalIR: ParasiticIR,
        topCell: String? = nil,
        command: AnalysisCommand,
        processConfiguration: ProcessConfiguration? = nil,
        simulationService: SimulationService = SimulationService()
    ) async throws -> SimulationResult {
        let netlist = try buildHierarchicalPostLayoutNetlist(
            baseNetlist: baseNetlist,
            canonicalIR: canonicalIR,
            topCell: topCell
        )
        return try await simulationService.runAnalysis(
            source: netlist,
            fileName: "post_pex.cir",
            processConfiguration: processConfiguration,
            command: command
        )
    }

    private func renderParasitics(_ elements: [PEXParasiticElement]) -> [String] {
        elements.enumerated().compactMap { index, element in
            guard element.value > 0 else { return nil }
            let id = sanitizeIdentifier(element.id, fallback: "\(index)")
            let nodeA = sanitizeNode(element.nodeA)
            let nodeB = sanitizeNode(element.nodeB ?? "0")

            switch element.kind {
            case .resistor:
                guard element.nodeB != nil else { return nil }
                return "RPEX_\(id) \(nodeA) \(nodeB) \(formatValue(element.value))"
            case .capacitor:
                return "CPEX_\(id) \(nodeA) \(nodeB) \(formatValue(element.value))"
            case .coupling:
                guard element.nodeB != nil else { return nil }
                return "CPEX_\(id) \(nodeA) \(nodeB) \(formatValue(element.value))"
            case .inductor:
                guard element.nodeB != nil else { return nil }
                return "LPEX_\(id) \(nodeA) \(nodeB) \(formatValue(element.value))"
            }
        }
    }

    private func sanitizeIdentifier(_ raw: String, fallback: String) -> String {
        let filtered = raw.map { character -> Character in
            if character.isLetter || character.isNumber || character == "_" {
                return character
            }
            return "_"
        }
        let value = String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return value.isEmpty ? fallback : value
    }

    private func sanitizeNode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "0" }
        if trimmed == "gnd" || trimmed == "GND" {
            return "0"
        }
        let mapped = trimmed.map { character -> Character in
            if character.isLetter || character.isNumber || character == "_" {
                return character
            }
            return "_"
        }
        return String(mapped)
    }

    private func formatValue(_ value: Double) -> String {
        String(format: "%.12g", value)
    }
}
