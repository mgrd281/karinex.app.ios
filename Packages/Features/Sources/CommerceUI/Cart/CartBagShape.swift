import SwiftUI

// MARK: - CartBagShape

/// The cart's shopping bag as fashion retail apps draw it: a tote with a straight top edge that
/// widens slightly toward its rounded bottom corners, and a tall, round handle, as one even
/// outline (the proportions of the About You cart icon, owner request).
///
/// The shape is the filled outline, so it takes the foreground style like a symbol and renders
/// into template images. It is drawn on a grid of ``designSize`` and scales to fit its rect,
/// line width included; give it a frame with ``aspectRatio``.
struct CartBagShape: Shape {
    /// The size of the drawing grid in points, 22 high like the tab bar symbols.
    static let designSize = CartBagGrid.size

    /// The width of the bag divided by its height.
    static let aspectRatio = CartBagGrid.size.width / CartBagGrid.size.height

    nonisolated func path(in rect: CGRect) -> Path {
        let size = CartBagGrid.size
        let scale = min(rect.width / size.width, rect.height / size.height)
        let transform = CGAffineTransform(
            translationX: rect.midX - size.width * scale / 2,
            y: rect.midY - size.height * scale / 2
        )
        .scaledBy(x: scale, y: scale)
        return CartBagGrid.outline().applying(transform)
    }
}

// MARK: - CartBagGrid

/// The bag on its drawing grid. The outer edges of the outline touch the grid's bounds.
enum CartBagGrid {
    /// The grid, in points.
    static let size = CGSize(width: 18.46, height: 22)
    /// The even line width of the outline.
    static let lineWidth: CGFloat = 1.67
    /// The radius of the handle's half circle, on the line's center.
    static let handleRadius: CGFloat = 3.78
    /// The top edge of the body, on the line's center.
    static let bodyTop: CGFloat = 7.8
    /// Half the width of the top edge, on the line's center.
    static let bodyTopHalfWidth: CGFloat = 7.25
    /// Half the width of the bottom edge, on the line's center.
    static let bodyBottomHalfWidth: CGFloat = 8.68
    /// The radius of the bottom corners, on the line's center. The top corners are the round
    /// line joins.
    static let bottomCornerRadius: CGFloat = 2.48

    /// The stroked body and handle as one filled outline.
    static func outline() -> Path {
        let center = size.width / 2
        let bodyBottom = size.height - lineWidth / 2
        let handleTop = lineWidth / 2
        let handleCenterY = handleTop + handleRadius
        let topLeft = CGPoint(x: center - bodyTopHalfWidth, y: bodyTop)
        let topRight = CGPoint(x: center + bodyTopHalfWidth, y: bodyTop)
        let bottomRight = CGPoint(x: center + bodyBottomHalfWidth, y: bodyBottom)
        let bottomLeft = CGPoint(x: center - bodyBottomHalfWidth, y: bodyBottom)
        let handleLeft = center - handleRadius
        let handleRight = center + handleRadius

        var path = Path()
        // The body: the straight top edge, the slightly slanted sides and the rounded bottom.
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: bottomCornerRadius)
        path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: bottomCornerRadius)
        path.closeSubpath()
        // The handle: two straight legs rising from the top edge, joined by a half circle.
        path.move(to: CGPoint(x: handleLeft, y: bodyTop))
        path.addLine(to: CGPoint(x: handleLeft, y: handleCenterY))
        path.addArc(
            tangent1End: CGPoint(x: handleLeft, y: handleTop),
            tangent2End: CGPoint(x: center, y: handleTop),
            radius: handleRadius
        )
        path.addArc(
            tangent1End: CGPoint(x: handleRight, y: handleTop),
            tangent2End: CGPoint(x: handleRight, y: handleCenterY),
            radius: handleRadius
        )
        path.addLine(to: CGPoint(x: handleRight, y: bodyTop))
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
    }
}
