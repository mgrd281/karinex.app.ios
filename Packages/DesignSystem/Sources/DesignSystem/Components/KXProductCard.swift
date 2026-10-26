import Foundation
import SwiftUI

// MARK: - KXProductCardModel

/// The display data of a ``KXProductCard``: plain, already-localized and already-formatted
/// strings plus an image URL.
///
/// Build it from Shopify data only. Prices are `MoneyV2` amounts formatted for the active
/// market ("12,90 €", "CHF 29.00"); never compute or hardcode them.
public struct KXProductCardModel: Identifiable, Hashable, Sendable {
    /// Color treatment of the optional badge, rendered as the ``KXBadge`` style of the same name.
    public enum BadgeTone: String, CaseIterable, Sendable {
        /// Ink fill with white text, e.g. "Bestseller".
        case accent
        /// Sale red fill with white text, e.g. a sale or deal badge.
        case urgency

        /// The badge style that renders this tone.
        var badgeStyle: KXBadge.Style {
            switch self {
            case .accent: .accent
            case .urgency: .urgency
            }
        }
    }

    /// Stable identity, typically the product GID.
    public let id: String
    /// The product title exactly as returned by the store.
    public let title: String
    /// Optional vendor shown as an eyebrow above the title.
    public let vendor: String?
    /// The formatted current price.
    public let price: String
    /// The formatted former price, shown struck through. `nil` when the store has none.
    public let compareAtPrice: String?
    /// Optional already-localized tax note shown below the price, e.g. "inkl. MwSt.".
    public let taxNote: String?
    /// Optional already-localized badge text shown over the image, e.g. "Bestseller".
    public let badge: String?
    /// Color treatment of the badge.
    public let badgeTone: BadgeTone
    /// The product image URL, ideally already sized for the card with the Shopify CDN `width`
    /// parameter. `nil` shows a neutral image placeholder.
    public let imageURL: URL?
    /// Optional already-localized availability note, e.g. when the product cannot be bought.
    public let availabilityNote: String?

    /// Creates a product card model.
    ///
    /// - Parameters:
    ///   - id: Stable identity, typically the product GID.
    ///   - title: The product title from the store.
    ///   - vendor: Optional vendor eyebrow.
    ///   - price: The formatted current price.
    ///   - compareAtPrice: The formatted former price, or `nil`.
    ///   - taxNote: Optional tax note, only for markets whose prices include tax.
    ///   - badge: Optional badge text.
    ///   - badgeTone: Badge color treatment. Defaults to ``BadgeTone/accent``.
    ///   - imageURL: The product image URL, or `nil`.
    ///   - availabilityNote: Optional availability note.
    public init(
        id: String,
        title: String,
        vendor: String? = nil,
        price: String,
        compareAtPrice: String? = nil,
        taxNote: String? = nil,
        badge: String? = nil,
        badgeTone: BadgeTone = .accent,
        imageURL: URL? = nil,
        availabilityNote: String? = nil
    ) {
        self.id = id
        self.title = title
        self.vendor = vendor
        self.price = price
        self.compareAtPrice = compareAtPrice
        self.taxNote = taxNote
        self.badge = badge
        self.badgeTone = badgeTone
        self.imageURL = imageURL
        self.availabilityNote = availabilityNote
    }
}

// MARK: - KXProductCard

