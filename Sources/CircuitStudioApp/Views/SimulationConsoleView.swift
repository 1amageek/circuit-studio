import SwiftUI

/// Terminal-style console displaying simulation pipeline activity.
///
/// Shows timestamped log entries for each stage: netlist generation,
/// generated SPICE source, analysis execution, and results.
struct SimulationConsoleView: View {
    @Bindable var appState: AppState

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            consoleToolbar
            Divider()
            consoleBody
        }
    }

    // MARK: - Toolbar

    private var consoleToolbar: some View {
        HStack(spacing: 8) {
            Label("Console", systemImage: "terminal")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if let status = appState.simulationStatus {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                appState.clearConsole()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear console")

            Button {
                appState.showConsole = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide console")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }

    // MARK: - Body

    private var consoleBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appState.consoleEntries) { entry in
                        entryRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .onChange(of: appState.consoleEntries.count) {
                if let last = appState.consoleEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Color(nsColor: .textBackgroundColor))
        .font(.system(.caption, design: .monospaced))
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: ConsoleEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if entry.kind != .output {
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .foregroundStyle(.tertiary)

                entryIcon(entry.kind)
            }

            Text(entry.message)
                .foregroundStyle(entryColor(entry.kind))
                .textSelection(.enabled)
        }
        .padding(.vertical, entry.kind == .output ? 0 : 2)
        .padding(.leading, entry.kind == .output ? 24 : 0)
    }

    @ViewBuilder
    private func entryIcon(_ kind: ConsoleEntry.Kind) -> some View {
        switch kind {
        case .info:
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .output:
            EmptyView()
        }
    }

    private func entryColor(_ kind: ConsoleEntry.Kind) -> Color {
        switch kind {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        case .output: return .secondary
        }
    }
}
