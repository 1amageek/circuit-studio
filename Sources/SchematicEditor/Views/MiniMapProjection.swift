import CoreGraphics

/// Single source of truth for coordinate mapping between world (canvas) space and MiniMap pixel space.
///
/// Both drawing and navigation code use this type, eliminating duplicated transform logic.
struct MiniMapProjection {
    let miniMapSize: CGSize
    let worldRect: CGRect
    let scale: CGFloat
    /// Pixel offset within the MiniMap where `worldRect.origin` maps to.
    let origin: CGPoint

    /// - Parameters:
    ///   - miniMapSize: The pixel dimensions of the MiniMap view.
    ///   - worldRect: The rectangle in canvas (world) coordinates to display.
    ///   - padding: Inset from the MiniMap edges.
    init(miniMapSize: CGSize, worldRect: CGRect, padding: CGFloat) {
        self.miniMapSize = miniMapSize
        self.worldRect = worldRect

        let available = CGSize(
            width: miniMapSize.width - padding * 2,
            height: miniMapSize.height - padding * 2
        )

        guard worldRect.width > 0, worldRect.height > 0,
              available.width > 0, available.height > 0 else {
            self.scale = 1
            self.origin = CGPoint(x: padding, y: padding)
            return
        }

        let scaleX = available.width / worldRect.width
        let scaleY = available.height / worldRect.height
        let s = min(scaleX, scaleY)
        self.scale = s

        let scaledWidth = worldRect.width * s
        let scaledHeight = worldRect.height * s
        self.origin = CGPoint(
            x: (miniMapSize.width - scaledWidth) / 2,
            y: (miniMapSize.height - scaledHeight) / 2
        )
    }

    /// Convert a world-space point to MiniMap pixel coordinates.
    func worldToMiniMap(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x + (point.x - worldRect.origin.x) * scale,
            y: origin.y + (point.y - worldRect.origin.y) * scale
        )
    }

    /// Convert a MiniMap pixel point to world-space coordinates.
    func miniMapToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - origin.x) / scale + worldRect.origin.x,
            y: (point.y - origin.y) / scale + worldRect.origin.y
        )
    }

    /// Convert a world-space rectangle to MiniMap pixel coordinates.
    func worldRectToMiniMap(_ rect: CGRect) -> CGRect {
        let topLeft = worldToMiniMap(rect.origin)
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}
