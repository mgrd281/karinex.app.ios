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
        /// Champagne-gold fill with ink text, e.g. a savings badge.
        case gold
        /// Terracotta fill with white text, e.g. a sale or deal badge. Use sparingly.
        case urgency

        /// The badge style that renders this tone.
        var badgeStyle: KXBadge.Style {
            switch self {
            case .gold: .gold
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
    ///   - badgeTone: Badge color treatment. Defaults to ``BadgeTone/gold``.
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
        badgeTone: BadgeTone = .gold,
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

/// A product tile for grids and carousels: a 1:1 image area on the cream surface with a
/// hairline border and an optional ``KXBadge``, the vendor as an eyebrow, the serif title (up to
/// three lines, more at accessibility sizes) and a compact ``KXPriceTag`` with the
/// struck-through compare-at price and the tax note.
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
    private let imageContent: ImageContent

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    /// Creates a product card with custom image content.
    ///
    /// - Parameters:
    ///   - model: The display data.
    ///   - image: The image content. It is proposed the square image area and clipped to it;
    ///     make it resizable (e.g. `.resizable().scaledToFit()`).
    public init(_ model: KXProductCardModel, @ViewBuilder image: () -> ImageContent) {
        self.model = model
        imageContent = image()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            imageArea
            details
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    // MARK: Image

    private var imageArea: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                imageContent
            }
            .background(KXColor.surface)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(KXColor.hairline, lineWidth: 1 / max(displayScale, 1))
            }
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
                .kxFont(.title3)
                .foregroundStyle(KXColor.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            KXPriceTag(price: model.price, compareAtPrice: model.compareAtPrice, taxNote: model.taxNote, size: .compact)
                .padding(.top, KXSpacing.xxs)
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
    /// - Parameter model: The display data.
    public init(_ model: KXProductCardModel) {
        self.init(model) {
            KXProductImage(url: model.imageURL)
        }
    }
}

// MARK: - KXProductImage

/// A remote product image for cards: loads `url` with `AsyncImage` and scales it to fit.
///
/// While loading it shows a ``KXSkeleton``; without a URL or after a failure it shows a neutral
/// photo symbol. The image fades in (a cross-fade, also with Reduce Motion). It is decorative and
/// hidden from VoiceOver; the surrounding card describes the product.
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
                            KXSkeleton(cornerRadius: 0)
                                .onAppear { reloadCount += 1 }
                        } else {
                            KXProductImageFallback()
                        }
                    } else {
                        KXSkeleton(cornerRadius: 0)
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

/// Neutral stand-in when a product has no image or the image could not be loaded.
private struct KXProductImageFallback: View {
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

// Recorded from the live Storefront API on 2026-09-26 (Storefront API 2026-07, DE/DE,
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
