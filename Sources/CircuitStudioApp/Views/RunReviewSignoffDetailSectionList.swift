import SwiftUI

struct RunReviewSignoffDetailSectionList: View {
    let sections: [RunReviewSignoffDetailSection]

    var body: some View {
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sections, id: \.title) { section in
                    DisclosureGroup {
                        RunReviewSignoffDetailRows(rows: section.rows)
                            .padding(.top, 3)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: iconName(for: section.title))
                                .foregroundStyle(color(for: section.title))
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                            Text("\(section.rows.count)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func iconName(for title: String) -> String {
        switch title {
        case "Artifact Evaluation":
            return "checklist.checked"
        case "Evaluation Criteria":
            return "slider.horizontal.3"
        case "Evaluation Channels":
            return "dot.radiowaves.left.and.right"
        case "Feedback Signals":
            return "arrow.triangle.2.circlepath"
        default:
            return "list.bullet.rectangle"
        }
    }

    private func color(for title: String) -> Color {
        switch title {
        case "Artifact Evaluation", "Evaluation Criteria", "Evaluation Channels", "Feedback Signals":
            return .blue
        default:
            return .secondary
        }
    }
}
