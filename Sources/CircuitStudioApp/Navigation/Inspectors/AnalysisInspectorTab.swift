import SwiftUI
import CircuitStudioCore

/// Analysis configuration tab. Selects the analysis type and exposes its parameters.
/// Run/Stop is performed from the toolbar — Cmd-R uses whatever this tab has selected.
struct AnalysisInspectorTab: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            typeSection
            parametersSection
        }
        .formStyle(.grouped)
    }

    private var typeSection: some View {
        Section("Analysis") {
            Picker("Type", selection: typeBinding) {
                Text("Operating Point").tag(AnalysisType.op)
                Text("Transient").tag(AnalysisType.tran)
                Text("AC Sweep").tag(AnalysisType.ac)
                Text("DC Sweep").tag(AnalysisType.dc)
            }
        }
    }

    @ViewBuilder
    private var parametersSection: some View {
        switch appState.selectedAnalysis {
        case .op:
            Section("Parameters") {
                Text("Operating point has no parameters.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        case .tran(let spec):
            Section("Transient") {
                durationField(
                    label: "Stop Time",
                    value: spec.stopTime,
                    update: { newValue in
                        appState.selectedAnalysis = .tran(TranSpec(
                            stopTime: newValue,
                            stepTime: spec.stepTime,
                            startTime: spec.startTime,
                            maxStep: spec.maxStep
                        ))
                    }
                )
                durationField(
                    label: "Step Time",
                    value: spec.stepTime ?? 0,
                    update: { newValue in
                        appState.selectedAnalysis = .tran(TranSpec(
                            stopTime: spec.stopTime,
                            stepTime: newValue > 0 ? newValue : nil,
                            startTime: spec.startTime,
                            maxStep: spec.maxStep
                        ))
                    }
                )
            }
        case .ac(let spec):
            Section("AC Sweep") {
                Picker("Scale", selection: Binding(
                    get: { spec.scaleType },
                    set: { newValue in
                        appState.selectedAnalysis = .ac(ACSpec(
                            scaleType: newValue,
                            numberOfPoints: spec.numberOfPoints,
                            startFrequency: spec.startFrequency,
                            stopFrequency: spec.stopFrequency
                        ))
                    }
                )) {
                    Text("Decade").tag(ACScale.decade)
                    Text("Octave").tag(ACScale.octave)
                    Text("Linear").tag(ACScale.linear)
                }
                LabeledContent("Points") {
                    TextField("", value: Binding(
                        get: { spec.numberOfPoints },
                        set: { newValue in
                            appState.selectedAnalysis = .ac(ACSpec(
                                scaleType: spec.scaleType,
                                numberOfPoints: max(1, newValue),
                                startFrequency: spec.startFrequency,
                                stopFrequency: spec.stopFrequency
                            ))
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
                }
                frequencyField(
                    label: "Start (Hz)",
                    value: spec.startFrequency,
                    update: { newValue in
                        appState.selectedAnalysis = .ac(ACSpec(
                            scaleType: spec.scaleType,
                            numberOfPoints: spec.numberOfPoints,
                            startFrequency: newValue,
                            stopFrequency: spec.stopFrequency
                        ))
                    }
                )
                frequencyField(
                    label: "Stop (Hz)",
                    value: spec.stopFrequency,
                    update: { newValue in
                        appState.selectedAnalysis = .ac(ACSpec(
                            scaleType: spec.scaleType,
                            numberOfPoints: spec.numberOfPoints,
                            startFrequency: spec.startFrequency,
                            stopFrequency: newValue
                        ))
                    }
                )
            }
        case .dcSweep, .noise, .tf, .pz:
            Section("Parameters") {
                Text("Editing this analysis from the inspector is not yet supported.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    // MARK: - Helpers

    private enum AnalysisType: Hashable { case op, tran, ac, dc }

    private var typeBinding: Binding<AnalysisType> {
        Binding(
            get: {
                switch appState.selectedAnalysis {
                case .op: return .op
                case .tran: return .tran
                case .ac: return .ac
                case .dcSweep: return .dc
                default: return .op
                }
            },
            set: { newValue in
                switch newValue {
                case .op:
                    appState.selectedAnalysis = .op
                case .tran:
                    appState.selectedAnalysis = .tran(TranSpec(stopTime: 1e-3, stepTime: 10e-6))
                case .ac:
                    appState.selectedAnalysis = .ac(ACSpec(
                        scaleType: .decade, numberOfPoints: 20,
                        startFrequency: 1, stopFrequency: 1e6
                    ))
                case .dc:
                    appState.selectedAnalysis = .dcSweep(DCSweepSpec(
                        source: "V1", startValue: 0, stopValue: 5, stepValue: 0.1
                    ))
                }
            }
        )
    }

    private func durationField(
        label: String,
        value: Double,
        update: @escaping (Double) -> Void
    ) -> some View {
        LabeledContent(label) {
            TextField("", value: Binding(get: { value }, set: { update($0) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 100)
            Text("s")
                .foregroundStyle(.secondary)
        }
    }

    private func frequencyField(
        label: String,
        value: Double,
        update: @escaping (Double) -> Void
    ) -> some View {
        LabeledContent(label) {
            TextField("", value: Binding(get: { value }, set: { update($0) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
        }
    }
}
