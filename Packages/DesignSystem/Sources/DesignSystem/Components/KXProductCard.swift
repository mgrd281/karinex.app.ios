import DesignTokens
import Foundation
import SwiftUI
import UIKit

// MARK: - KXProductCardModel

/// The display data of a ``KXProductCard``: plain, already-localized and already-formatted
/// strings plus an image URL.
///
/// Build it from Shopify data only. Prices are `MoneyV2` amounts formatted for the active
/// market ("12,90 €", "CHF 29.00"); never compute or hardcode them.
public struct KXProductCardModel: Identifiable, Hashable, Sendable {
    /// Color treatment of the optional badge.
    public enum BadgeTone: String, CaseIterable, Sendable {
        /// Champagne-gold fill with ink text, e.g. a savings badge.
        case gold
        /// Terracotta fill with white text, e.g. a sale or deal badge. Use sparingly.
        case urgency
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
/// hairline border and an optional badge, the vendor as an eyebrow, the serif title (up to
/// three lines, more at accessibility sizes) and a compact price with the struck-through
/// compare-at price.
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
            Text(badgeText)
                .kxFont(.eyebrow)
                .foregroundStyle(model.badgeTone == .gold ? KXColor.textOnAccent : KXColor.textOnUrgency)
                .lineLimit(2)
                .padding(.horizontal, KXSpacing.xs)
                .padding(.vertical, KXSpacing.xxs)
                .background(model.badgeTone == .gold ? KXColor.accent : KXColor.urgency, in: Capsule(style: .continuous))
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
                    .lineLimit(1)
            }
            Text(model.title)
                .kxFont(.title3)
                .foregroundStyle(KXColor.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            priceRow
                .padding(.top, KXSpacing.xxs)
            if let taxNote = model.taxNote, !taxNote.isEmpty {
                Text(taxNote)
                    .kxFont(.caption)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let availabilityNote = model.availabilityNote, !availabilityNote.isEmpty {
                Text(availabilityNote)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Price and compare-at price on one baseline, stacked when they do not fit.
    private var priceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                priceText
                compareAtText
            }
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                priceText
                compareAtText
            }
        }
    }

    private var priceText: some View {
        Text(model.price)
            .monospacedDigit()
            .kxFont(.headline)
            .foregroundStyle(KXColor.textPrimary)
            .lineLimit(1)
    }

    @ViewBuilder private var compareAtText: some View {
        if let compareAtPrice = model.compareAtPrice, !compareAtPrice.isEmpty {
            Text(compareAtPrice)
                .strikethrough(true, color: KXColor.textTertiary)
                .monospacedDigit()
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: Accessibility

    /// "Title, vendor, Preis 12,90 €, statt 79,99 €, tax note, badge, availability".
    private var accessibilityText: String {
        let priceDescription = if let compareAtPrice = model.compareAtPrice, !compareAtPrice.isEmpty {
            String(
                localized: "kx.product.accessibility.compare \(model.price) \(compareAtPrice)",
                bundle: .module
            )
        } else {
            String(localized: "kx.product.accessibility.price \(model.price)", bundle: .module)
        }
        return [model.title, model.vendor, priceDescription, model.taxNote, model.badge, model.availabilityNote]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

extension KXProductCard where ImageContent == KXProductImage {
    /// Creates a product card that loads `model.imageURL` with `AsyncImage`, showing a
    /// skeleton-colored placeholder while loading and a neutral symbol when there is no image
    /// or loading fails.
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
/// While loading it shows a flat skeleton-colored placeholder; without a URL or after a
/// failure it shows a neutral photo symbol. The image fades in (a cross-fade, also with Reduce
/// Motion). It is decorative and hidden from VoiceOver; the surrounding card describes the
/// product.
///
/// Pass a URL already sized with the Shopify CDN `width` parameter to keep downloads small.
public struct KXProductImage: View {
    private let url: URL?

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
                    } else if phase.error != nil {
                        KXProductImageFallback()
                    } else {
                        KXColor.skeleton
                    }
                }
            } else {
                KXProductImageFallback()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
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
