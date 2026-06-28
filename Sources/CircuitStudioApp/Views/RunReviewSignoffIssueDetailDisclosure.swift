import SwiftUI

struct RunReviewSignoffIssueDetailDisclosure: View {
    let rows: [RunReviewSignoffDetailRow]

    var body: some View {
        if !rows.isEmpty {
            DisclosureGroup {
                RunReviewSignoffDetailRows(rows: rows, minimumColumnWidth: 82)
                    .padding(.top, 3)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.secondary)
                    Text("Details")
                        .font(.caption2.weight(.semibold))
                    Text("\(rows.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
