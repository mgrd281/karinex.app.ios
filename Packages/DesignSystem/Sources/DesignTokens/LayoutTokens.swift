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

/// Corner radii.
public enum RadiusToken {
    /// Badges, chips and small tags.
    public static let small: Double = 8
    /// Buttons and text fields.
    public static let medium: Double = 14
    /// Cards and panels (`KXCard`).
    public static let card: Double = 18
    /// Hero panels and sheets.
    public static let large: Double = 24
}

/// Stroke widths.
public enum BorderToken {
    /// Hairline rule. Components convert it to one physical pixel where appropriate.
    public static let hairline: Double = 0.5
    /// Standard outline (secondary button, gold inset ring).
    public static let regular: Double = 1
    /// Emphasis rule (section header gold rule, key card accent line).
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
    /// Duration of one skeleton shimmer sweep.
    public static let shimmerDuration: Double = 1.4
    /// Maximum parallax offset of the hero image in points.
    public static let heroParallax: Double = 24
}