/// A product tile for grids and carousels, in the style of fashion retail apps: a photo tile
/// (square, or portrait with `imageAspectRatio`) edge to edge on the light grey photo background
/// (``SwiftUICore/View/kxPhotoTile()``)
/// with an optional ``KXBadge`` in the corner, then the vendor as an eyebrow, the title in
/// regular weight (up to three lines with the space reserved, more at accessibility sizes) and
/// a compact ``KXPriceTag`` with the sale red price, the struck-through compare-at price and
/// the tax note. No card, border or shadow.
///
/// The card fills the width it is offered; give it a width through the grid or carousel. It
/// is not a button itself: wrap it in a `NavigationLink` or `Button`, which then supplies the
/// button trait.
///
/// VoiceOver reads the whole card as one element, e.g. "Windows 11 Pro kaufen, Preis 12,90 €,
/// statt 79,99 €, inkl. MwSt., Bestseller". The image is decorative.
///
/// Use the convenience initializer to load `model.imageURL` with `AsyncImage`, or pass your own
/// image view (for example a cached image, or a local placeholder in snapshot tests):
///
/// ```swift
/// KXProductCard(model)
/// KXProductCard(model) { Image(uiImage: cachedImage).resizable().scaledToFit() }
/// ```
public struct KXProductCard<ImageContent: View>: View {
    private let model: KXProductCardModel
    private let imageAspectRatio: CGFloat
    private let imageContent: ImageContent

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a product card with custom image content.
    ///
    /// - Parameters:
    ///   - model: The display data.
    ///   - imageAspectRatio: The width of the photo tile divided by its height: 1 (the default)
    ///     for a square tile, `3.0 / 4.0` for a portrait tile.
    ///   - image: The image content. It is proposed the image area and clipped to it; make it
    ///     resizable (e.g. `.resizable().scaledToFit()`).
    public init(_ model: KXProductCardModel, imageAspectRatio: CGFloat = 1, @ViewBuilder image: () -> ImageContent) {
        self.model = model
        self.imageAspectRatio = imageAspectRatio
        imageContent = image()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            imageArea
            details
                .padding(.horizontal, KXSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    // MARK: Image

    private var imageArea: some View {
        Color.clear
            .aspectRatio(imageAspectRatio, contentMode: .fit)
            .overlay {
                imageContent
            }
            .kxPhotoTile()
            .clipShape(RoundedRectangle(cornerRadius: KXRadius.image, style: .continuous))
            .overlay(alignment: .topLeading) {
                badge
            }
    }

    @ViewBuilder private var badge: some View {
        if let badgeText = model.badge, !badgeText.isEmpty {
            KXBadge(badgeText, style: model.badgeTone.badgeStyle)
                .lineLimit(2)
                .padding(KXSpacing.xs)
        }
    }

    // MARK: Text

    private var details: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            if let vendor = model.vendor, !vendor.isEmpty {
                Text(vendor)
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(model.title)
                .kxFont(.subheadline)
                .foregroundStyle(KXColor.textPrimary)
                .lineLimit(
                    dynamicTypeSize.isAccessibilitySize
                        ? KXProductCardMetrics.accessibilityTitleLines
                        : KXProductCardMetrics.reservedTitleLines,
                    reservesSpace: !dynamicTypeSize.isAccessibilitySize
                )
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            KXPriceTag(price: model.price, compareAtPrice: model.compareAtPrice, taxNote: model.taxNote, size: .compact)
                .padding(.top, KXSpacing.xxs / 2)
            if let availabilityNote = model.availabilityNote, !availabilityNote.isEmpty {
                Text(availabilityNote)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Accessibility

    /// "Title, vendor, Preis 12,90 €, statt 79,99 €, tax note, badge, availability".
    private var accessibilityText: String {
        let priceDescription = KXPriceTag.spokenPrice(model.price, compareAtPrice: model.compareAtPrice)
        return [model.title, model.vendor, priceDescription, model.taxNote, model.badge, model.availabilityNote]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

extension KXProductCard where ImageContent == KXProductImage {
    /// Creates a product card that loads `model.imageURL` with `AsyncImage`, showing a
    /// ``KXSkeleton`` while loading and a neutral symbol when there is no image or loading fails.
    ///
    /// - Parameters:
    ///   - model: The display data.
    ///   - imageAspectRatio: The width of the photo tile divided by its height (1, square, by
    ///     default).
    public init(_ model: KXProductCardModel, imageAspectRatio: CGFloat = 1) {
        self.init(model, imageAspectRatio: imageAspectRatio) {
            KXProductImage(url: model.imageURL)
        }
    }
}

// MARK: - KXProductCardMetrics

/// The title lines of a ``KXProductCard``, shared with its ``KXProductCardSkeleton``.
enum KXProductCardMetrics {
    /// The title lines whose space a card reserves, so the prices of a row line up. Three show
    /// the full name of nearly every product.
    static let reservedTitleLines = 3
    /// The most title lines at accessibility text sizes, where no space is reserved.
    static let accessibilityTitleLines = 6
}

// MARK: - KXProductCardSkeleton

/// The placeholder of a ``KXProductCard`` while its product loads: a skeleton photo tile, then
/// skeleton lines in exactly the space the card's title, price and tax note take, so a row
/// keeps its height when the cards arrive. Hidden from VoiceOver; the row around it announces
/// the loading once.
///
/// ```swift
/// KXProductCardSkeleton(imageAspectRatio: 3.0 / 4.0)
///     .frame(width: cardWidth)
/// ```
public struct KXProductCardSkeleton: View {
    /// The lengths of the title lines, as parts of the card width.
    private static let titleLineLengths: [CGFloat] = [1, 0.8, 0.5]
    /// The lengths of the price line and the tax note line.
    private static let priceLineLengths: [CGFloat] = [0.45, 0.3]

    private let imageAspectRatio: CGFloat

    /// Creates the placeholder.
    ///
    /// - Parameter imageAspectRatio: The width of the photo tile divided by its height, as
    ///   given to the cards it stands in for (1, square, by default).
    public init(imageAspectRatio: CGFloat = 1) {
        self.imageAspectRatio = imageAspectRatio
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            KXSkeleton(cornerRadius: KXRadius.image)
                .aspectRatio(imageAspectRatio, contentMode: .fit)
            // Invisible text in the card's styles reserves the card's exact height; the lines
            // are drawn over it.
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(verbatim: " ")
                    .kxFont(.subheadline)
                    .lineLimit(KXProductCardMetrics.reservedTitleLines, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hidden()
                    .overlay {
                        lines(Self.titleLineLengths)
                    }
                KXPriceTag(price: " ", taxNote: " ", size: .compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hidden()
                    .overlay {
                        lines(Self.priceLineLengths)
                    }
                    .padding(.top, KXSpacing.xxs / 2)
            }
            .padding(.horizontal, KXSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// One skeleton line per equal slot of the area, each the given part of its width.
    private func lines(_ lengths: [CGFloat]) -> some View {
        GeometryReader { proxy in
            let slot = proxy.size.height / CGFloat(max(lengths.count, 1))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lengths.indices, id: \.self) { index in
                    KXSkeleton()
                        .frame(width: proxy.size.width * lengths[index], height: slot * 0.6)
                        .frame(height: slot)
                }
            }
        }
    }
}

// MARK: - KXProductImage

/// A remote product image for cards: loads `url` with `AsyncImage` and scales it to fit.
///
/// While loading it shows a ``KXSkeleton`` (inside a ``SwiftUICore/View/kxPhotoTile()`` only the
/// tile); without a URL or after a failure it shows a neutral photo symbol. The image fades in (a
/// cross-fade, also with Reduce Motion). It is decorative and hidden from VoiceOver; the
/// surrounding card describes the product.
///
/// Lazy grids and lists cancel the downloads of cells that scroll away, and `AsyncImage` then
/// keeps reporting the cancellation as a failure. A cancelled load therefore keeps the skeleton
/// and starts again as soon as the placeholder is back on screen (up to
/// ``maximumReloadCount`` times), instead of showing the failure symbol for an image that exists.
///
/// Pass a URL already sized with the Shopify CDN `width` parameter to keep downloads small.
public struct KXProductImage: View {
    /// How often a cancelled download is started again before the failure symbol is shown.
    public static let maximumReloadCount = 3

    private let url: URL?

    /// Incremented to restart a cancelled download; it is the identity of the `AsyncImage`.
    @State private var reloadCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a remote product image.
    ///
    /// - Parameter url: The image URL, or `nil` to show the neutral placeholder.
    public init(url: URL?) {
        self.url = url
    }

    public var body: some View {
        Group {
            if let url {
                AsyncImage(
                    url: url,
                    transaction: Transaction(animation: KXMotion.animation(.fade, reduceMotion: reduceMotion))
                ) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else if let error = phase.error {
                        if Self.isCancellation(error), reloadCount < Self.maximumReloadCount {
                            KXProductImageLoadingPlaceholder()
                                .onAppear { reloadCount += 1 }
                        } else {
                            KXProductImageFallback()
                        }
                    } else {
                        KXProductImageLoadingPlaceholder()
                    }
                }
                .id(reloadCount)
            } else {
                KXProductImageFallback()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: url) {
            reloadCount = 0
        }
        .accessibilityHidden(true)
    }

    /// Whether `error` only reports that the download was cancelled (the view left the screen),
    /// not that the image is unavailable.
    nonisolated static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }
}

/// The placeholder while an image loads: a skeleton, or nothing inside a photo tile, whose
/// plain light grey already reads as a placeholder.
private struct KXProductImageLoadingPlaceholder: View {
    @Environment(\.kxIsInPhotoTile) private var isInPhotoTile

    var body: some View {
        if isInPhotoTile {
            Color.clear
        } else {
            KXSkeleton(cornerRadius: 0)
        }
    }
}

/// Neutral stand-in when a product has no image or the image could not be loaded.
private struct KXProductImageFallback: View {
    @Environment(\.kxIsInPhotoTile) private var isInPhotoTile

    var body: some View {
        ZStack {
            if !isInPhotoTile {
                KXColor.surface
            }
            Image(systemName: "photo")
                .kxFont(.title2)
                .foregroundStyle(isInPhotoTile ? KXColor.imageIcon : KXColor.iconSecondary)
        }
    }
}

// MARK: - Previews

// Recorded from the live Storefront API on 2026-09-26 (Storefront API 2026-10, DE/DE,
// collection "bestseller"). Titles are store content and rendered as-is, including their
// dashes (written as \u{2013} escapes). Prices are the MoneyV2 amounts formatted for de_DE.
private let kxProductCardPreviewModels: [KXProductCardModel] = [
    KXProductCardModel(
        id: "office-2024-professional-plus",
        title: "Microsoft Office 2024 Professional Plus Download kaufen",
        price: "29,90 €",
        compareAtPrice: "149,99 €",
        taxNote: "inkl. MwSt.",
        badge: "Bestseller",
        imageURL: URL(string: "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Office_2024_Professional_Plus.webp")
    ),
    KXProductCardModel(
        id: "windows-11-pro",
        title: "Windows 11 Pro kaufen \u{2013} Dauerlizenz 1 PC, Download",
        price: "12,90 €",
        compareAtPrice: "79,99 €",
        taxNote: "inkl. MwSt.",
        imageURL: URL(
            string: "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Windows-11-Pro-Key-Download-kaufen..webp?v=1787442708"
        )
    ),
    KXProductCardModel(
        id: "office-2024-standard-mac",
        title: "Microsoft Office 2024 Standard für Mac Key \u{2013} Sofort Download",
        price: "13,90 €",
        compareAtPrice: "39,99 €",
        taxNote: "inkl. MwSt."
    ),
]

private struct KXProductCardPreviewGallery: View {
    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: KXSpacing.m, alignment: .top), GridItem(.flexible(), alignment: .top)],
                spacing: KXSpacing.l
            ) {
                ForEach(kxProductCardPreviewModels) { model in
                    KXProductCard(model)
                }
            }
            .padding(KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXProductCard, light") {
    KXProductCardPreviewGallery()
}

#Preview("KXProductCard, dark") {
    KXProductCardPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXProductCard, accessibility size") {
    KXProductCardPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}

#Preview("KXProductCard, portrait with its skeleton") {
    HStack(alignment: .top, spacing: KXSpacing.xs) {
        KXProductCard(kxProductCardPreviewModels[1], imageAspectRatio: 3.0 / 4.0)
            .frame(width: 184)
        KXProductCardSkeleton(imageAspectRatio: 3.0 / 4.0)
            .frame(width: 184)
    }
    .padding(KXSpacing.gutter)
    .kxScreenBackground()
}
