import SwiftUI

/// Renders the background grid on the schematic canvas.
public struct GridRenderer {
    public static func render(
        in context: inout GraphicsContext,
        size: CGSize,
        gridSize: CGFloat,
        zoom: CGFloat,
        offset: CGPoint
    ) {
        let scaledGrid = gridSize * zoom
        guard scaledGrid > 4 else { return }

        let startX = offset.x.truncatingRemainder(dividingBy: scaledGrid)
        let startY = offset.y.truncatingRemainder(dividingBy: scaledGrid)

        let dotRadius: CGFloat = scaledGrid > 20 ? 1.5 : 0.75

        var x = startX
        while x < size.width {
            var y = startY
            while y < size.height {
                let rect = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.3)))
                y += scaledGrid
            }
            x += scaledGrid
        }
    }
}
