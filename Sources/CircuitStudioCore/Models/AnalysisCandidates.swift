import Foundation

/// Source and node name candidates for the analysis parameter editors,
/// derived from whichever design representation is currently active.
public struct AnalysisCandidates: Sendable, Equatable {
    /// Independent source names (V*/I*) — sweep and excitation targets.
    public let sourceNames: [String]
    /// Non-ground node names — output and probe targets.
    public let nodeNames: [String]

    public init(sourceNames: [String], nodeNames: [String]) {
        self.sourceNames = sourceNames
        self.nodeNames = nodeNames
    }

    public static let empty = AnalysisCandidates(sourceNames: [], nodeNames: [])

    /// Candidates from a parsed SPICE netlist (netlist editing mode).
    public static func from(netlist info: NetlistInfo) -> AnalysisCandidates {
        let sources = info.components
            .filter { $0.type == "V" || $0.type == "I" }
            .map(\.name)
        let nodes = info.nodes.filter { $0 != "0" }
        return AnalysisCandidates(
            sourceNames: deduplicated(sources),
            nodeNames: deduplicated(nodes)
        )
    }

    /// Candidates from a visual schematic (schematic capture mode).
    /// Sources are components whose device kind emits a V/I card; nodes
    /// are the extracted nets, excluding ground.
    public static func from(
        document: SchematicDocument,
        catalog: DeviceCatalog
    ) -> AnalysisCandidates {
        let sources = document.components
            .filter { component in
                guard let kind = catalog.device(for: component.deviceKindID) else {
                    return false
                }
                return kind.spicePrefix == "V" || kind.spicePrefix == "I"
            }
            .map(\.name)
        let nodes = NetExtractor()
            .extract(from: document)
            .map(\.name)
            .filter { $0 != "0" }
        return AnalysisCandidates(
            sourceNames: deduplicated(sources),
            nodeNames: deduplicated(nodes)
        )
    }

    private static func deduplicated(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
