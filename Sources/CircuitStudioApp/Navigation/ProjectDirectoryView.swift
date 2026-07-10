import SwiftUI
import CircuitStudioCore

/// A useful center-editor summary for a directory selected in the project navigator.
struct ProjectDirectoryView: View {
    let url: URL
    let root: FileNode?
    let openItem: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.title3.weight(.semibold))
                    Text(url.path(percentEncoded: false))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if children.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder")
            } else {
                List(children) { node in
                    Button {
                        openItem(node.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: node.isDirectory ? "folder" : "doc")
                                .foregroundStyle(.secondary)
                            Text(node.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var children: [FileNode] {
        findNode(url, in: root)?.children ?? []
    }

    private func findNode(_ target: URL, in node: FileNode?) -> FileNode? {
        guard let node else { return nil }
        if node.id == target { return node }
        for child in node.children ?? [] {
            if let match = findNode(target, in: child) {
                return match
            }
        }
        return nil
    }
}
