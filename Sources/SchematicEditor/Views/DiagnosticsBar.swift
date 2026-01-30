import SwiftUI
import CircuitStudioCore

/// Compact bar displaying circuit validation diagnostics.
///
/// Shows a summary row with error/warning counts. Expands to reveal
/// individual diagnostic messages with navigation to the affected component.
struct DiagnosticsBar: View {
    let diagnostics: [Diagnostic]
    let onSelectComponent: (UUID?) -> Void
    @State private var isExpanded = false

    private var errorCount: Int {
        diagnostics.filter { $0.severity == .error }.count
    }

    private var warningCount: Int {
        diagnostics.filter { $0.severity == .warning }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    if errorCount > 0 {
                        Label("\(errorCount) error\(errorCount == 1 ? "" : "s")", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    if warningCount > 0 {
                        Label("\(warningCount) warning\(warningCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            // Expanded detail list
            if isExpanded {
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(diagnostics) { diagnostic in
                            DiagnosticRow(
                                diagnostic: diagnostic,
                                onSelect: onSelectComponent
                            )
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .background(.bar)
    }
}

/// Single diagnostic row with severity icon, message, and optional navigation.
private struct DiagnosticRow: View {
    let diagnostic: Diagnostic
    let onSelect: (UUID?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            severityIcon
                .frame(width: 16)
            Text(diagnostic.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            if diagnostic.componentID != nil {
                Button {
                    onSelect(diagnostic.componentID)
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if diagnostic.componentID != nil {
                onSelect(diagnostic.componentID)
            }
        }
    }

    @ViewBuilder
    private var severityIcon: some View {
        switch diagnostic.severity {
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .info:
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
