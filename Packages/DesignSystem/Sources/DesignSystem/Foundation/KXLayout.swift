import DesignTokens
import SwiftUI

/// Spacing in points on the 8 pt grid. Mirrors `SpacingToken` as `CGFloat` for SwiftUI.
public enum KXSpacing {
    public static let xxs = CGFloat(SpacingToken.xxs)
    public static let xs = CGFloat(SpacingToken.xs)
    public static let s = CGFloat(SpacingToken.s)
    public static let m = CGFloat(SpacingToken.m)
    public static let l = CGFloat(SpacingToken.l)
    public static let xl = CGFloat(SpacingToken.xl)
    public static let xxl = CGFloat(SpacingToken.xxl)
    public static let xxxl = CGFloat(SpacingToken.xxxl)
    public static let gutter = CGFloat(SpacingToken.gutter)
    public static let minimumTapTarget = CGFloat(SpacingToken.minimumTapTarget)
}

/// Corner radii. Mirrors `RadiusToken` as `CGFloat`.
public enum KXRadius {
    public static let small = CGFloat(RadiusToken.small)
    public static let medium = CGFloat(RadiusToken.medium)
    public static let card = CGFloat(RadiusToken.card)
    public static let large = CGFloat(RadiusToken.large)
}

/// Stroke widths. Mirrors `BorderToken` as `CGFloat`.
public enum KXBorder {
    public static let hairline = CGFloat(BorderToken.hairline)
    public static let regular = CGFloat(BorderToken.regular)
    public static let emphasis = CGFloat(BorderToken.emphasis)
}

extension View {
    /// Fills the available space with the page background, extending under the safe areas.
    public func kxScreenBackground() -> some View {
        background(KXColor.background.ignoresSafeArea())
    }

    /// Applies the standard horizontal screen gutter.
    public func kxGutter() -> some View {
        padding(.horizontal, KXSpacing.gutter)
    }
}
