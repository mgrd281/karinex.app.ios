import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - Environment

extension EnvironmentValues {
    /// Loads the products of the wishlist and the history. `nil` (the default, e.g. in
    /// previews) hides the sections that need it. The App sets the Storefront repository.
    public var productLookup: (any ProductLookupRepository)? {
        get { self[ProductLookupKey.self] }
        set { self[ProductLookupKey.self] = newValue }
    }
}

private struct ProductLookupKey: EnvironmentKey {
    static let defaultValue: (any ProductLookupRepository)? = nil
}

// MARK: - SavedProductsLoader

/// Loads the products for a list of saved IDs, keeping the last result while a reload runs.
@MainActor
@Observable
public final class SavedProductsLoader {
    /// The products, in the order of the IDs.
    public private(set) var state: LoadState<[ProductSummary]> = .idle

    /// Creates a loader.
    public init() {}

    /// Loads the products for `ids`; an empty list is the empty state without a request.
    public func load(_ ids: [ShopifyID], from lookup: (any ProductLookupRepository)?) async {
        guard let lookup, !ids.isEmpty else {
            state = .empty
            return
        }
        if state.value == nil {
            state = .loading
        }
        do {
            let products = try await lookup.products(ids: ids)
            state = LoadState(collection: products)
        } catch {
            if let failure = UserFacingError(error), state.value == nil {
                state = .failed(failure)
            }
        }
    }
}

// MARK: - RecentlyViewedSection

/// "Zuletzt angesehen": a carousel of the products viewed last on this device. It shows
/// nothing while there is no history, no `SavedProductsStore` or no `productLookup` in the
/// environment, and when loading fails (the section is optional).
public struct RecentlyViewedSection: View {
    private let excluding: ShopifyID?
    private let onSelect: @MainActor (ProductSummary) -> Void

    @Environment(SavedProductsStore.self) private var savedProducts: SavedProductsStore?
    @Environment(\.productLookup) private var lookup
    @State private var loader = SavedProductsLoader()

    /// Creates the section.
    ///
    /// - Parameters:
    ///   - excluding: A product to leave out, e.g. the one on screen.
    ///   - onSelect: Called with the tapped product.
    public init(excluding: ShopifyID? = nil, onSelect: @escaping @MainActor (ProductSummary) -> Void) {
        self.excluding = excluding
        self.onSelect = onSelect
    }

    private var ids: [ShopifyID] {
        (savedProducts?.recentlyViewed ?? []).filter { $0 != excluding }
    }

    public var body: some View {
        Group {
            if let products = loader.state.value, !products.isEmpty {
                ProductCarouselSection(
                    title: String(localized: "commerce.recent.title", bundle: .module),
                    products: products,
                    onSelect: onSelect
                )
                .accessibilityIdentifier("section.recentlyViewed")
            }
        }
        .task(id: ids) {
            await loader.load(ids, from: lookup)
        }
    }
}
