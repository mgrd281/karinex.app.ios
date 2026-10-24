import DesignSystem
import Nuke
import NukeUI
import ShopifyKit
import SwiftUI

// MARK: - ProductImage

/// A remote Shopify image loaded through the KARINEX Nuke pipeline.
///
/// The view fills the space it is offered and requests the image at exactly that width in
/// pixels (rendered width times display scale, see ``KXImagePipeline/pixelWidth(pointWidth:scale:)``)
/// with the WebP `Accept` header, so a product card downloads about 15 to 30 KB instead of the
/// original. While loading it shows a ``KXSkeleton``; without an image or after a failure a
/// neutral photo symbol. The image fades in (a plain cross-fade with Reduce Motion).
///
/// Accessibility: the image is hidden from VoiceOver unless it has alt text and is not marked
/// decorative. Inside a product card pass `isDecorative: true`, because the card describes the
/// product.
///
/// ```swift
/// ProductImage(product.featuredImage, isDecorative: true)
///     .aspectRatio(1, contentMode: .fit)
/// ```
public struct ProductImage: View {
    private let image: ShopifyImage?
    private let contentMode: ContentMode
    private let isDecorative: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a product image.
    ///
    /// - Parameters:
    ///   - image: The Shopify image, or `nil` for the neutral placeholder.
    ///   - contentMode: How the image fills the offered space. Defaults to `.fit`.
    ///   - isDecorative: When `true` the image is always hidden from VoiceOver.
    public init(_ image: ShopifyImage?, contentMode: ContentMode = .fit, isDecorative: Bool = false) {
        self.image = image
        self.contentMode = contentMode
        self.isDecorative = isDecorative
    }

    /// Creates a product image for a plain URL (for example an image inside rich text).
    ///
    /// - Parameters:
    ///   - url: The image URL.
    ///   - altText: The description read by VoiceOver, or `nil` for a decorative image.
    ///   - contentMode: How the image fills the offered space. Defaults to `.fit`.
    public init(url: URL, altText: String?, contentMode: ContentMode = .fit) {
        self.init(ShopifyImage(url: url, altText: altText), contentMode: contentMode, isDecorative: false)
    }

    public var body: some View {
        GeometryReader { proxy in
            content(pointWidth: proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        .modifier(ProductImageAccessibility(altText: accessibleAltText))
    }

    @ViewBuilder
    private func content(pointWidth: CGFloat) -> some View {
        if let image, pointWidth > 0 {
            LazyImage(
                request: KXImagePipeline.request(for: image, pointWidth: pointWidth, scale: displayScale),
                transaction: Transaction(animation: KXMotion.animation(.fade, reduceMotion: reduceMotion))
            ) { state in
                if let loaded = state.image {
                    loaded
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else if state.error != nil {
                    ProductImageFallback()
                } else {
                    KXSkeleton(cornerRadius: 0)
                }
            }
        } else if image == nil {
            ProductImageFallback()
        } else {
            KXSkeleton(cornerRadius: 0)
        }
    }

    /// The alt text VoiceOver reads, or `nil` when the image is hidden.
    private var accessibleAltText: String? {
        guard !isDecorative, let altText = image?.altText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !altText.isEmpty
        else { return nil }
        return altText
    }
}

// MARK: - Accessibility

/// Hides the image from VoiceOver, or exposes it as one image element with its alt text.
private struct ProductImageAccessibility: ViewModifier {
    let altText: String?

    func body(content: Content) -> some View {
        if let altText {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(altText))
                .accessibilityAddTraits(.isImage)
        } else {
            content
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Fallback

/// Neutral stand-in when there is no image or it could not be loaded.
private struct ProductImageFallback: View {
    var body: some View {
        ZStack {
            KXColor.surface
            Image(systemName: "photo")
                .kxFont(.title2)
                .foregroundStyle(KXColor.iconSecondary)
        }
    }
}

// MARK: - Previews

// Recorded from the live Storefront API on 2026-09-26 (collection "bestseller").
private let productImagePreviewImage = ShopifyImage(
    url: URL(string: "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Office_2024_Professional_Plus.webp") ?? URL(
        fileURLWithPath: "/"
    ),
    altText: "Microsoft Office 2024 Professional Plus"
)

#Preview("ProductImage") {
    VStack(spacing: KXSpacing.m) {
        ProductImage(productImagePreviewImage)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 180)
        ProductImage(nil)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 180)
    }
    .padding(KXSpacing.gutter)
    .kxScreenBackground()
}
