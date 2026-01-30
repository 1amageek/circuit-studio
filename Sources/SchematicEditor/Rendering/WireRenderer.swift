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

        // Junction dots at endpoints
        let dotRadius: CGFloat = 2.5
        for point in [wire.startPoint, wire.endPoint] {
            let rect = CGRect(
                x: point.x - dotRadius,
                y: point.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(.green))
        }
    }
}
