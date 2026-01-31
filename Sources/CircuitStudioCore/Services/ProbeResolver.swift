import Foundation

/// A probe that has been resolved to concrete SPICE variable name(s).
public struct ResolvedProbe: Sendable {
    public let probeID: UUID
    public let label: String
    /// SPICE variable names. Typically one; differential probes produce two.
    public let variableNames: [String]
    public let color: ProbeColor

    public init(probeID: UUID, label: String, variableNames: [String], color: ProbeColor) {
        self.probeID = probeID
        self.label = label
        self.variableNames = variableNames
        self.color = color
    }
}

/// Resolves Probe instances into SPICE variable names using extracted net information.
///
/// Bridges the gap between schematic-level probe definitions (which reference PinReferences)
/// and simulation-level variable names (like "V(net0)" or "I(V1)").
public struct ProbeResolver: Sendable {

    public init() {}

    /// Resolve a single probe to its SPICE variable name(s).
    ///
    /// Returns nil if the probe targets unconnected pins or cannot be resolved.
    public func resolve(
        probe: Probe,
        nets: [ExtractedNet],
        components: [PlacedComponent],
        catalog: DeviceCatalog
    ) -> ResolvedProbe? {
        switch probe.probeType {
        case .voltage(let pinRef):
            guard let netName = netName(for: pinRef, in: nets) else { return nil }
            return ResolvedProbe(
                probeID: probe.id,
                label: probe.label,
                variableNames: ["V(\(netName))"],
                color: probe.color
            )

        case .differential(let pos, let neg):
            guard let posNet = netName(for: pos, in: nets),
                  let negNet = netName(for: neg, in: nets) else { return nil }
            return ResolvedProbe(
                probeID: probe.id,
                label: probe.label,
                variableNames: ["V(\(posNet))", "V(\(negNet))"],
                color: probe.color
            )

        case .current(let pinRef):
            guard let component = components.first(where: { $0.id == pinRef.componentID }),
                  let kind = catalog.device(for: component.deviceKindID) else {
                return nil
            }
            // Current measurement is only directly available for devices with branch variables.
            let validPrefixes: Set<String> = ["V", "L"]
            guard validPrefixes.contains(kind.spicePrefix) else { return nil }
            return ResolvedProbe(
                probeID: probe.id,
                label: probe.label,
                variableNames: ["I(\(component.name))"],
                color: probe.color
            )
        }
    }

    /// Resolve all enabled probes.
    public func resolveAll(
        probes: [Probe],
        nets: [ExtractedNet],
        components: [PlacedComponent],
        catalog: DeviceCatalog
    ) -> [ResolvedProbe] {
        probes
            .filter(\.isEnabled)
            .compactMap { resolve(probe: $0, nets: nets, components: components, catalog: catalog) }
    }

    private func netName(for pinRef: PinReference, in nets: [ExtractedNet]) -> String? {
        nets.first { net in
            net.connections.contains(pinRef)
        }?.name
    }
}
