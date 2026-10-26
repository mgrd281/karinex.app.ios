/// Spacing scale on the 8 pt grid (with a 4 pt half step for tight inline gaps).
public enum SpacingToken {
    /// 4 pt
    public static let xxs: Double = 4
    /// 8 pt
    public static let xs: Double = 8
    /// 12 pt
    public static let s: Double = 12
    /// 16 pt, the standard screen gutter.
    public static let m: Double = 16
    /// 24 pt
    public static let l: Double = 24
    /// 32 pt
    public static let xl: Double = 32
    /// 48 pt
    public static let xxl: Double = 48
    /// 64 pt
    public static let xxxl: Double = 64

    /// Horizontal screen margin.
    public static let gutter: Double = m
    /// Minimum hit target edge length (Apple HIG).
    public static let minimumTapTarget: Double = 44
}

/// Corner radii. Buttons, chips and badges are capsules; product photos have square corners.
public enum RadiusToken {
    /// Small tags and thumbnails.
    public static let small: Double = 6
    /// Text fields and inline panels.
    public static let medium: Double = 12
    /// Cards and panels (`KXCard`).
    public static let card: Double = 12
    /// Hero panels and sheets.
    public static let large: Double = 20
    /// Product photos: square, edge to edge, as in fashion retail apps.
    public static let image: Double = 0
}

/// Stroke widths.
public enum BorderToken {
    /// Hairline rule. Components convert it to one physical pixel where appropriate.
    public static let hairline: Double = 0.5
    /// Standard outline (secondary button, selected chip).
    public static let regular: Double = 1
    /// Emphasis outline (selected variant, active tab underline).
    public static let emphasis: Double = 2
}

/// Motion timings. Springs stay within the 0.25 to 0.35 s response range of the brand spec.
public enum MotionToken {
    /// Response of the standard spring used for most state changes.
    public static let springResponse: Double = 0.3
    /// Damping of the standard spring.
    public static let springDamping: Double = 0.86
    /// Response of the snappy spring used for small controls (toggles, accordions).
    public static let snappyResponse: Double = 0.25
    /// Response of the gentle spring used for large surfaces (hero, sheets).
    public static let gentleResponse: Double = 0.35
    /// Duration of simple cross-fades.
    public static let fadeDuration: Double = 0.2
    /// Duration of the slow cross-fade when a large surface swaps its content, e.g. the
    /// category showcase of the Start tab moving on to the next category.
    public static let swapDuration: Double = 0.45
    /// How blurred content is at the start and the end of a swap.
    public static let swapBlurRadius: Double = 8
    /// How long a cycling showcase shows one item before it moves on to the next.
    public static let cycleDwellDuration: Double = 5
    /// How far a pressed card or tile shrinks.
    public static let pressedScale: Double = 0.97
    /// The opacity of a pressed card or tile when Reduce Motion is on (it dims instead).
    public static let pressedOpacity: Double = 0.7
    /// Duration of one skeleton shimmer sweep.
    public static let shimmerDuration: Double = 1.4
    /// How long the logo of the launch intro stays still before it zooms.
    public static let launchHoldDuration: Double = 0.4
    /// Duration of the launch intro's zoom into the logo.
    public static let launchZoomDuration: Double = 0.55
    /// How far the logo grows during the launch intro.
    public static let launchZoomScale: Double = 12
    /// How long the wishlist heart takes to fill from its center when a product is saved.
    public static let heartFillDuration: Double = 0.13
    /// How long the filled heart takes to grow to ``heartPopScale`` and settle again.
    public static let heartPopDuration: Double = 0.3
    /// How far the filled heart grows before it settles.
    public static let heartPopScale: Double = 1.12
    /// How long the small hearts take to burst from the saved heart and fade.
    public static let heartBurstDuration: Double = 0.45
}
