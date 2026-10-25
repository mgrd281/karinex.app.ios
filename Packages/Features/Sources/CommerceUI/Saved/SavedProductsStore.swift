import Core
import Foundation
import Observation
import ShopifyKit

// MARK: - SavedProductsStore

/// The wishlist ("Merkliste") and the recently viewed products, kept on this device only.
///
/// - Only product GIDs are stored, never titles, prices or images: the screens load the
///   products fresh through `ProductLookupRepository`, so everything shown comes from Shopify in
///   the current market. A product that no longer exists simply drops out of the list.
/// - Both lists are newest first. The wishlist holds up to ``wishlistLimit`` products, the
///   history ``recentLimit``; the oldest entries fall out.
/// - Nothing leaves the device and nothing is linked to the customer account.
@MainActor
@Observable
public final class SavedProductsStore {
    /// Preferences key of the wishlist.
    public static let wishlistKey = "saved.wishlist.v1"
    /// Preferences key of the recently viewed products.
    public static let recentKey = "saved.recent.v1"
    /// The most products the wishlist keeps.
    public static let wishlistLimit = 100
    /// The most products the history keeps.
    public static let recentLimit = 20

    /// The wishlist, newest first.
    public private(set) var wishlist: [ShopifyID]
    /// The recently viewed products, newest first.
    public private(set) var recentlyViewed: [ShopifyID]

    @ObservationIgnored private let store: any KeyValueStore

    /// Creates the store and reads the saved lists.
    public init(store: any KeyValueStore) {
        self.store = store
        wishlist = Self.read(Self.wishlistKey, from: store)
        recentlyViewed = Self.read(Self.recentKey, from: store)
    }

    // MARK: Wishlist

    /// Whether `id` is on the wishlist.
    public func isSaved(_ id: ShopifyID) -> Bool {
        wishlist.contains(id)
    }

    /// Adds `id` to the front of the wishlist, or removes it. Returns whether it is saved now.
    @discardableResult
    public func toggle(_ id: ShopifyID) -> Bool {
        if let index = wishlist.firstIndex(of: id) {
            wishlist.remove(at: index)
            save(wishlist, for: Self.wishlistKey)
            return false
        }
        wishlist = Array(([id] + wishlist).prefix(Self.wishlistLimit))
        save(wishlist, for: Self.wishlistKey)
        return true
    }

    /// Removes `id` from the wishlist.
    public func remove(_ id: ShopifyID) {
        guard wishlist.contains(id) else { return }
        wishlist.removeAll { $0 == id }
        save(wishlist, for: Self.wishlistKey)
    }

    // MARK: History

    /// Moves `id` to the front of the recently viewed products.
    public func recordView(_ id: ShopifyID) {
        guard recentlyViewed.first != id else { return }
        recentlyViewed = Array(([id] + recentlyViewed.filter { $0 != id }).prefix(Self.recentLimit))
        save(recentlyViewed, for: Self.recentKey)
    }

    /// Forgets the recently viewed products.
    public func clearRecentlyViewed() {
        recentlyViewed = []
        save(recentlyViewed, for: Self.recentKey)
    }

    /// Forgets both lists, e.g. from the privacy settings.
    public func removeAll() {
        wishlist = []
        recentlyViewed = []
        store.set(nil as Data?, forKey: Self.wishlistKey)
        store.set(nil as Data?, forKey: Self.recentKey)
    }

    // MARK: Storage

    private func save(_ ids: [ShopifyID], for key: String) {
        store.set(try? JSONEncoder().encode(ids), forKey: key)
    }

    private static func read(_ key: String, from store: any KeyValueStore) -> [ShopifyID] {
        guard let data = store.data(forKey: key), let ids = try? JSONDecoder().decode([ShopifyID].self, from: data) else {
            return []
        }
        var seen = Set<ShopifyID>()
        return ids.filter { $0.isShopifyGID && seen.insert($0).inserted }
    }
}
