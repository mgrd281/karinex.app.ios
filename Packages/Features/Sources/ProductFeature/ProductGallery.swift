import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductGallery

/// The product images as a paged gallery, edge to edge on the light grey photo tile, the way
/// fashion retail apps present their products. The page dots sit in the bottom leading corner of
/// the photo, the wishlist heart in the bottom trailing corner. Tapping an image opens the
/// full-screen ``ProductImageViewer``.
///
/// The tile is light in both appearances, so its overlays always use the light-appearance ink.
///
/// VoiceOver reads each image with its alt text (or "Produktbild") and its position ("Bild 2
/// von 5"); swiping with three fingers pages through the images.
struct ProductGallery: View {
    /// The images in store order.
    let images: [ShopifyImage]
    /// The visible page.
    @Binding var selection: Int
    /// The wishlist state of the product, or `nil` to hide the heart.
    let isSaved: Bool?
    /// How many customers saved the product, or `nil` to show no number.
    var saveCount: Int?
    /// Adds the product to the wishlist or removes it.
    let onToggleSaved: @MainActor () -> Void
    /// Opens the viewer at an index.
    let onOpen: @MainActor (Int) -> Void

    var body: some View {
        ZStack {
            KXColor.imageBackground
            if images.isEmpty {
                ProductImage(nil)
                    .kxPhotoTile()
            } else {
                TabView(selection: $selection) {
                    ForEach(images.indices, id: \.self) { index in
                        page(at: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            overlays
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("product.gallery")
    }

    private func page(at index: Int) -> some View {
        Button {
            onOpen(index)
        } label: {
            // Each page is its own photo tile: the blend has to happen inside the page, because
            // the paging container is a platform view.
            ProductImage(images[index], isDecorative: true)
                .kxPhotoTile()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.accessibilityLabel(for: images[index])))
        .accessibilityValue(Text("product.gallery.position \(index + 1) \(images.count)", bundle: .module))
        .accessibilityHint(Text("product.gallery.open.hint", bundle: .module))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("product.gallery.image.\(index)")
    }

    /// The page dots and the heart over the photo, in the light appearance of the tile.
    private var overlays: some View {
        HStack(alignment: .center, spacing: KXSpacing.m) {
            if images.count > 1 {
                ProductPageDots(count: images.count, selection: selection)
            }
            Spacer(minLength: 0)
            if let isSaved {
                ProductWishlistButton(isSaved: isSaved, count: saveCount, onToggle: onToggleSaved)
            }
        }
        .padding(.leading, KXSpacing.gutter)
        .padding(.trailing, KXSpacing.xs)
        .padding(.bottom, KXSpacing.xs)
        .environment(\.colorScheme, .light)
    }

    /// The image's alt text, or "Produktbild" when the store has none.
    static func accessibilityLabel(for image: ShopifyImage) -> String {
        let altText = image.altText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return altText.isEmpty ? String(localized: "product.gallery.image", bundle: .module) : altText
    }
}

// MARK: - ProductWishlistButton

/// The heart over the product photo on a white disc, as in fashion retail apps: outlined while
/// the product is not saved, filled once it is.
///
/// Saving animates like the About You app (owner request): the filled heart grows from the
/// center of the outline, springs a little larger and settles, and small hearts burst from it
/// to the upper left and the lower right and fade. Removing it from the Merkliste just shows the
/// outline again. With Reduce Motion the heart only switches.
struct ProductWishlistButton: View {
    let isSaved: Bool
    /// How many customers saved the product, shown beside the heart; `nil` shows none.
    var count: Int?
    let onToggle: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var discSize: CGFloat = 52
    /// Counts the saves that animate; each change plays the animation once.
    @State private var savesToAnimate = 0

    var body: some View {
        Button {
            if !isSaved, !reduceMotion {
                savesToAnimate += 1
            }
            onToggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSaved)
        .accessibilityLabel(isSaved ? Text("product.wishlist.remove", bundle: .module) : Text("product.wishlist.add", bundle: .module))
        .accessibilityValue(count.map { Text(verbatim: $0.formatted()) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isSaved ? .isSelected : [])
        .accessibilityIdentifier("product.wishlist")
    }

    private var label: some View {
        let size = min(discSize, ProductWishlistMetrics.maximumDiscSize)
        return HStack(spacing: KXSpacing.xxs) {
            if let count {
                Text(verbatim: count.formatted())
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textPrimary)
                    .padding(.horizontal, KXSpacing.xs)
                    .padding(.vertical, KXSpacing.xxs)
                    .background(KXColor.surface, in: Capsule())
                    .accessibilityHidden(true)
            }
            disc(size: size)
        }
    }

    private func disc(size: CGFloat) -> some View {
        Circle()
            .fill(KXColor.surface)
            .shadow(
                color: KXColor.scrim.opacity(ProductWishlistMetrics.shadowOpacity),
                radius: ProductWishlistMetrics.shadowRadius,
                x: 0,
                y: ProductWishlistMetrics.shadowOffset
            )
            .frame(width: size, height: size)
            .overlay {
                heart(size: size * ProductWishlistMetrics.heartToDisc)
            }
            .frame(minWidth: KXSpacing.minimumTapTarget, minHeight: KXSpacing.minimumTapTarget)
            .contentShape(Circle())
    }

    /// The outline, the filled heart and the burst, driven by one keyframe animation per save.
    private func heart(size: CGFloat) -> some View {
        KeyframeAnimator(initialValue: ProductHeartMotion.resting, trigger: savesToAnimate) { motion in
            ZStack {
                if !isSaved || motion.fill < 1 {
                    Image(systemName: "heart")
                }
                if isSaved {
                    Image(systemName: "heart.fill")
                        .scaleEffect(max(motion.fill * motion.pop, 0.01))
                }
                ProductHeartBurst(progress: motion.burst, heartSize: size)
            }
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(KXColor.textPrimary)
        } keyframes: { _ in
            KeyframeTrack(\.fill) {
                MoveKeyframe(0)
                CubicKeyframe(1, duration: KXMotion.heartFillDuration)
            }
            KeyframeTrack(\.pop) {
                MoveKeyframe(1)
                LinearKeyframe(1, duration: KXMotion.heartFillDuration)
                SpringKeyframe(KXMotion.heartPopScale, duration: KXMotion.heartPopDuration * 0.4, spring: .snappy)
                SpringKeyframe(1, duration: KXMotion.heartPopDuration * 0.6, spring: .bouncy)
            }
            KeyframeTrack(\.burst) {
                MoveKeyframe(0)
                LinearKeyframe(0, duration: KXMotion.heartFillDuration + KXMotion.heartPopDuration * 0.4)
                LinearKeyframe(1, duration: KXMotion.heartBurstDuration)
            }
        }
    }
}

/// The sizes of the wishlist disc.
private enum ProductWishlistMetrics {
    /// The largest disc at large text sizes, so it never covers the photo.
    static let maximumDiscSize: CGFloat = 64
    /// The heart's size relative to the disc.
    static let heartToDisc: CGFloat = 0.5
    static let shadowOpacity = 0.12
    static let shadowRadius: CGFloat = 4
    static let shadowOffset: CGFloat = 1
}

/// The animated values of the wishlist heart. At rest the heart is full and unscaled and the
/// burst is hidden.
struct ProductHeartMotion {
    /// How far the filled heart has grown from the center, from 0 to 1.
    var fill: CGFloat
    /// The extra scale of the filled heart while it springs.
    var pop: CGFloat
    /// The progress of the burst, from 0 (not started) to 1 (faded).
    var burst: CGFloat

    static let resting = ProductHeartMotion(fill: 1, pop: 1, burst: 0)
}

// MARK: - ProductHeartBurst

/// The small hearts that burst from a saved heart: two to the upper left and two to the lower
/// right. They fly outward, shrink a little and fade as `progress` runs from 0 to 1, and are
/// hidden at 0 and 1. Decorative.
struct ProductHeartBurst: View {
    /// The progress of the burst, from 0 to 1.
    let progress: CGFloat
    /// The size of the heart they burst from.
    let heartSize: CGFloat

    /// One small heart: its direction from the center and its size relative to the heart.
    struct Particle {
        let direction: CGVector
        let scale: CGFloat
    }

    static let particles = [
        Particle(direction: CGVector(dx: -0.78, dy: -0.62), scale: 0.3),
        Particle(direction: CGVector(dx: -0.95, dy: -0.3), scale: 0.16),
        Particle(direction: CGVector(dx: 0.78, dy: 0.62), scale: 0.3),
        Particle(direction: CGVector(dx: 0.95, dy: 0.3), scale: 0.16),
    ]

    var body: some View {
        ZStack {
            ForEach(Self.particles.indices, id: \.self) { index in
                let particle = Self.particles[index]
                let distance = Self.distance(at: progress) * heartSize
                Image(systemName: "heart.fill")
                    .font(.system(size: heartSize * particle.scale))
                    .scaleEffect(Self.scale(at: progress))
                    .offset(x: particle.direction.dx * distance, y: particle.direction.dy * distance)
            }
        }
        .opacity(Self.opacity(at: progress))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// How far the hearts are from the center, in heart sizes: from just outside the heart
    /// outward, fast at first.
    static func distance(at progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        let eased = 1 - (1 - clamped) * (1 - clamped)
        return 0.55 + 0.4 * eased
    }

    /// The hearts grow in during the first fifth of the burst and shrink to two thirds by its end.
    static func scale(at progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return clamped < 0.2 ? 0.4 + 3 * clamped : 1 - (clamped - 0.2) / 0.8 / 3
    }

    /// Fully visible until the middle of the burst, then fading out; hidden at 0 and 1.
    static func opacity(at progress: CGFloat) -> Double {
        guard progress > 0, progress < 1 else { return 0 }
        return progress < 0.5 ? 1 : Double((1 - progress) / 0.5)
    }
}

// MARK: - ProductPageDots

/// Page dots: the current page is a short ink capsule, the others are small light grey dots.
/// Decorative; VoiceOver reads the position on each image instead.
struct ProductPageDots: View {
    /// The number of pages.
    let count: Int
    /// The current page.
    let selection: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 6

    var body: some View {
        HStack(spacing: KXSpacing.xs - KXSpacing.xxs / 2) {
            ForEach(0..<count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == selection ? KXColor.accent : KXColor.divider)
                    .frame(width: index == selection ? dotSize * 4 : dotSize, height: dotSize)
            }
        }
        .animation(KXMotion.animation(.snappy, reduceMotion: reduceMotion), value: selection)
        .accessibilityHidden(true)
    }
}

// MARK: - ProductImageViewer

/// The full-screen image viewer: paged images that zoom with a pinch or a double tap (up to
/// four times) and pan while zoomed, the position ("Bild 2 von 5") and a close button.
///
/// Paging is paused while an image is zoomed, so a pan never switches the image. VoiceOver can
/// zoom with the standard zoom gesture.
struct ProductImageViewer: View {
    /// The images in store order.
    let images: [ShopifyImage]

    @State private var selection: Int
    @State private var isZoomed = false
    @Environment(\.dismiss) private var dismiss

    /// Creates the viewer.
    ///
    /// - Parameters:
    ///   - images: The images.
    ///   - initialIndex: The image shown first.
    init(images: [ShopifyImage], initialIndex: Int) {
        self.images = images
        _selection = State(initialValue: min(max(initialIndex, 0), max(images.count - 1, 0)))
    }

    var body: some View {
        ZStack {
            KXColor.background
                .ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(images.indices, id: \.self) { index in
                    ProductZoomableImage(image: images[index], isZoomed: index == selection ? $isZoomed : .constant(false))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(isZoomed)
            .ignoresSafeArea(edges: .horizontal)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if images.count > 1 {
                ProductPageDots(count: images.count, selection: selection)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, KXSpacing.m)
            }
        }
        .onChange(of: selection) {
            isZoomed = false
        }
        .accessibilityIdentifier("product.viewer")
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: KXSpacing.m) {
            if images.count > 1 {
                Text("product.gallery.position \(selection + 1) \(images.count)", bundle: .module)
                    .monospacedDigit()
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                    .frame(width: KXSpacing.minimumTapTarget, height: KXSpacing.minimumTapTarget)
                    .background(KXColor.surface, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("product.gallery.close", bundle: .module))
            .accessibilityIdentifier("product.viewer.close")
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.vertical, KXSpacing.xs)
    }
}

// MARK: - ProductZoomableImage

/// One image of the viewer with pinch, double-tap and pan zoom.
///
/// The image is rendered at twice the page size and scaled down, so the CDN delivers enough
/// pixels to stay sharp when zoomed.
private struct ProductZoomableImage: View {
    let image: ShopifyImage
    @Binding var isZoomed: Bool

    /// The largest zoom factor.
    private static let maximumScale: CGFloat = 4
    /// The zoom factor of a double tap.
    private static let doubleTapScale: CGFloat = 2.5
    /// How much larger than the page the image is requested.
    private static let resolutionFactor: CGFloat = 2

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ProductImage(image, isDecorative: true)
                .frame(width: size.width * Self.resolutionFactor, height: size.height * Self.resolutionFactor)
                .scaleEffect(scale / Self.resolutionFactor)
                .offset(offset)
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    toggleZoom(in: size)
                }
                .gesture(magnification(in: size))
                .gesture(pan(in: size), including: scale > 1 ? .all : .subviews)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(ProductGallery.accessibilityLabel(for: image)))
                .accessibilityHint(Text("product.gallery.zoom.hint", bundle: .module))
                .accessibilityAddTraits(.isImage)
                .accessibilityZoomAction { action in
                    let target = action.direction == .zoomIn ? min(scale * 1.5, Self.maximumScale) : max(scale / 1.5, 1)
                    setScale(target, in: size, animated: true)
                }
        }
        .clipped()
        .onChange(of: isZoomed) { _, zoomed in
            if !zoomed, scale > 1 {
                setScale(1, in: .zero, animated: false)
            }
        }
    }

