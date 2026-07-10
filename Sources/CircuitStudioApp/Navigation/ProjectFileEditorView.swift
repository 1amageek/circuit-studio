import SwiftUI
import AppKit

/// Text and metadata editor for non-SPICE files selected in the project navigator.
struct ProjectFileEditorView: View {
    @Bindable var appState: AppState
    let save: () -> Void
    let reload: () -> Void
    @State private var isRevertConfirmationPresented = false

    var body: some View {
        Group {
            if let document = appState.projectFileDocument {
                content(document)
            } else if let error = appState.projectFileError {
                ContentUnavailableView {
                    Label("File unavailable", systemImage: "xmark.octagon")
                } description: {
                    Text(error)
                }
            } else {
                ContentUnavailableView("File unavailable", systemImage: "doc.badge.ellipsis")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Revert unsaved changes?",
            isPresented: $isRevertConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Revert", role: .destructive, action: reload)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file will be reloaded from disk and local edits will be discarded.")
        }
    }

    @ViewBuilder
    private func content(_ document: ProjectFileDocument) -> some View {
        switch document.storage {
        case .text:
            textEditor(document)
        case .binary:
            unavailableContent(
                document,
                title: "Binary file",
                description: "This file cannot be displayed as UTF-8 text."
            )
        case .tooLarge(let limit):
            unavailableContent(
                document,
                title: "File is too large",
                description: "Files larger than \(formattedByteCount(limit)) are opened externally."
            )
        }
    }

    private func textEditor(_ document: ProjectFileDocument) -> some View {
        VStack(spacing: 0) {
            TextEditor(text: textBinding)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
            Divider()
            HStack(spacing: 12) {
                Text("UTF-8")
                Text("\(document.lineCount) lines")
                Text(formattedByteCount(document.byteCount))
                if let validationIssue {
                    Label(validationIssue, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if document.isDirty {
                    Label("Modified", systemImage: "circle.fill")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    isRevertConfirmationPresented = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(!document.isDirty)
                .help("Revert File")
                Button(action: save) {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(!document.isDirty || validationIssue != nil)
                .help("Save File")
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.bar)
        }
    }

    private func unavailableContent(
        _ document: ProjectFileDocument,
        title: String,
        description: String
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "doc")
        } description: {
            Text("\(description) \(formattedByteCount(document.byteCount)).")
        } actions: {
            HStack(spacing: 8) {
                Button("Open Externally") {
                    NSWorkspace.shared.open(document.url)
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([document.url])
                }
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { appState.projectFileDocument?.text ?? "" },
            set: { appState.updateProjectFileText($0) }
        )
    }

    private var validationIssue: String? {
        guard let document = appState.projectFileDocument,
              document.url.pathExtension.lowercased() == "json",
              let text = document.text else { return nil }
        guard let data = text.data(using: .utf8) else { return "Invalid UTF-8" }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return nil
        } catch {
            return "Invalid JSON"
        }
    }

    private func formattedByteCount(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
