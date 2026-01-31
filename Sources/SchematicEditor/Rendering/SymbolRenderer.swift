import SwiftUI
import CircuitStudioCore

/// Renders circuit symbols using SwiftUI drawing commands.
public struct SymbolRenderer {

    /// Render a device kind's symbol at the given position and rotation.
    public static func render(
        _ kind: DeviceKind,
        in context: inout GraphicsContext,
        at position: CGPoint,
        rotation: Double = 0,
        mirrorX: Bool = false,
        mirrorY: Bool = false,
        selected: Bool = false
    ) {
        context.translateBy(x: position.x, y: position.y)

        // GraphicsContext applies later transforms first to the point.
        // We want Mirror → Rotate → Translate, so rotate must be outer (earlier call)
        // and mirror must be inner (later call).
        let rotationRadians = rotation * .pi / 180
        context.rotate(by: .radians(rotationRadians))

        let scaleX: CGFloat = mirrorY ? -1 : 1
        let scaleY: CGFloat = mirrorX ? -1 : 1
        context.scaleBy(x: scaleX, y: scaleY)

        let strokeColor: Color = selected ? .accentColor : Color(nsColor: .labelColor)
        let lineWidth: CGFloat = selected ? 2 : 1.5

        renderShape(kind.symbol.shape, in: &context, strokeColor: strokeColor, lineWidth: lineWidth)

        // Pin circles at port positions
        for port in kind.portDefinitions {
            let pinPos = port.position
            let radius: CGFloat = 2.5
            let rect = CGRect(
                x: pinPos.x - radius,
                y: pinPos.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(strokeColor))
        }

        // Reverse transforms in opposite order (undo inner first, then outer)
        context.scaleBy(x: scaleX, y: scaleY)
        context.rotate(by: .radians(-rotationRadians))
        context.translateBy(x: -position.x, y: -position.y)
    }

    private static func renderShape(
        _ shape: SymbolShape,
        in context: inout GraphicsContext,
        strokeColor: Color,
        lineWidth: CGFloat
    ) {
        switch shape {
        case .custom(let commands):
            for command in commands {
                renderCommand(command, in: &context, strokeColor: strokeColor, lineWidth: lineWidth)
            }
        case .ic(let width, let height):
            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            context.stroke(Path(rect), with: .color(strokeColor), lineWidth: lineWidth)
        }
    }

    private static func renderCommand(
        _ command: DrawCommand,
        in context: inout GraphicsContext,
        strokeColor: Color,
        lineWidth: CGFloat
    ) {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

        switch command {
        case .line(let from, let to):
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(strokeColor), style: style)

        case .rect(let origin, let size):
            let rect = CGRect(origin: origin, size: size)
            context.stroke(Path(rect), with: .color(strokeColor), style: style)

        case .circle(let center, let radius):
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.stroke(Path(ellipseIn: rect), with: .color(strokeColor), style: style)

        case .arc(let center, let radius, let startAngle, let endAngle):
            var path = Path()
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .radians(startAngle),
                endAngle: .radians(endAngle),
                clockwise: false
            )
            context.stroke(path, with: .color(strokeColor), style: style)

        case .text(let string, let at, let fontSize):
            let text = Text(string).font(.system(size: fontSize))
            context.draw(context.resolve(text), at: at, anchor: .center)
        }
    }
}
