import SwiftUI
import CircuitStudioCore
import LayoutVerify

/// Aggregated diagnostics from schematic, netlist, layout (DRC), and the latest simulation.
/// Mirrors Xcode's Issue Navigator: errors first, warnings next, info last.
struct IssuesNavigatorView: View {
    @Bindable var appState: AppState
    @Bindable var project: DesignProject

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No Issues",
                systemImage: "checkmark.seal",
                description: Text("Diagnostics, DRC violations, and simulation errors will appear here.")
            )
        } else {
            List {
                let grouped = groupedRows
                ForEach(grouped, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items, id: \.id) { row in
                            issueRow(row)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func issueRow(_ row: IssueRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: row.icon)
                .foregroundStyle(row.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(.body))
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Aggregation

    private struct IssueRow {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let detail: String?
        let group: String
    }

    private struct IssueGroup {
        let title: String
        let items: [IssueRow]
    }

    private var rows: [IssueRow] {
        var result: [IssueRow] = []

        for d in project.schematicViewModel.diagnostics {
            result.append(IssueRow(
                id: "schem-\(d.id)",
                icon: schematicIcon(d.severity),
                tint: schematicTint(d.severity),
                title: d.message,
                detail: nil,
                group: "Schematic"
            ))
        }

        for d in appState.netlistInfo?.diagnostics ?? [] {
            let detail: String? = d.line.map { "Line \($0)" }
            result.append(IssueRow(
                id: "net-\(d.id)",
                icon: netlistIcon(d.severity),
                tint: netlistTint(d.severity),
                title: d.message,
                detail: detail,
                group: "Netlist"
            ))
        }

        for v in project.layoutViewModel.violations {
            result.append(IssueRow(
                id: "drc-\(v.id)",
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                title: v.message,
                detail: v.layer.map { "Layer \($0.name)" },
                group: "DRC"
            ))
        }

        if let error = appState.simulationError {
            result.append(IssueRow(
                id: "sim-error",
                icon: "xmark.octagon.fill",
                tint: .red,
                title: error,
                detail: nil,
                group: "Simulation"
            ))
        }

        if let error = project.layoutGenerationError {
            result.append(IssueRow(
                id: "layout-gen",
                icon: "xmark.octagon.fill",
                tint: .red,
                title: error,
                detail: nil,
                group: "Layout"
            ))
        }

        return result
    }

    private var groupedRows: [IssueGroup] {
        let dict = Dictionary(grouping: rows, by: \.group)
        return dict
            .map { IssueGroup(title: $0.key, items: $0.value) }
            .sorted { $0.title < $1.title }
    }

    private func schematicIcon(_ s: Diagnostic.Severity) -> String {
        switch s {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func schematicTint(_ s: Diagnostic.Severity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private func netlistIcon(_ s: NetlistDiagnostic.Severity) -> String {
        switch s {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .hint: return "lightbulb.fill"
        }
    }

    private func netlistTint(_ s: NetlistDiagnostic.Severity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .hint: return .secondary
        }
    }
}
