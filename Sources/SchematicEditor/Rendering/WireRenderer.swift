import SwiftUI
import CircuitStudioCore

/// Renders wires on the schematic canvas.
public struct WireRenderer {
    public static func render(
        _ wire: Wire,
        in context: inout GraphicsContext,
        selected: Bool = false,
        highlighted: Bool = false
    ) {
        var path = Path()
        path.move(to: wire.startPoint)
        path.addLine(to: wire.endPoint)

        let color: Color = selected ? .accentColor : highlighted ? .orange : .green
        let lineWidth: CGFloat = selected ? 2.5 : highlighted ? 2.5 : 1.5

        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        context.stroke(path, with: .color(color), style: style)
    }
}