    // MARK: Gestures

    private func magnification(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(committedScale * value.magnification, 1), Self.maximumScale)
                offset = clamped(offset, scale: scale, in: size)
            }
            .onEnded { _ in
                setScale(scale, in: size, animated: true)
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = clamped(proposed, scale: scale, in: size)
            }
            .onEnded { _ in
                committedOffset = offset
            }
    }

    // MARK: Zoom

    private func toggleZoom(in size: CGSize) {
        setScale(scale > 1 ? 1 : Self.doubleTapScale, in: size, animated: true)
    }

    /// Sets the zoom; a factor close to 1 snaps back to the unzoomed image.
    private func setScale(_ target: CGFloat, in size: CGSize, animated: Bool) {
        let newScale = target < 1.05 ? 1 : min(target, Self.maximumScale)
        let update = {
            scale = newScale
            committedScale = newScale
            offset = newScale == 1 ? .zero : clamped(offset, scale: newScale, in: size)
            committedOffset = offset
        }
        if animated {
            withAnimation(KXMotion.animation(.standard, reduceMotion: reduceMotion), update)
        } else {
            update()
        }
        isZoomed = newScale > 1
    }

    /// `offset` limited so the zoomed image never leaves the page.
    private func clamped(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let maxX = max((size.width * scale - size.width) / 2, 0)
        let maxY = max((size.height * scale - size.height) / 2, 0)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }
}
