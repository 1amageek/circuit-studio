import Foundation

/// The single source of truth for what the center editor is displaying.
public enum EditorDestination: Hashable, Sendable {
    case schematic(SchematicMode)
    case layout
    case integration
    case review
    case projectFile(URL)
    case projectDirectory(URL)
    case waveform

    public var workspace: Workspace? {
        switch self {
        case .schematic:
            return .schematicCapture
        case .layout:
            return .layout
        case .integration:
            return .integration
        case .review:
            return .review
        case .projectFile, .projectDirectory, .waveform:
            return nil
        }
    }

    public var schematicMode: SchematicMode? {
        guard case .schematic(let mode) = self else { return nil }
        return mode
    }

    public var persistenceIdentifier: String? {
        switch self {
        case .schematic(.visual):
            return "schematic.visual"
        case .schematic(.netlist):
            return "schematic.netlist"
        case .layout:
            return "layout"
        case .integration:
            return "integration"
        case .review:
            return "review"
        case .projectFile, .projectDirectory, .waveform:
            return nil
        }
    }

    public var diagnosticIdentifier: String {
        persistenceIdentifier ?? {
            switch self {
            case .projectFile: return "projectFile"
            case .projectDirectory: return "projectDirectory"
            case .waveform: return "waveform"
            case .schematic, .layout, .integration, .review:
                return "unknown"
            }
        }()
    }

    public init?(persistenceIdentifier: String) {
        switch persistenceIdentifier {
        case "schematic.visual":
            self = .schematic(.visual)
        case "schematic.netlist":
            self = .schematic(.netlist)
        case "layout":
            self = .layout
        case "integration":
            self = .integration
        case "review":
            self = .review
        default:
            return nil
        }
    }
}
