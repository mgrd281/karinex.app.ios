import Foundation
import ShopifyKit

// MARK: - CollectionNames

/// The names the app shows for the store's collections.
///
/// The store titles some collections for search engines ("SALE – Stark reduzierte Angebote",
/// "Bestseller günstig kaufen", "Visual Studio – Entwicklungstools"). Those get a short name of
/// the app on every screen, in the user's language; every other collection keeps its store title,
/// which arrives in the buyer's content language (docs/STORE_AUDIT.md).
public enum CollectionNames {
    /// The name to show for `collection`.
    public static func title(for collection: CollectionSummary) -> String {
        title(handle: collection.handle, storeTitle: collection.title)
    }

    /// The name to show for the collection with `handle` whose store title is `storeTitle`.
    public static func title(handle: String, storeTitle: String) -> String {
        title(handle: handle, storeTitle: storeTitle, in: CommerceUIResources.bundle)
    }

    /// The name resolved against `bundle`: the module bundle, or one of its `.lproj` folders.
    public static func title(handle: String, storeTitle: String, in bundle: Bundle) -> String {
        if let key = localizedKey(for: handle) {
            return String(localized: key, bundle: bundle)
        }
        return productName(for: handle) ?? storeTitle
    }

    /// The String Catalog key of a collection with a translated short name.
    private static func localizedKey(for handle: String) -> String.LocalizationValue? {
        switch handle {
        case "bestseller": "commerce.collection.bestseller"
        case "sale": "commerce.collection.sale"
        default: nil
        }
    }

    /// The short name of a collection named after a product, the same in every language.
    private static func productName(for handle: String) -> String? {
        switch handle {
        case "visual-studio-entwicklungstools": "Visual Studio"
        case "microsoft-tools": "Microsoft Tools"
        case "microsoft-365-abonnement": "Microsoft 365"
        default: nil
        }
    }
}
