import Foundation

/// Target of a cross-probe selection between editors.
public enum ProbeTarget: Sendable {
    case schematicComponent(UUID)
    case schematicNet(String)
    case layoutShape(UUID)
    case layoutNet(UUID)
    case waveformSignal(String)
}

/// Service that synchronizes selections across schematic, layout, and waveform editors.
@Observable
@MainActor
public final class CrossProbeService {
    /// The currently active probe target (set by whichever editor initiated the probe).
    public var activeProbe: ProbeTarget?

    /// Mapping from schematic net name to layout net ID.
    public var netMapping: [String: UUID] = [:]

    /// Mapping from schematic component ID to layout instance ID.
    public var instanceMapping: [UUID: UUID] = [:]

    public init() {}
}
