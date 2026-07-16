import SwiftUI

struct RunReviewNetlistEvidenceView: View {
    let netlists: [RunReviewDesignEvidence.NetlistEvidence]

    @State private var selectedPath: String

    init(netlists: [RunReviewDesignEvidence.NetlistEvidence]) {
        self.netlists = netlists
        _selectedPath = State(initialValue: netlists.first?.artifact.reference.locator.location.value ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if netlists.count > 1 {
                Picker("Netlist source", selection: $selectedPath) {
                    ForEach(netlists, id: \.artifact.reference.locator.location.value) { netlist in
                        Text(netlist.phase.rawValue)
                            .tag(netlist.artifact.reference.locator.location.value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let selectedNetlist {
                ScrollView([.horizontal, .vertical]) {
                    Text(numbered(selectedNetlist.text))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .overlay {
                    Rectangle()
                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                }

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text(selectedNetlist.artifact.reference.locator.location.value)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .onChange(of: netlists.map(\.artifact.reference.locator.location.value)) { _, paths in
            if !paths.contains(selectedPath) {
                selectedPath = paths.first ?? ""
            }
        }
    }

    private var selectedNetlist: RunReviewDesignEvidence.NetlistEvidence? {
        netlists.first { $0.artifact.reference.locator.location.value == selectedPath } ?? netlists.first
    }

    private func numbered(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in
                String(format: "%4d  %@", index + 1, String(line))
            }
            .joined(separator: "\n")
    }
}
