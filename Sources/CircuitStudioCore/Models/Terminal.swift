import Foundation
import CoreGraphics

/// The connection state of a terminal on the schematic.
public enum TerminalConnectionState: Sendable, Hashable {
    /// No wire connected to this terminal.
    case unconnected
    /// Connected to a net.
    case connected(netName: String)
    /// Connected and actively probed.
    case probed(netName: String)
}

/// A resolved terminal on a placed component instance.
///
/// Terminals are computed (not stored in the document). They combine a component's
/// identity, a port definition, and the extracted net connectivity to provide a
/// complete, clickable interaction point on the canvas.
public struct Terminal: Sendable, Identifiable, Hashable {
    /// Stable identity derived from component ID and port ID.
    public var id: String { "\(pinReference.componentID):\(pinReference.portID)" }

    /// The PinReference this terminal represents.
    public let pinReference: PinReference

    /// Display name from PortDefinition (e.g. "Drain", "Gate").
    public let displayName: String

    /// Index in DeviceKind.portDefinitions, matching CoreSpice Instance.nodes[] order.
    public let portIndex: Int

    /// World-space position on the canvas (pre-computed with mirror/rotate/translate).
    public let worldPosition: CGPoint

    /// The net this terminal is connected to, if any.
    public let netName: String?

    /// Current visual state reflecting connection and probe status.
    public let connectionState: TerminalConnectionState

    /// The instance name of the owning component (e.g. "R1", "M2").
    public let componentName: String

    /// The SPICE prefix of the owning component's device kind (e.g. "R", "V", "M").
    public let spicePrefix: String

    public init(
        pinReference: PinReference,
        displayName: String,
        portIndex: Int,
        worldPosition: CGPoint,
        netName: String?,
        connectionState: TerminalConnectionState,
        componentName: String,
        spicePrefix: String
    ) {
        self.pinReference = pinReference
        self.displayName = displayName
        self.portIndex = portIndex
        self.worldPosition = worldPosition
        self.netName = netName
        self.connectionState = connectionState
        self.componentName = componentName
        self.spicePrefix = spicePrefix
    }
}
