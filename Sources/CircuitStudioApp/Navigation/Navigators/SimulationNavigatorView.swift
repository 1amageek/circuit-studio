import SwiftUI
import CircuitStudioCore
import CoreSpiceWaveform

/// Summary of the current simulation plus waveform-rich results cached for the
/// current app session. Durable run history is owned by the `.xcircuite` ledger.
struct SimulationNavigatorView: View {
    @Bindable var appState: AppState
    @State private var expandedBatchIDs: Set<UUID> = []

    var body: some View {
        List {
            statusSection
            if let info = appState.netlistInfo, !info.analyses.isEmpty {
                analysesSection(info.analyses)
            }
            if !appState.runHistory.isEmpty {
                runHistorySection
            }
        }
        .listStyle(.sidebar)
        .onAppear { expandNewestBatch() }
        .onChange(of: appState.runHistory.count) { _, _ in
            expandNewestBatch()
        }
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
                Button {
                    appState.showSchematic(appState.schematicModeContext)
                    appState.showDebugArea = true
                    appState.debugAreaTab = .console
                } label: {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show Simulation Console")
            }
        }
    }

    private func analysesSection(_ analyses: [AnalysisSummary]) -> some View {
        Section("Detected Analyses") {
            ForEach(analyses) { analysis in
                Button {
                    appState.showSchematic(.netlist)
                } label: {
                    HStack {
                        Text(analysis.type)
                            .font(.system(.body))
                        Spacer()
                        Text(analysis.label)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show in Netlist")
            }
        }
    }

    // MARK: - Run History

    private var runHistorySection: some View {
        Section("Session Results") {
            ForEach(appState.runHistory.reversed()) { batch in
                DisclosureGroup(isExpanded: batchExpansionBinding(batch.id)) {
                    ForEach(batch.records) { record in
                        recordRow(record)
                    }
                    overlayButtons(batch)
                } label: {
                    batchLabel(batch)
                }
            }
        }
    }

    private func batchLabel(_ batch: AnalysisRunBatch) -> some View {
        let completed = batch.records.filter { $0.status == .completed }.count
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(batch.startedAt, format: .dateTime.hour().minute().second())
                if let runID = batch.runID {
                    Text(runID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(completed)/\(batch.records.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func recordRow(_ record: AnalysisRunRecord) -> some View {
        Button {
            select(record)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: recordIcon(record.status))
                    .foregroundStyle(recordTint(record.status))
                Text(record.analysis.mnemonic)
                    .font(.system(.body, design: .monospaced))
                if let cornerName = record.cornerName {
                    Text(cornerName)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let temperature = record.temperature {
                    Text(String(format: "%.4g°C", temperature))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Plottable results focus the waveform pane; everything else (failures,
    /// cancellations, point results) goes to the console where its output is.
    private func select(_ record: AnalysisRunRecord) {
        if record.status == .completed,
           let waveform = record.result?.waveform,
           waveform.pointCount > 0 {
            appState.focusWaveform(waveform, source: .history)
            return
        }
        appState.showSchematic(appState.schematicModeContext)
        appState.showDebugArea = true
        appState.debugAreaTab = .console
    }

    @ViewBuilder
    private func overlayButtons(_ batch: AnalysisRunBatch) -> some View {
        ForEach(overlayableAnalyses(batch), id: \.self) { analysis in
            Button {
                buildOverlay(batch: batch, analysis: analysis)
            } label: {
                Label("Overlay \(analysis.mnemonic) corners", systemImage: "square.3.layers.3d")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Analyses with 2+ completed corner results, first-seen order. Pole-zero
    /// is excluded: its sweep is an index, not a physical axis to overlay on.
    private func overlayableAnalyses(_ batch: AnalysisRunBatch) -> [AnalysisCommand] {
        var order: [AnalysisCommand] = []
        var counts: [AnalysisCommand: Int] = [:]
        for record in batch.records {
            guard record.status == .completed,
                  record.cornerName != nil,
                  let waveform = record.result?.waveform,
                  waveform.pointCount > 0,
                  waveform.metadata.analysisType != .poleZero else { continue }
            if counts[record.analysis] == nil {
                order.append(record.analysis)
            }
            counts[record.analysis, default: 0] += 1
        }
        return order.filter { (counts[$0] ?? 0) >= 2 }
    }

    private func buildOverlay(batch: AnalysisRunBatch, analysis: AnalysisCommand) {
        let sources = batch.records.compactMap { record -> CornerOverlayBuilder.Source? in
            guard record.analysis == analysis,
                  record.status == .completed,
                  let cornerName = record.cornerName,
                  let waveform = record.result?.waveform,
                  waveform.pointCount > 0 else { return nil }
            return CornerOverlayBuilder.Source(label: cornerName, waveform: waveform)
        }
        do {
            let overlay = try CornerOverlayBuilder().build(sources: sources)
            appState.focusWaveform(overlay, source: .overlay)
        } catch {
            appState.log("Corner overlay failed: \(error.localizedDescription)", kind: .warning)
        }
    }

    private func batchExpansionBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedBatchIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedBatchIDs.insert(id)
                } else {
                    expandedBatchIDs.remove(id)
                }
            }
        )
    }

    private func expandNewestBatch() {
        guard let newest = appState.runHistory.last else { return }
        expandedBatchIDs.insert(newest.id)
    }

    private func recordIcon(_ status: RunStatus) -> String {
        switch status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "slash.circle"
        case .pending: return "circle"
        case .running: return "circle.dashed"
        }
    }

    private func recordTint(_ status: RunStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .pending, .running: return .secondary
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
