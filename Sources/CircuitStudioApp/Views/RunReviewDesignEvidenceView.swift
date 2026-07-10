import SwiftUI

struct RunReviewDesignEvidenceView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case schematic = "Circuit"
        case layout = "Layout"
        case waveforms = "Waveforms"
        case netlists = "Netlists"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .schematic: "point.3.connected.trianglepath.dotted"
            case .layout: "square.3.layers.3d"
            case .waveforms: "waveform.path.ecg"
            case .netlists: "doc.plaintext"
            }
        }
    }

    let evidence: RunReviewDesignEvidence
    @State private var selectedSection: Section

    init(evidence: RunReviewDesignEvidence) {
        self.evidence = evidence
        _selectedSection = State(initialValue: Self.availableSections(evidence).first ?? .schematic)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Design view", selection: $selectedSection) {
                    ForEach(availableSections) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Divider()

                sectionContent
                    .frame(minHeight: 360, idealHeight: 430, maxHeight: 520)

                if !evidence.issues.isEmpty {
                    DisclosureGroup("Display diagnostics (\(evidence.issues.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(evidence.issues.enumerated()), id: \.offset) { _, issue in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 1) {
                                        if let path = issue.artifactPath {
                                            Text(path)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text(issue.message)
                                            .font(.caption)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                Text("Design")
                Spacer()
                Text("canonical artifacts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: evidence.sourceSignature) { _, _ in
            if !availableSections.contains(selectedSection) {
                selectedSection = availableSections.first ?? .schematic
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .schematic:
            if let schematic = evidence.schematic {
                RunReviewSchematicEvidenceView(evidence: schematic)
            }
        case .layout:
            if let layout = evidence.layout {
                RunReviewLayoutEvidenceView(evidence: layout)
            }
        case .waveforms:
            RunReviewWaveformEvidenceView(waveforms: evidence.waveforms)
        case .netlists:
            RunReviewNetlistEvidenceView(netlists: evidence.netlists)
        }
    }

    private var availableSections: [Section] {
        Self.availableSections(evidence)
    }

    private static func availableSections(_ evidence: RunReviewDesignEvidence) -> [Section] {
        Section.allCases.filter { section in
            switch section {
            case .schematic: evidence.schematic != nil
            case .layout: evidence.layout != nil
            case .waveforms: !evidence.waveforms.isEmpty
            case .netlists: !evidence.netlists.isEmpty
            }
        }
    }
}
