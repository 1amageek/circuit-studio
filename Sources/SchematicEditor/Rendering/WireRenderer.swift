import SwiftUI
import CircuitStudioCore

/// Renders wires on the schematic canvas.
public struct WireRenderer {
    public static func render(
        _ wire: Wire,
        in context: inout GraphicsContext,
        selected: Bool = false
    ) {
        var path = Path()
        path.move(to: wire.startPoint)
        path.addLine(to: wire.endPoint)

        let color: Color = selected ? .accentColor : .green
        let lineWidth: CGFloat = selected ? 2.5 : 1.5

        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }
}
