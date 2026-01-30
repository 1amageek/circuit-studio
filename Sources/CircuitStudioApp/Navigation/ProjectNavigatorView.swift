import SwiftUI
import CircuitStudioCore

/// File tree navigator for the sidebar.
/// Displays the project directory as an outline and loads SPICE files on selection.
struct ProjectNavigatorView: View {
    @Bindable var appState: AppState
    let fileSystemService: FileSystemService

    var body: some View {
        Group {
            if let root = appState.projectRoot {
                fileTreeContent(root: root)
            } else {
                emptyContent
            }
        }
        .navigationTitle("Project")
    }

    @ViewBuilder
    private func fileTreeContent(root: FileNode) -> some View {
        List(selection: $appState.selectedFileURL) {
            OutlineGroup(root.children ?? [], id: \.id, children: \.children) { node in
                Label {
                    Text(node.name)
                } icon: {
                    Image(systemName: fileIcon(for: node))
                        .foregroundStyle(node.isSPICEFile ? .orange : .secondary)
                }
                .tag(node.id)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: appState.selectedFileURL) { _, newURL in
            guard let url = newURL else { return }
            openSelectedFile(url: url)
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label("No Project Open", systemImage: "folder")
        } description: {
            Text("Open a folder to browse project files.")
        }
    }

    private func openSelectedFile(url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "cir" || ext == "spice" || ext == "sp" || ext == "net" || ext == "txt" else {
            return
        }
        do {
            try appState.loadSPICEFile(url: url)
            appState.activeEditor = .netlist
        } catch {
            appState.simulationError = "Failed to load file: \(error.localizedDescription)"
        }
    }

    private func fileIcon(for node: FileNode) -> String {
        if node.isDirectory {
            return "folder"
        }
        if node.isSPICEFile {
            return "doc.text"
        }
        return "doc"
    }
}

#Preview("Navigator — Empty") {
    ProjectNavigatorView(
        appState: AppState(),
        fileSystemService: FileSystemService()
    )
    .frame(width: 240, height: 400)
}
