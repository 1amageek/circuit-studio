import SwiftUI

struct RunReviewSignoffDetailRows: View {
    let rows: [RunReviewSignoffDetailRow]
    var minimumColumnWidth: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows, id: \.label) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.label)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: minimumColumnWidth), spacing: 6)],
                        alignment: .leading,
                        spacing: 3
                    ) {
                        ForEach(row.metrics, id: \.label) { metric in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(metric.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(metric.value)
                                    .font(.caption2.monospaced())
                                    .lineLimit(lineLimit(for: metric.label))
                            }
                        }
                    }
                }
            }
        }
    }

    private func lineLimit(for label: String) -> Int {
        switch label {
        case "Summary", "Text", "Actions", "Affected paths":
            return 2
        default:
            return 1
        }
    }
}
