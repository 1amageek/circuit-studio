import Foundation

/// The type of measurement a probe performs.
public enum ProbeType: Sendable, Codable, Hashable {
    /// Voltage at a single node (referenced to ground).
    case voltage(PinReference)
    /// Voltage difference between two nodes.
    case differential(positive: PinReference, negative: PinReference)
    /// Current through a component pin.
    /// Only valid for devices with SPICE branch variables (voltage sources and inductors).
    case current(PinReference)
}

/// Codable-safe color representation for probes.
public enum ProbeColor: String, Sendable, Codable, Hashable, CaseIterable {
    case blue
    case red
    case green
    case orange
    case purple
    case cyan
    case yellow
    case pink
}

/// A persistent measurement probe placed on the schematic.
///
/// Probes are stored in SchematicDocument and participate in undo/redo
/// via the snapshot-based UndoStack. They resolve to SPICE variable names
/// for the waveform viewer through ProbeResolver.
public struct Probe: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    /// Human-readable label (auto-generated or user-customized).
    public var label: String
    /// What this probe measures.
    public var probeType: ProbeType
    /// Display color in the waveform viewer.
    public var color: ProbeColor
    /// Whether this probe is enabled for measurement.
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        label: String,
        probeType: ProbeType,
        color: ProbeColor = .blue,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.label = label
        self.probeType = probeType
        self.color = color
        self.isEnabled = isEnabled
    }
}
