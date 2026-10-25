import Foundation
import ShopifyKit

// MARK: - CollectionSortOption

/// The sort orders of a collection, in menu order, mapped to the Storefront API.
enum CollectionSortOption: String, CaseIterable, Identifiable, Sendable {
    /// "Empfohlen": the order configured for the collection in the store.
    case recommended
    /// "Bestseller": by sales.
    case bestSelling
    /// "Preis aufsteigend".
    case priceAscending
    /// "Preis absteigend".
    case priceDescending
    /// "Neueste": newest first.
    case newest

    /// Stable identity for `ForEach` and accessibility identifiers.
    var id: String {
        rawValue
    }

    /// The Storefront sort key.
    var sortKey: ProductCollectionSortKeys {
        switch self {
        case .recommended: .collectionDefault
        case .bestSelling: .bestSelling
        case .priceAscending, .priceDescending: .price
        case .newest: .created
        }
    }

    /// Whether the sort order is reversed (high to low, newest first).
    var reverse: Bool {
        switch self {
        case .priceDescending, .newest: true
        case .recommended, .bestSelling, .priceAscending: false
        }
    }

    /// The menu title in the user's language.
    var title: String {
        title(in: CatalogResources.bundle)
    }

    /// The menu title resolved against `bundle`: the module bundle or one of its `.lproj` folders.
    func title(in bundle: Bundle) -> String {
        String(localized: titleKey, bundle: bundle)
    }

    private var titleKey: String.LocalizationValue {
        switch self {
        case .recommended: "catalog.sort.recommended"
        case .bestSelling: "catalog.sort.best_selling"
        case .priceAscending: "catalog.sort.price_ascending"
        case .priceDescending: "catalog.sort.price_descending"
        case .newest: "catalog.sort.newest"
        }
    }
}
