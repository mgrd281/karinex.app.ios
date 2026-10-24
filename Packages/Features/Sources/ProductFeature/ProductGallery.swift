import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductGallery

/// The product images as a paged gallery on a cream panel with gold page dots. Tapping an image
/// opens the full-screen ``ProductImageViewer``.
///
/// VoiceOver reads each image with its alt text (or "Produktbild") and its position ("Bild 2
/// von 5"); swiping with three fingers pages through the images.
struct ProductGallery: View {
    /// The images in store order.
    let images: [ShopifyImage]
    /// The visible page.
    @Binding var selection: Int
    /// Opens the viewer at an index.
    let onOpen: @MainActor (Int) -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: KXSpacing.s) {
            panel
            if images.count > 1 {
                ProductPageDots(count: images.count, selection: selection)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("product.gallery")
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.large, style: .continuous)
        return ZStack {
            KXColor.surface
            if images.isEmpty {
                ProductImage(nil)
                    .padding(KXSpacing.xl)
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
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(KXColor.hairline, lineWidth: 1 / max(displayScale, 1))
        }
    }

    private func page(at index: Int) -> some View {
        Button {
            onOpen(index)
        } label: {
            ProductImage(images[index], isDecorative: true)
                .padding(KXSpacing.l)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.accessibilityLabel(for: images[index])))
        .accessibilityValue(Text("product.gallery.position \(index + 1) \(images.count)", bundle: .module))
        .accessibilityHint(Text("product.gallery.open.hint", bundle: .module))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("product.gallery.image.\(index)")
    }

    /// The image's alt text, or "Produktbild" when the store has none.
    static func accessibilityLabel(for image: ShopifyImage) -> String {
        let altText = image.altText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return altText.isEmpty ? String(localized: "product.gallery.image", bundle: .module) : altText
    }
}

// MARK: - ProductPageDots

/// Page dots below the gallery: the current page is a short gold capsule, the others are small
/// hairline dots. Decorative; VoiceOver reads the position on each image instead.
struct ProductPageDots: View {
    /// The number of pages.
    let count: Int
    /// The current page.
    let selection: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 6

    var body: some View {
        HStack(spacing: KXSpacing.xs) {
            ForEach(0..<count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == selection ? KXColor.accent : KXColor.divider)
                    .frame(width: index == selection ? dotSize * 3 : dotSize, height: dotSize)
            }
        }
        .frame(maxWidth: .infinity)
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
                    .background(KXColor.surfaceElevated, in: Circle())
                    .overlay {
                        Circle().strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
                    }
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
