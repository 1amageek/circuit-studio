import CoreGraphics
import CircuitStudioCore

/// Holds copied schematic objects for paste operations.
public struct ClipboardContent: Sendable {
    public var components: [PlacedComponent]
    public var wires: [Wire]
    public var labels: [NetLabel]
    public var probes: [Probe]
    /// Centre of the copied bounding box, used to compute paste offset.
    public var anchorPoint: CGPoint

    public init(
        components: [PlacedComponent],
        wires: [Wire],
        labels: [NetLabel],
        probes: [Probe] = [],
        anchorPoint: CGPoint
    ) {
        self.components = components
        self.wires = wires
        self.labels = labels
        self.probes = probes
        self.anchorPoint = anchorPoint
    }
}
