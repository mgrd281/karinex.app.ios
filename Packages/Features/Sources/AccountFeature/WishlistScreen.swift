import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - WishlistScreen

/// "Merkliste": the products saved with the heart on the product page, newest first.
///
/// The list lives only on this device (`SavedProductsStore`) and needs no login. The products
/// are loaded fresh from Shopify, so prices and availability are always those of the current
/// market; a product that no longer exists drops out. A long press removes a product.
public struct WishlistScreen: View {
    private let savedProducts: SavedProductsStore
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @Environment(\.productLookup) private var lookup
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var loader = SavedProductsLoader()

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - savedProducts: The device's wishlist.
    ///   - onRoute: Opens a product.
    public init(savedProducts: SavedProductsStore, onRoute: @escaping @MainActor (CommerceRoute) -> Void) {
        self.savedProducts = savedProducts
        self.onRoute = onRoute
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: KXSpacing.m, alignment: .top)]
        }
        return [GridItem(.adaptive(minimum: 160, maximum: 280), spacing: KXSpacing.m, alignment: .top)]
    }

    public var body: some View {
        AsyncContentView(
            loader.state,
            empty: AsyncContentEmptyState(
                systemImage: "heart",
                title: String(localized: "account.wishlist.empty.title", bundle: .module),
                message: String(localized: "account.wishlist.empty.message", bundle: .module)
            ),
            retry: { await loader.load(savedProducts.wishlist, from: lookup) },
            content: { products in
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: KXSpacing.l) {
                        ForEach(products) { product in
                            card(product)
                        }
                    }
                    .padding(.horizontal, KXSpacing.gutter)
                    .padding(.vertical, KXSpacing.l)
                }
                .refreshable { await loader.load(savedProducts.wishlist, from: lookup) }
            },
            placeholder: {
                AsyncContentSkeleton()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.wishlist")
        .kxScreenBackground()
        .navigationTitle(Text("account.wishlist.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: savedProducts.wishlist) {
            await loader.load(savedProducts.wishlist, from: lookup)
        }
    }

    private func card(_ product: ProductSummary) -> some View {
        Button {
            onRoute(.product(handle: product.handle))
        } label: {
            ProductCardView(product)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                savedProducts.remove(product.id)
            } label: {
                Label {
                    Text("account.wishlist.remove", bundle: .module)
                } icon: {
                    Image(systemName: "heart.slash")
                }
            }
        }
        .accessibilityAction(named: Text("account.wishlist.remove", bundle: .module)) {
            savedProducts.remove(product.id)
        }
        .accessibilityIdentifier("product.card.\(product.handle)")
    }
}
