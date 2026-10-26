import DesignSystem
import Foundation
import ShopifyKit
import SwiftUI

// MARK: - ProductCardHighlight

/// An editorial badge the caller may put on a product card. The card never decides this
/// itself: "Bestseller" is only allowed in the row of the `bestseller` collection.
public enum ProductCardHighlight: Sendable, Hashable {
    /// No editorial badge.
    case none
    /// "Bestseller", for cards in the bestseller collection row.
    case bestseller
}

// MARK: - ProductCardView

/// A ``KXProductCard`` for a Shopify ``ShopifyKit/ProductSummary``: title, price, compare-at
/// price and the market's tax note from ``PriceDisplay``, the image through ``ProductImage``.
///
/// Badges: when the product is reduced (compare-at price above the price) a red badge with the
/// reduction ("-80 %"), or "Angebot" when it is below 1 %, and the price in sale red; otherwise
/// the caller's ``ProductCardHighlight`` in ink. No ratings, review counts or invented claims.
/// A product that cannot be bought shows "Derzeit nicht verfügbar".
///
/// The card is not a button; wrap it in a `Button` or `NavigationLink`.
public struct ProductCardView: View {
    private let product: ProductSummary
    private let highlight: ProductCardHighlight
    private let imageAspectRatio: CGFloat

    @Environment(\.locale) private var locale
    @Environment(\.commerceCountry) private var country

    /// Creates a product card.
    ///
    /// - Parameters:
    ///   - product: The product from Shopify.
    ///   - highlight: The editorial badge decided by the caller. Defaults to none.
    ///   - imageAspectRatio: The width of the photo tile divided by its height (1, square, by
    ///     default).
    public init(_ product: ProductSummary, highlight: ProductCardHighlight = .none, imageAspectRatio: CGFloat = 1) {
        self.product = product
        self.highlight = highlight
        self.imageAspectRatio = imageAspectRatio
    }

    public var body: some View {
        let model = Self.model(for: product, highlight: highlight, country: country, locale: locale)
        KXProductCard(model, imageAspectRatio: imageAspectRatio) {
            ProductImage(product.featuredImage, isDecorative: true)
        }
    }

    /// The card model for `product`: the strings of ``PriceDisplay`` and the badge rules above.
    public static func model(
        for product: ProductSummary,
        highlight: ProductCardHighlight,
        country: CountryCode,
        locale: Locale
    ) -> KXProductCardModel {
        let display = PriceDisplay(product: product, country: country, locale: locale)
        let badge: String? = if display.compareAtPrice != nil {
            display.savingsText ?? String(localized: "commerce.product.badge.sale", bundle: .module)
        } else if highlight == .bestseller {
            String(localized: "commerce.product.badge.bestseller", bundle: .module)
        } else {
            nil
        }
        return KXProductCardModel(
            id: product.id.rawValue,
            title: product.title,
            price: display.price,
            compareAtPrice: display.compareAtPrice,
            taxNote: display.taxNoteText,
            badge: badge,
            badgeTone: display.compareAtPrice != nil ? .urgency : .accent,
            imageURL: product.featuredImage?.url,
            availabilityNote: product.availableForSale
                ? nil
                : String(localized: "commerce.product.unavailable", bundle: .module)
        )
    }
}
