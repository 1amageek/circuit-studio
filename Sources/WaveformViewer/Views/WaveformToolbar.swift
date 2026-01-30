import SwiftUI

/// Native macOS toolbar content for the waveform viewer.
public struct WaveformToolbarContent: ToolbarContent {
    @Bindable var viewModel: WaveformViewModel

    public init(viewModel: WaveformViewModel) {
        self.viewModel = viewModel
    }

    public var body: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryAction) {
            Button {
                viewModel.resetZoom()
            } label: {
                Label("Fit All", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Reset zoom to show all data")

            Button {
                viewModel.zoomIn()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .help("Zoom in 2x")
            .keyboardShortcut("+", modifiers: .command)

            Button {
                viewModel.zoomOut()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .help("Zoom out 2x")
            .keyboardShortcut("-", modifiers: .command)
        }

        ToolbarItem(placement: .status) {
            HStack(spacing: 8) {
                if let cursor = viewModel.document.cursorPosition {
                    Text("Cursor: \(formatSweep(cursor))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        viewModel.setCursor(at: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear cursor")
                }

                Text("\(viewModel.document.traces.filter(\.isVisible).count)/\(viewModel.document.traces.count) signals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatSweep(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue == 0 { return "0" }
        if absValue >= 1e6 { return String(format: "%.3gM", value / 1e6) }
        if absValue >= 1e3 { return String(format: "%.3gk", value / 1e3) }
        if absValue >= 1 { return String(format: "%.4g", value) }
        if absValue >= 1e-3 { return String(format: "%.3gm", value * 1e3) }
        if absValue >= 1e-6 { return String(format: "%.3gu", value * 1e6) }
        if absValue >= 1e-9 { return String(format: "%.3gn", value * 1e9) }
        return String(format: "%.3gp", value * 1e12)
    }
}

#Preview("Waveform Toolbar") {
    Text("Chart Area")
        .frame(width: 500, height: 300)
        .toolbar {
            WaveformToolbarContent(viewModel: WaveformPreview.transientViewModel())
        }
}
