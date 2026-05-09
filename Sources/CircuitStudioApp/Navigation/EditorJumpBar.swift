import SwiftUI

/// Xcode-style jump bar that sits above the editor content area.
/// Left: Workspace + (when schematic) Mode picker.
/// Center/Right: Breadcrumb showing project › active file.
///
/// Replaces the toolbar's old segmented workspace/mode pickers — those moved here
/// to keep the window toolbar reserved for high-level actions (Run/Stop, panes).
struct EditorJumpBar: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            workspacePicker
            if appState.workspace == .schematicCapture {
                modePicker
            }
            Divider().frame(height: 16)
            breadcrumb
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var workspacePicker: some View {
        Menu {
            Button {
                appState.workspace = .schematicCapture
            } label: {
                Label("Schematic", systemImage: "square.grid.3x3")
            }
            Button {
                appState.workspace = .layout
            } label: {
                Label("Layout", systemImage: "square.dashed")
            }
            Button {
                appState.workspace = .integration
            } label: {
                Label("Integration", systemImage: "rectangle.split.2x1")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: workspaceIcon)
                Text(workspaceTitle)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var modePicker: some View {
        Menu {
            Button {
                appState.schematicMode = .visual
            } label: {
                Label("Visual", systemImage: "square.grid.3x3")
            }
            Button {
                appState.schematicMode = .netlist
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
            if let project = projectName {
                crumb(text: project, icon: "folder")
                chevron
            }
            crumb(text: fileName, icon: fileIcon)
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

    // MARK: - Derived

    private var workspaceIcon: String {
        switch appState.workspace {
        case .schematicCapture: return "square.grid.3x3"
        case .layout: return "square.dashed"
        case .integration: return "rectangle.split.2x1"
        }
    }

    private var workspaceTitle: String {
        switch appState.workspace {
        case .schematicCapture: return "Schematic"
        case .layout: return "Layout"
        case .integration: return "Integration"
        }
    }

    private var modeIcon: String {
        switch appState.schematicMode {
        case .visual: return "square.grid.3x3"
        case .netlist: return "doc.text"
        }
    }

    private var modeTitle: String {
        switch appState.schematicMode {
        case .visual: return "Visual"
        case .netlist: return "Netlist"
        }
    }

    private var projectName: String? {
        appState.projectRootURL?.lastPathComponent
    }

    private var fileName: String {
        if appState.workspace == .schematicCapture, appState.schematicMode == .netlist {
            return appState.spiceFileName ?? "Untitled"
        }
        if let url = appState.selectedFileURL {
            return url.lastPathComponent
        }
        switch appState.workspace {
        case .schematicCapture: return "Schematic"
        case .layout: return "Layout"
        case .integration: return "Schematic + Layout"
        }
    }

    private var fileIcon: String {
        if appState.workspace == .schematicCapture, appState.schematicMode == .netlist {
            return "doc.text"
        }
        switch appState.workspace {
        case .schematicCapture: return "square.grid.3x3"
        case .layout: return "square.dashed"
        case .integration: return "rectangle.split.2x1"
        }
    }
}
