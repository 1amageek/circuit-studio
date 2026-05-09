import SwiftUI
import CircuitStudioCore

/// Lightweight summary of the current simulation: status, last result, and analyses found in the netlist.
/// In future this can grow into a proper run history, but it stays simple for now.
struct SimulationNavigatorView: View {
    @Bindable var appState: AppState

    var body: some View {
        List {
            statusSection
            if let info = appState.netlistInfo, !info.analyses.isEmpty {
                analysesSection(info.analyses)
            }
        }
        .listStyle(.sidebar)
    }

    private var statusSection: some View {
        Section("Status") {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusTint)
                Text(statusText)
                    .font(.system(.body))
                Spacer()
            }
            if let error = appState.simulationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private func analysesSection(_ analyses: [AnalysisSummary]) -> some View {
        Section("Detected Analyses") {
            ForEach(analyses) { analysis in
                HStack {
                    Text(analysis.type)
                        .font(.system(.body))
                    Spacer()
                    Text(analysis.label)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var statusText: String {
        if appState.isSimulating {
            return appState.simulationStatus ?? "Running…"
        }
        if appState.simulationResult != nil {
            return "Last run completed"
        }
        if appState.simulationError != nil {
            return "Last run failed"
        }
        return "Idle"
    }

    private var statusIcon: String {
        if appState.isSimulating { return "circle.dashed" }
        if appState.simulationResult != nil { return "checkmark.circle.fill" }
        if appState.simulationError != nil { return "xmark.octagon.fill" }
        return "circle"
    }

    private var statusTint: Color {
        if appState.isSimulating { return .accentColor }
        if appState.simulationResult != nil { return .green }
        if appState.simulationError != nil { return .red }
        return .secondary
    }
}
