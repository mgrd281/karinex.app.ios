import DesignTokens
import SwiftUI

// MARK: - KXSkeleton

/// A rounded loading placeholder with a soft highlight sweeping across it.
///
/// The skeleton fills the size it is offered, so give it a frame:
///
/// ```swift
/// VStack(alignment: .leading, spacing: KXSpacing.xs) {
///     KXSkeleton(cornerRadius: KXRadius.card).aspectRatio(1, contentMode: .fit)
///     KXSkeleton().frame(height: 14)
///     KXSkeleton().frame(width: 96, height: 14)
/// }
/// ```
///
/// The sweep is a continuous, time-based animation (`MotionToken.shimmerDuration` per pass).
/// It is omitted when Reduce Motion is on, and when the `kxSkeletonShimmerEnabled` environment
/// value is `false` (snapshot tests set it with `.kxSkeletonShimmer(false)` so that renders do not
/// depend on the clock).
///
/// Skeletons are hidden from VoiceOver by default so a screen full of placeholders is not read
/// block by block. Mark one placeholder per loading region with `isAccessibilityElement: true`,
/// or use the `kxSkeleton(isActive:)` modifier, which announces loading
/// content once for the whole region.
public struct KXSkeleton: View {
    private let cornerRadius: CGFloat
    private let isAccessibilityElement: Bool

    /// Creates a skeleton placeholder.
    ///
    /// - Parameters:
    ///   - cornerRadius: Corner radius of the placeholder. Defaults to `KXRadius.small`; use
    ///     `KXRadius.card` for image areas of cards.
    ///   - isAccessibilityElement: When `true`, VoiceOver reads the placeholder as
    ///     "Inhalte werden geladen". Defaults to `false` (hidden).
    public init(cornerRadius: CGFloat = KXRadius.small, isAccessibilityElement: Bool = false) {
        self.cornerRadius = cornerRadius
        self.isAccessibilityElement = isAccessibilityElement
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(KXColor.skeleton)
            .overlay {
                KXShimmerHighlight()
            }
            .clipShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("kx.skeleton.loading", bundle: .module))
            .accessibilityHidden(!isAccessibilityElement)
    }
}

// MARK: - Skeleton modifier

extension View {
    /// Turns this view into its own loading placeholder while `isActive` is `true`.
    ///
    /// The content is redacted with `.redacted(reason: .placeholder)` (text and images become
    /// rounded blocks), a highlight sweeps across it, hit testing is disabled and VoiceOver
    /// reads the region once as "Inhalte werden geladen". Render the real layout with sample
    /// or cached data underneath so the placeholder has the final shape.
    ///
    /// The view keeps its identity when `isActive` changes, so state and `.task` modifiers
    /// inside the content are not restarted when loading finishes.
    ///
    /// ```swift
    /// ProductGrid(products: viewModel.products ?? .placeholders)
    ///     .kxSkeleton(isActive: viewModel.products == nil)
    /// ```
    public func kxSkeleton(isActive: Bool) -> some View {
        modifier(KXSkeletonModifier(isActive: isActive))
    }

    /// Enables or disables the skeleton highlight sweep for this view hierarchy.
    ///
    /// The sweep is time-based; snapshot tests disable it for deterministic renders. Reduce
    /// Motion always disables it regardless of this setting.
    public func kxSkeletonShimmer(_ isEnabled: Bool) -> some View {
        environment(\.kxSkeletonShimmerEnabled, isEnabled)
    }
}

extension EnvironmentValues {
    /// Whether ``KXSkeleton`` and the `kxSkeleton(isActive:)` modifier animate their
    /// highlight sweep. Defaults to `true`. Reduce Motion overrides it.
    public var kxSkeletonShimmerEnabled: Bool {
        get { self[KXSkeletonShimmerEnabledKey.self] }
        set { self[KXSkeletonShimmerEnabledKey.self] = newValue }
    }
}

private struct KXSkeletonShimmerEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct KXSkeletonModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .redacted(reason: isActive ? RedactionReasons.placeholder : RedactionReasons())
            .allowsHitTesting(!isActive)
            .accessibilityHidden(isActive)
            .overlay {
                if isActive {
                    ZStack {
                        Color.clear
                        KXShimmerHighlight()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("kx.skeleton.loading", bundle: .module))
                }
            }
    }
}

// MARK: - Shimmer

/// The moving highlight band shared by ``KXSkeleton`` and the `kxSkeleton(isActive:)` modifier.
/// Renders nothing when Reduce Motion is on or the shimmer is disabled in the environment.
private struct KXShimmerHighlight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.kxSkeletonShimmerEnabled) private var isShimmerEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isShimmerEnabled, !reduceMotion {
            TimelineView(.animation) { context in
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let bandWidth = max(width * 0.5, 48)
                    let progress = kxShimmerProgress(at: context.date)
                    LinearGradient(
                        colors: [highlight.opacity(0), highlight, highlight.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: -bandWidth + (width + bandWidth) * progress)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A lighter tone in both appearances: the elevated cream in light mode, a faint cream
    /// veil in dark mode.
    private var highlight: Color {
        colorScheme == .dark ? KXColor.textPrimary.opacity(0.08) : KXColor.surfaceElevated.opacity(0.7)
    }
}

/// Position of the highlight band in `0..<1` for `date`: one pass per `MotionToken.shimmerDuration`.
private func kxShimmerProgress(at date: Date) -> CGFloat {
    let duration = MotionToken.shimmerDuration
    let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
    return CGFloat(elapsed / duration)
}

// MARK: - Previews

private struct KXSkeletonPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.l) {
                HStack(alignment: .top, spacing: KXSpacing.m) {
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: KXSpacing.xs) {
                            KXSkeleton(cornerRadius: KXRadius.card)
                                .aspectRatio(1, contentMode: .fit)
                            KXSkeleton()
                                .frame(width: 64, height: 10)
                            KXSkeleton()
                                .frame(height: 16)
                            KXSkeleton()
                                .frame(width: 80, height: 20)
                        }
                    }
                }
                // Recorded from the live Storefront API on 2026-09-26 (collection "bestseller", DE/DE).
                KXCard {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        Text(verbatim: "Microsoft Office 2024 Professional Plus Download kaufen")
                            .kxFont(.title3)
                            .foregroundStyle(KXColor.textPrimary)
                        KXPriceTag(price: "29,90 €", compareAtPrice: "149,99 €", taxNote: "inkl. MwSt.")
                        KXButton("In den Warenkorb", isFullWidth: true) {}
                    }
                }
                .kxSkeleton(isActive: true)
            }
            .padding(KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXSkeleton, light") {
    KXSkeletonPreviewGallery()
}

#Preview("KXSkeleton, dark") {
    KXSkeletonPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXSkeleton, accessibility size") {
    KXSkeletonPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
