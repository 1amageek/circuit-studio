import SwiftUI
import CircuitStudioCore

/// Renders probe icons on the schematic canvas.
public struct ProbeRenderer {

    /// Render a probe icon (diamond shape) at the given position.
    public static func render(
        _ probe: Probe,
        in context: inout GraphicsContext,
        at position: CGPoint,
        selected: Bool = false
    ) {
        let size: CGFloat = 6

        // Diamond shape
        var path = Path()
        path.move(to: CGPoint(x: position.x, y: position.y - size))
        path.addLine(to: CGPoint(x: position.x + size, y: position.y))
        path.addLine(to: CGPoint(x: position.x, y: position.y + size))
        path.addLine(to: CGPoint(x: position.x - size, y: position.y))
        path.closeSubpath()

        let fillColor = probeSwiftUIColor(probe.color)
        context.fill(path, with: .color(fillColor))

        if selected {
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        } else {
            context.stroke(path, with: .color(fillColor), lineWidth: 1)
        }

        // Disabled indicator: draw an X through the diamond
        if !probe.isEnabled {
            var xPath = Path()
            xPath.move(to: CGPoint(x: position.x - size, y: position.y - size))
            xPath.addLine(to: CGPoint(x: position.x + size, y: position.y + size))
            xPath.move(to: CGPoint(x: position.x + size, y: position.y - size))
            xPath.addLine(to: CGPoint(x: position.x - size, y: position.y + size))
            context.stroke(xPath, with: .color(.secondary), lineWidth: 1)
        }

        // Label below the icon
        let label = Text(probe.label).font(.system(size: 8))
        context.draw(
            context.resolve(label),
            at: CGPoint(x: position.x, y: position.y + size + 6),
            anchor: .center
        )
    }

    /// Map ProbeColor to SwiftUI Color.
    private static func probeSwiftUIColor(_ color: ProbeColor) -> Color {
        switch color {
        case .blue: return .blue
        case .red: return .red
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .cyan: return .cyan
        case .yellow: return .yellow
        case .pink: return .pink
        }
    }
}
