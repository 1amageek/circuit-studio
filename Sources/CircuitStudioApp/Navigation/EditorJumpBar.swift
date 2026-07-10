import SwiftUI

/// Editor-local navigation derived from the same destination that renders the center pane.
struct EditorJumpBar: View {
    @Bindable var appState: AppState
    @Bindable var project: StudioSession

    var body: some View {
        HStack(spacing: 8) {
            if case .schematic = appState.editorDestination {
                modePicker
                Divider().frame(height: 16)
            }
            breadcrumb
            Spacer(minLength: 0)
            if isTransientDestination {
                Button {
                    appState.closeTransientEditor()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Editor")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var modePicker: some View {
        Menu {
            Button {
                appState.showSchematic(.visual)
            } label: {
                Label("Visual", systemImage: "square.grid.3x3")
            }
            Button {
                appState.showSchematic(.netlist)
            } label: {
                Label("Netlist", systemImage: "doc.text")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: modeIcon)
                Text(modeTitle)
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            if let projectName = appState.projectRootURL?.lastPathComponent {
                crumb(text: projectName, icon: "folder")
                chevron
            }
            crumb(text: editorTitle, icon: editorIcon)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    private func crumb(text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .lineLimit(1)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private var modeIcon: String {
        appState.activeSchematicMode == .visual ? "square.grid.3x3" : "doc.text"
    }

    private var modeTitle: String {
        appState.activeSchematicMode == .visual ? "Visual" : "Netlist"
    }

    private var editorTitle: String {
        switch appState.editorDestination {
        case .schematic(.visual):
            return project.activeCellName
        case .schematic(.netlist):
            return appState.spiceFileName ?? "Untitled Netlist"
        case .layout:
            return "\(project.activeCellName) Layout"
        case .integration:
            return "\(project.activeCellName) Schematic + Layout"
        case .review:
            return "Run Review"
        case .projectFile(let url), .projectDirectory(let url):
            return url.lastPathComponent
        case .waveform:
            return "Waveform Result"
        }
    }

    private var editorIcon: String {
        switch appState.editorDestination {
        case .schematic(.visual): return "square.grid.3x3"
        case .schematic(.netlist): return "doc.text"
        case .layout: return "square.dashed"
        case .integration: return "rectangle.split.2x1"
        case .review: return "checkmark.seal"
        case .projectFile: return "doc"
        case .projectDirectory: return "folder"
        case .waveform: return "waveform.path.ecg"
        }
    }

    private var isTransientDestination: Bool {
        appState.activeWorkspace == nil
    }
}
