import SwiftUI
import CircuitStudioCore

/// Properties inspector body for netlist mode. Shows file metadata and parsed netlist contents.
/// Process and Analysis live in their own inspector tabs and are intentionally absent here.
struct NetlistInspectorBody: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            fileSection
            componentsSection
            nodesSection
            modelsSection
            diagnosticsSection
            simulationErrorSection
        }
        .formStyle(.grouped)
    }

    // MARK: - File

    private var fileSection: some View {
        Section("File") {
            LabeledContent("Name", value: appState.spiceFileName ?? "Untitled")
            LabeledContent("Lines", value: "\(appState.spiceSource.components(separatedBy: "\n").count)")
            if let title = appState.netlistInfo?.title {
                LabeledContent("Title", value: title)
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var componentsSection: some View {
        let components = appState.netlistInfo?.components ?? []
        if !components.isEmpty {
            Section("Components (\(components.count))") {
                ForEach(components) { component in
                    HStack {
                        Text(component.name)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        Spacer()
                        if let model = component.modelName {
                            Text(model)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let value = component.primaryValue {
                            Text(value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(component.type)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Nodes

    @ViewBuilder
    private var nodesSection: some View {
        let nodes = appState.netlistInfo?.nodes ?? []
        if !nodes.isEmpty {
            Section("Nodes (\(nodes.count))") {
                ForEach(nodes, id: \.self) { node in
                    Text(node)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    // MARK: - Models

    @ViewBuilder
    private var modelsSection: some View {
        let models = appState.netlistInfo?.models ?? []
        if !models.isEmpty {
            Section("Models (\(models.count))") {
                ForEach(models) { model in
                    LabeledContent(model.name) {
                        Text(model.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Diagnostics

    @ViewBuilder
    private var diagnosticsSection: some View {
        let diagnostics = appState.netlistInfo?.diagnostics ?? []
        if !diagnostics.isEmpty {
            Section("Diagnostics") {
                ForEach(diagnostics) { d in
                    HStack(spacing: 6) {
                        Image(systemName: diagnosticIcon(d.severity))
                            .foregroundStyle(diagnosticColor(d.severity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.message)
                                .font(.caption)
                            if let line = d.line {
                                Text("Line \(line)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Simulation Error

    @ViewBuilder
    private var simulationErrorSection: some View {
        if let error = appState.simulationError {
            Section("Error") {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Diagnostic Helpers

    private func diagnosticIcon(_ severity: NetlistDiagnostic.Severity) -> String {
        switch severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .hint: return "lightbulb.fill"
        }
    }

    private func diagnosticColor(_ severity: NetlistDiagnostic.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .hint: return .secondary
        }
    }
}
