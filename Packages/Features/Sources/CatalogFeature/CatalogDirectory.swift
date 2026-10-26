import CommerceUI
import Foundation
import ShopifyKit

// MARK: - CatalogDirectory

/// What the Shop tab shows and in which order, with the live store handles
/// (docs/STORE_AUDIT.md):
///
/// - ``highlightHandles``: the bestsellers and the sale as two large cards on top.
/// - ``categoryHandles``: the product families as rows with a photo and a short line.
/// - ``versionHandles``: the single versions (Windows 11, Office 2024, ...) as a shelf of cards.
/// - Every other collection of the store, in the store's order (by title), as a list.
///
/// `all` (the whole range) and `digital-goods-vat-tax` (a helper collection for tax settings)
/// are never listed, and a handle the store does not have is left out.
enum CatalogDirectory {
    /// The collections of the two large cards on top, in display order.
    static let highlightHandles = ["bestseller", "sale"]

    /// The product families, in display order.
    static let categoryHandles = [
        "windows",
        "microsoft-office",
        "microsoft-office-fur-mac",
        "microsoft-365-abonnement",
        "windows-server",
        "visual-studio-entwicklungstools",
        "microsoft-tools",
    ]

    /// The single product versions, in display order: newest first within each family.
    static let versionHandles = [
        "windows-11",
        "windows-10",
        "microsoft-office-2024",
        "microsoft-office-2021",
        "microsoft-office-2019",
        "microsoft-office-2024-fur-mac",
        "microsoft-office-2021-fur-mac",
        "windows-server-2025",
        "windows-server-2022",
        "windows-server-2019",
        "microsoft-project",
        "microsoft-visio",
        "microsoft-sql-server",
    ]

    /// Handles that are never listed.
    static let excludedHandles: Set<String> = ["all", "digital-goods-vat-tax"]

    /// The number of collections requested from the store. The live store has about 30, and
    /// each costs about 6 of the 1000 a tokenless request may cost (``CollectionsQuery``).
    static let requestLimit = 60

    /// The store's sale collection, whose card is sale red.
    static let saleHandle = "sale"

    /// Whether `handle` is the sale collection.
    static func isSale(_ handle: String) -> Bool {
        handle == saleHandle
    }

    /// The listed collections in the sections of the Shop tab. Duplicate handles are listed
    /// once.
    static func arrange(_ collections: [CollectionSummary]) -> CatalogSections {
        var seen = Set<String>()
        let listed = collections.filter { collection in
            !excludedHandles.contains(collection.handle) && seen.insert(collection.handle).inserted
        }
        let byHandle = Dictionary(listed.map { ($0.handle, $0) }, uniquingKeysWith: { first, _ in first })
        let placed = Set(highlightHandles + categoryHandles + versionHandles)
        return CatalogSections(
            highlights: highlightHandles.compactMap { byHandle[$0] },
            categories: categoryHandles.compactMap { byHandle[$0] },
            versions: versionHandles.compactMap { byHandle[$0] },
            more: listed.filter { !placed.contains($0.handle) }
        )
    }

    /// The name of a version card: the collection's name without the leading "Microsoft " that
    /// every version shares, e.g. "Office 2024", "Windows Server 2025" or "Project".
    static func versionName(for collection: CollectionSummary) -> String {
        let name = CollectionNames.title(for: collection)
        let prefix = "Microsoft "
        guard name.hasPrefix(prefix), name.count > prefix.count else { return name }
        return String(name.dropFirst(prefix.count))
    }

    /// The short line below a family's name, e.g. "Betriebssysteme"; `nil` for every other
    /// collection.
    static func detail(for handle: String) -> String? {
        detail(for: handle, in: CatalogResources.bundle)
    }

    /// The line resolved against `bundle`: the module bundle, or one of its `.lproj` folders.
    static func detail(for handle: String, in bundle: Bundle) -> String? {
        detailKey(for: handle).map { String(localized: $0, bundle: bundle) }
    }

    /// What a highlight card invites to, e.g. "Jetzt entdecken"; `nil` for other collections.
    static func highlightAction(for handle: String) -> String? {
        highlightAction(for: handle, in: CatalogResources.bundle)
    }

    /// The invitation resolved against `bundle`.
    static func highlightAction(for handle: String, in bundle: Bundle) -> String? {
        highlightActionKey(for: handle).map { String(localized: $0, bundle: bundle) }
    }

    private static func detailKey(for handle: String) -> String.LocalizationValue? {
        switch handle {
        case "windows": "catalog.category.windows.detail"
        case "microsoft-office": "catalog.category.office.detail"
        case "microsoft-office-fur-mac": "catalog.category.mac.detail"
        case "microsoft-365-abonnement": "catalog.category.microsoft365.detail"
        case "windows-server": "catalog.category.server.detail"
        case "visual-studio-entwicklungstools": "catalog.category.development.detail"
        case "microsoft-tools": "catalog.category.tools.detail"
        default: nil
        }
    }

    private static func highlightActionKey(for handle: String) -> String.LocalizationValue? {
        switch handle {
        case "bestseller": "catalog.highlight.bestseller.action"
        case saleHandle: "catalog.highlight.sale.action"
        default: nil
        }
    }
}

// MARK: - CatalogSections

/// The collections of the Shop tab, section by section.
struct CatalogSections: Sendable, Hashable {
    /// The bestsellers and the sale, as large cards.
    let highlights: [CollectionSummary]
    /// The product families, as rows with a photo.
    let categories: [CollectionSummary]
    /// The single versions, as a shelf of cards.
    let versions: [CollectionSummary]
    /// Every other listed collection, in the store's order.
    let more: [CollectionSummary]

    /// Whether nothing is listed.
    var isEmpty: Bool {
        highlights.isEmpty && categories.isEmpty && versions.isEmpty && more.isEmpty
    }
}
