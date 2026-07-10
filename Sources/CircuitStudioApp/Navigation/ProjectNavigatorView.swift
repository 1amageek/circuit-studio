import SwiftUI
import CircuitStudioCore

/// File tree navigator. Every selection opens a corresponding center editor.
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
    }

    @ViewBuilder
    private func fileTreeContent(root: FileNode) -> some View {
        VStack(spacing: 0) {
            PaneSectionHeader(root.name) {
                Button {
                    appState.refreshProjectTree(using: fileSystemService)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh Project Files")
            }
            List {
                OutlineGroup(root.children ?? [], id: \.id, children: \.children) { node in
                    Button {
                        appState.requestOpenProjectItem(at: node.id, using: fileSystemService)
                    } label: {
                        Label {
                            Text(node.name)
                        } icon: {
                            Image(systemName: fileIcon(for: node))
                                .foregroundStyle(node.isSPICEFile ? .orange : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        node.id == appState.projectNavigatorSelection
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label("No Project Open", systemImage: "folder")
        } description: {
            Text("Open a folder to browse project files.")
        }
    }

    private func fileIcon(for node: FileNode) -> String {
        if node.isDirectory {
            return "folder"
        }
        if node.isSPICEFile {
            return "doc.text"
        }
        switch node.id.pathExtension.lowercased() {
        case "json": return "curlybraces"
        case "toml", "yaml", "yml": return "gearshape"
        case "gds", "oas": return "square.3.layers.3d"
        case "spef": return "point.3.connected.trianglepath.dotted"
        default: break
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
