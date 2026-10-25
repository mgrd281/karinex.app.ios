import Foundation
import ShopifyKit

// MARK: - CatalogDirectory

/// Which collections the Shop tab lists and in which order.
///
/// The curated collections (docs/STORE_AUDIT.md) come first, in the order below, followed by
/// every other collection of the store in the store's order (by title). `all` (the whole range)
/// and `digital-goods-vat-tax` (a helper collection for tax settings) are never listed.
enum CatalogDirectory {
    /// The curated collection handles, in display order.
    static let curatedHandles = [
        "windows",
        "microsoft-office",
        "windows-server",
        "visual-studio-entwicklungstools",
        "bestseller",
        "sale",
        "microsoft-tools",
        "microsoft-365-abonnement",
        "microsoft-office-fur-mac",
    ]

    /// Handles that are never listed.
    static let excludedHandles: Set<String> = ["all", "digital-goods-vat-tax"]

    /// The number of collections requested from the store (the live store has about 30).
    static let requestLimit = 100

    /// The store's sale collection, whose tile is drawn in sale red.
    static let saleHandle = "sale"

    /// Whether `handle` is the sale collection.
    static func isSale(_ handle: String) -> Bool {
        handle == saleHandle
    }

    /// The listed collections split into the curated ones (in curated order) and the rest (in
    /// the given order). Duplicate handles are listed once.
    static func arrange(_ collections: [CollectionSummary]) -> CatalogSections {
        var seen = Set<String>()
        let listed = collections.filter { collection in
            !excludedHandles.contains(collection.handle) && seen.insert(collection.handle).inserted
        }
        let byHandle = Dictionary(listed.map { ($0.handle, $0) }, uniquingKeysWith: { first, _ in first })
        let featured = curatedHandles.compactMap { byHandle[$0] }
        let curated = Set(curatedHandles)
        let more = listed.filter { !curated.contains($0.handle) }
        return CatalogSections(featured: featured, more: more)
    }

    /// The decorative SF Symbol of a collection tile.
    static func systemImage(for handle: String) -> String {
        switch handle {
        case "windows", "windows-10", "windows-11", "windows-7", "windows-8": "macwindow"
        case "microsoft-office", "microsoft-office-2019", "microsoft-office-2021", "microsoft-office-2024": "doc.richtext"
        case "windows-server": "server.rack"
        case "visual-studio-entwicklungstools": "chevron.left.forwardslash.chevron.right"
        case "bestseller": "sparkles"
        case saleHandle: "tag"
        case "microsoft-tools", "microsoft-project", "microsoft-visio", "microsoft-sql-server": "wrench.and.screwdriver"
        case "microsoft-365-abonnement": "icloud"
        case "microsoft-office-fur-mac": "laptopcomputer"
        default:
            if handle.hasPrefix("windows-server") {
                "server.rack"
            } else if handle.hasSuffix("fur-mac") {
                "laptopcomputer"
            } else {
                "square.grid.2x2"
            }
        }
    }
}

// MARK: - CatalogSections

/// The collections of the Shop tab: the curated ones as large tiles, the rest as a list.
struct CatalogSections: Sendable, Hashable {
    /// The curated collections, in curated order.
    let featured: [CollectionSummary]
    /// Every other listed collection, in the store's order.
    let more: [CollectionSummary]

    /// Whether nothing is listed.
    var isEmpty: Bool {
        featured.isEmpty && more.isEmpty
    }
}
