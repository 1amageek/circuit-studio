import SwiftUI
import SchematicEditor
import LayoutEditor

/// Context-aware Properties inspector derived from the visible center editor.
struct PropertiesInspectorTab: View {
    @Bindable var appState: AppState
    @Bindable var project: StudioSession

    var body: some View {
        switch appState.editorDestination {
        case .schematic(.visual):
            PropertyInspector(viewModel: project.schematicViewModel)
        case .schematic(.netlist):
            NetlistInspectorBody(appState: appState)
        case .layout:
            LayoutInspectorView(viewModel: project.layoutViewModel)
        case .integration:
            LayoutInspectorView(viewModel: project.layoutViewModel)
        case .review:
            ContentUnavailableView(
                "Run review has no properties",
                systemImage: "checkmark.seal",
                description: Text("Decisions are recorded per stage in the review pane.")
            )
        case .projectFile(let url):
            fileProperties(url)
        case .projectDirectory(let url):
            fileProperties(url)
        case .waveform:
            ContentUnavailableView(
                "Waveform properties",
                systemImage: "waveform.path.ecg",
                description: Text("Use the Waveform inspector for traces and axes.")
            )
        }
    }

    private func fileProperties(_ url: URL) -> some View {
        Form {
            Section("File") {
                LabeledContent("Name", value: url.lastPathComponent)
                LabeledContent("Type", value: url.pathExtension.isEmpty ? "Folder" : url.pathExtension.uppercased())
            }
            Section("Location") {
                Text(url.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            if let document = appState.projectFileDocument,
               document.url == url {
                Section("Content") {
                    LabeledContent("Size", value: ByteCountFormatter.string(
                        fromByteCount: Int64(document.byteCount),
                        countStyle: .file
                    ))
                    LabeledContent("Encoding", value: document.isEditable ? "UTF-8" : "Binary")
                    if document.isEditable {
                        LabeledContent("Lines", value: "\(document.lineCount)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
