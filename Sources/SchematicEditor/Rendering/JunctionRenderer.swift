import SwiftUI
import CircuitStudioCore

/// Renders junction dots where three or more wires meet.
public struct JunctionRenderer {
    public static func render(
        _ junction: Junction,
        in context: inout GraphicsContext,
        selected: Bool = false
    ) {
        let radius: CGFloat = 3
        let rect = CGRect(
            x: junction.position.x - radius,
            y: junction.position.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let color: Color = selected ? .accentColor : .green
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }
}
