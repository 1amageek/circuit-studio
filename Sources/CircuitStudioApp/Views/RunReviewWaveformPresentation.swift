import SwiftUI

enum RunReviewWaveformPresentation {
    static func value(_ value: Double?) -> String {
        guard let value else {
            return "n/a"
        }
        return String(format: "%.4g", value)
    }

    static func chartColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        return colors[index % colors.count]
    }
}
