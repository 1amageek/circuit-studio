import SwiftUI
import CircuitStudioCore

/// Analysis configuration tab. Selects the analysis type and exposes its parameters.
/// Run/Stop is performed from the toolbar — Cmd-R uses whatever this tab has selected.
struct AnalysisInspectorTab: View {
    @Bindable var appState: AppState
    let project: StudioSession
    let catalog: DeviceCatalog

    var body: some View {
        Form {
            typeSection
            parametersSection
        }
        .formStyle(.grouped)
    }

    /// Source/node candidates from the active design representation.
    private var candidates: AnalysisCandidates {
        switch appState.schematicMode {
        case .visual:
            return .from(document: project.schematicViewModel.document, catalog: catalog)
        case .netlist:
            guard let info = appState.netlistInfo else { return .empty }
            return .from(netlist: info)
        }
    }

    private var typeSection: some View {
        Section("Analysis") {
            Picker("Type", selection: typeBinding) {
                Text("Operating Point").tag(AnalysisType.op)
                Text("Transient").tag(AnalysisType.tran)
                Text("AC Sweep").tag(AnalysisType.ac)
                Text("DC Sweep").tag(AnalysisType.dc)
                Text("Noise").tag(AnalysisType.noise)
                Text("Transfer Function").tag(AnalysisType.tf)
                Text("Pole-Zero").tag(AnalysisType.pz)
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
            tranSection(spec)
        case .ac(let spec):
            acSection(spec)
        case .dcSweep(let spec):
            dcSweepSection(spec)
        case .noise(let spec):
            noiseSection(spec)
        case .tf(let spec):
            tfSection(spec)
        case .pz(let spec):
            pzSection(spec)
        }
    }

    // MARK: - Transient

    private func tranSection(_ spec: TranSpec) -> some View {
        Section("Transient") {
            durationField(
                label: "Stop Time",
                value: spec.stopTime,
                update: { newValue in
                    var updated = spec
                    updated.stopTime = newValue
                    appState.selectedAnalysis = .tran(updated)
                }
            )
            durationField(
                label: "Step Time",
                value: spec.stepTime ?? 0,
                update: { newValue in
                    var updated = spec
                    updated.stepTime = newValue > 0 ? newValue : nil
                    appState.selectedAnalysis = .tran(updated)
                }
            )
        }
    }

    // MARK: - AC Sweep

    private func acSection(_ spec: ACSpec) -> some View {
        Section("AC Sweep") {
            scalePicker(
                selection: spec.scaleType,
                update: { newValue in
                    var updated = spec
                    updated.scaleType = newValue
                    appState.selectedAnalysis = .ac(updated)
                }
            )
            pointsField(
                value: spec.numberOfPoints,
                update: { newValue in
                    var updated = spec
                    updated.numberOfPoints = newValue
                    appState.selectedAnalysis = .ac(updated)
                }
            )
            frequencyField(
                label: "Start (Hz)",
                value: spec.startFrequency,
                update: { newValue in
                    var updated = spec
                    updated.startFrequency = newValue
                    appState.selectedAnalysis = .ac(updated)
                }
            )
            frequencyField(
                label: "Stop (Hz)",
                value: spec.stopFrequency,
                update: { newValue in
                    var updated = spec
                    updated.stopFrequency = newValue
                    appState.selectedAnalysis = .ac(updated)
                }
            )
        }
    }

    // MARK: - DC Sweep

    private func dcSweepSection(_ spec: DCSweepSpec) -> some View {
        Section("DC Sweep") {
            namePicker(
                "Source",
                selection: spec.source,
                options: candidates.sourceNames,
                update: { newValue in
                    var updated = spec
                    updated.source = newValue
                    appState.selectedAnalysis = .dcSweep(updated)
                }
            )
            valueField(
                label: "Start",
                value: spec.startValue,
                update: { newValue in
                    var updated = spec
                    updated.startValue = newValue
                    appState.selectedAnalysis = .dcSweep(updated)
                }
            )
            valueField(
                label: "Stop",
                value: spec.stopValue,
                update: { newValue in
                    var updated = spec
                    updated.stopValue = newValue
                    appState.selectedAnalysis = .dcSweep(updated)
                }
            )
            valueField(
                label: "Step",
                value: spec.stepValue,
                update: { newValue in
                    var updated = spec
                    updated.stepValue = newValue
                    appState.selectedAnalysis = .dcSweep(updated)
                }
            )
        }
    }

    // MARK: - Noise

    @ViewBuilder
    private func noiseSection(_ spec: NoiseSpec) -> some View {
        Section("Noise") {
            namePicker(
                "Output Node",
                selection: spec.outputNode,
                options: candidates.nodeNames,
                update: { newValue in
                    var updated = spec
                    updated.outputNode = newValue
                    appState.selectedAnalysis = .noise(updated)
                }
            )
            optionalNodePicker(
                "Reference",
                selection: spec.referenceNode,
                options: candidates.nodeNames,
                update: { newValue in
                    var updated = spec
                    updated.referenceNode = newValue
                    appState.selectedAnalysis = .noise(updated)
                }
            )
            namePicker(
                "Input Source",
                selection: spec.inputSource,
                options: candidates.sourceNames,
                update: { newValue in
                    var updated = spec
                    updated.inputSource = newValue
                    appState.selectedAnalysis = .noise(updated)
                }
            )
        }
        Section("Sweep") {
            scalePicker(
                selection: spec.scaleType,
                update: { newValue in
                    var updated = spec
                    updated.scaleType = newValue
                    appState.selectedAnalysis = .noise(updated)
                }
            )
            pointsField(
                value: spec.numberOfPoints,
                update: { newValue in
                    var updated = spec
                    updated.numberOfPoints = newValue
                    appState.selectedAnalysis = .noise(updated)
                }
            )
            frequencyField(
                label: "Start (Hz)",
                value: spec.startFrequency,
                update: { newValue in
                    var updated = spec
                    updated.startFrequency = newValue
                    appState.selectedAnalysis = .noise(updated)
                }
            )
            frequencyField(
                label: "Stop (Hz)",
                value: spec.stopFrequency,
                update: { newValue in
                    var updated = spec
                    updated.stopFrequency = newValue
                    appState.selectedAnalysis = .noise(updated)
                }
            )
        }
    }

    // MARK: - Transfer Function

    private func tfSection(_ spec: TFSpec) -> some View {
        Section("Transfer Function") {
            namePicker(
                "Output Node",
                selection: spec.output,
                options: candidates.nodeNames,
                update: { newValue in
                    var updated = spec
                    updated.output = newValue
                    appState.selectedAnalysis = .tf(updated)
                }
            )
            namePicker(
                "Input Source",
                selection: spec.input,
                options: candidates.sourceNames,
                update: { newValue in
                    var updated = spec
                    updated.input = newValue
                    appState.selectedAnalysis = .tf(updated)
                }
            )
        }
    }

    // MARK: - Pole-Zero

    @ViewBuilder
    private func pzSection(_ spec: PZSpec) -> some View {
        Section("Pole-Zero") {
            namePicker(
                "Input Source",
                selection: spec.inputNode,
                options: candidates.sourceNames,
                update: { newValue in
                    var updated = spec
                    updated.inputNode = newValue
                    appState.selectedAnalysis = .pz(updated)
                }
            )
            namePicker(
                "Output Node",
                selection: spec.outputNode,
                options: candidates.nodeNames,
                update: { newValue in
                    var updated = spec
                    updated.outputNode = newValue
                    appState.selectedAnalysis = .pz(updated)
                }
            )
        }
        Section("References") {
            namePicker(
                "Input Ref",
                selection: spec.inputReference,
                options: groundedNodeNames,
                update: { newValue in
                    var updated = spec
                    updated.inputReference = newValue
                    appState.selectedAnalysis = .pz(updated)
                }
            )
            namePicker(
                "Output Ref",
                selection: spec.outputReference,
                options: groundedNodeNames,
                update: { newValue in
                    var updated = spec
                    updated.outputReference = newValue
                    appState.selectedAnalysis = .pz(updated)
                }
            )
        }
    }

    /// Node options including ground, for reference terminals.
    private var groundedNodeNames: [String] {
        ["0"] + candidates.nodeNames
    }

    // MARK: - Type Selection

    private enum AnalysisType: Hashable { case op, tran, ac, dc, noise, tf, pz }

    private var typeBinding: Binding<AnalysisType> {
        Binding(
            get: {
                switch appState.selectedAnalysis {
                case .op: return .op
                case .tran: return .tran
                case .ac: return .ac
                case .dcSweep: return .dc
                case .noise: return .noise
                case .tf: return .tf
                case .pz: return .pz
                }
            },
            set: { newValue in
                let source = candidates.sourceNames.first ?? "V1"
                let node = candidates.nodeNames.first ?? "out"
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
                        source: source, startValue: 0, stopValue: 5, stepValue: 0.1
                    ))
                case .noise:
                    appState.selectedAnalysis = .noise(NoiseSpec(
                        outputNode: node, inputSource: source,
                        scaleType: .decade, numberOfPoints: 20,
                        startFrequency: 1, stopFrequency: 1e6
                    ))
                case .tf:
                    appState.selectedAnalysis = .tf(TFSpec(output: node, input: source))
                case .pz:
                    appState.selectedAnalysis = .pz(PZSpec(
                        inputNode: source, inputReference: "0",
                        outputNode: node, outputReference: "0"
                    ))
                }
            }
        )
    }

    // MARK: - Field Helpers

    /// Picker over known names; falls back to a free-text field when no
    /// candidates exist so the user can still type a name. The current
    /// value stays selectable even when it is not among the candidates.
    @ViewBuilder
    private func namePicker(
        _ label: String,
        selection: String,
        options: [String],
        update: @escaping (String) -> Void
    ) -> some View {
        if options.isEmpty {
            LabeledContent(label) {
                TextField("", text: Binding(get: { selection }, set: { update($0) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
            }
        } else {
            Picker(label, selection: Binding(get: { selection }, set: { update($0) })) {
                if !options.contains(selection) {
                    Text(selection).tag(selection)
                }
                ForEach(options, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        }
    }

    /// Node picker with a "Ground" choice mapping to `nil`.
    private func optionalNodePicker(
        _ label: String,
        selection: String?,
        options: [String],
        update: @escaping (String?) -> Void
    ) -> some View {
        Picker(label, selection: Binding(
            get: { selection ?? "" },
            set: { update($0.isEmpty ? nil : $0) }
        )) {
            Text("Ground").tag("")
            if let selection, !selection.isEmpty, !options.contains(selection) {
                Text(selection).tag(selection)
            }
            ForEach(options, id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    private func scalePicker(
        selection: ACScale,
        update: @escaping (ACScale) -> Void
    ) -> some View {
        Picker("Scale", selection: Binding(get: { selection }, set: { update($0) })) {
            Text("Decade").tag(ACScale.decade)
            Text("Octave").tag(ACScale.octave)
            Text("Linear").tag(ACScale.linear)
        }
    }

    private func pointsField(
        value: Int,
        update: @escaping (Int) -> Void
    ) -> some View {
        LabeledContent("Points") {
            TextField("", value: Binding(get: { value }, set: { update(max(1, $0)) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 100)
        }
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

    private func valueField(
        label: String,
        value: Double,
        update: @escaping (Double) -> Void
    ) -> some View {
        LabeledContent(label) {
            TextField("", value: Binding(get: { value }, set: { update($0) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 100)
        }
    }
}

#Preview("DC Sweep") {
    let appState = AppState()
    appState.selectedAnalysis = .dcSweep(DCSweepSpec(
        source: "V1", startValue: 0, stopValue: 5, stepValue: 0.1
    ))
    return AnalysisInspectorTab(
        appState: appState,
        project: StudioSession(),
        catalog: .standard()
    )
    .frame(width: 280, height: 400)
}

#Preview("Noise") {
    let appState = AppState()
    appState.selectedAnalysis = .noise(NoiseSpec(
        outputNode: "out", inputSource: "V1",
        scaleType: .decade, numberOfPoints: 20,
        startFrequency: 1, stopFrequency: 1e6
    ))
    return AnalysisInspectorTab(
        appState: appState,
        project: StudioSession(),
        catalog: .standard()
    )
    .frame(width: 280, height: 500)
}

#Preview("Pole-Zero") {
    let appState = AppState()
    appState.selectedAnalysis = .pz(PZSpec(
        inputNode: "V1", inputReference: "0",
        outputNode: "out", outputReference: "0"
    ))
    return AnalysisInspectorTab(
        appState: appState,
        project: StudioSession(),
        catalog: .standard()
    )
    .frame(width: 280, height: 400)
}
