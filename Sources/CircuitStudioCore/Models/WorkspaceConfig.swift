import Foundation

/// Persisted workspace configuration stored in `.xcircuite/workspace.json`.
public struct WorkspaceConfig: Sendable, Codable {
    public var version: Int
    public var activeWorkspace: String
    public var schematicMode: String
    public var panels: PanelState

    public struct PanelState: Sendable, Codable {
        public var inspector: Bool
        public var console: Bool
        public var simulationResults: Bool

        public init(
            inspector: Bool = false,
            console: Bool = false,
            simulationResults: Bool = false
        ) {
            self.inspector = inspector
            self.console = console
            self.simulationResults = simulationResults
        }
    }

    public init(
        version: Int = 1,
        activeWorkspace: String = "schematicCapture",
        schematicMode: String = "netlist",
        panels: PanelState = PanelState()
    ) {
        self.version = version
        self.activeWorkspace = activeWorkspace
        self.schematicMode = schematicMode
        self.panels = panels
    }
}
