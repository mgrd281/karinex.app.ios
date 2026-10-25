@testable import CommerceUI
import Core
import Foundation
import ShopifyKit
import Testing

@Suite("Saved products")
@MainActor
struct SavedProductsStoreTests {
    private func id(_ number: Int) -> ShopifyID {
        ShopifyID("gid://shopify/Product/\(number)")
    }

    @Test("The heart adds to the front and removes again")
    func toggle() {
        let store = SavedProductsStore(store: InMemoryKeyValueStore())

        #expect(store.toggle(id(1)))
        #expect(store.toggle(id(2)))
        #expect(store.wishlist == [id(2), id(1)])
        #expect(store.isSaved(id(1)))
        #expect(!store.toggle(id(1)))
        #expect(store.wishlist == [id(2)])
    }

    @Test("Both lists survive a restart")
    func persistence() {
        let preferences = InMemoryKeyValueStore()
        let store = SavedProductsStore(store: preferences)
        store.toggle(id(1))
        store.recordView(id(5))
        store.recordView(id(6))

        let reloaded = SavedProductsStore(store: preferences)

        #expect(reloaded.wishlist == [id(1)])
        #expect(reloaded.recentlyViewed == [id(6), id(5)])
    }

    @Test("A product viewed again moves to the front, without duplicates")
    func history() {
        let store = SavedProductsStore(store: InMemoryKeyValueStore())

        for number in 1...3 {
            store.recordView(id(number))
        }
        store.recordView(id(1))

        #expect(store.recentlyViewed == [id(1), id(3), id(2)])
    }

    @Test("The lists are capped")
    func limits() {
        let store = SavedProductsStore(store: InMemoryKeyValueStore())

        for number in 0..<(SavedProductsStore.wishlistLimit + 5) {
            store.toggle(id(number))
            store.recordView(id(number))
        }

        #expect(store.wishlist.count == SavedProductsStore.wishlistLimit)
        #expect(store.recentlyViewed.count == SavedProductsStore.recentLimit)
        #expect(store.recentlyViewed.first == id(SavedProductsStore.wishlistLimit + 4))
    }

    @Test("Damaged or foreign stored values are ignored")
    func damagedStorage() throws {
        let preferences = InMemoryKeyValueStore()
        preferences.set(Data("not json".utf8), forKey: SavedProductsStore.wishlistKey)
        let mixed = try JSONEncoder().encode([id(1), ShopifyID("office"), id(1)])
        preferences.set(mixed, forKey: SavedProductsStore.recentKey)

        let store = SavedProductsStore(store: preferences)

        #expect(store.wishlist.isEmpty)
        #expect(store.recentlyViewed == [id(1)])
    }

    @Test("Clearing removes everything")
    func clearing() {
        let preferences = InMemoryKeyValueStore()
        let store = SavedProductsStore(store: preferences)
        store.toggle(id(1))
        store.recordView(id(2))

        store.clearRecentlyViewed()
        #expect(store.recentlyViewed.isEmpty)
        #expect(store.wishlist == [id(1)])

        store.removeAll()
        #expect(SavedProductsStore(store: preferences).wishlist.isEmpty)
    }
}

@Suite("Saved products loader")
@MainActor
struct SavedProductsLoaderTests {
    private actor StubLookup: ProductLookupRepository {
        private(set) var requests: [[ShopifyID]] = []

        func products(ids: [ShopifyID]) async throws -> [ProductSummary] {
            requests.append(ids)
            return []
        }
    }

    @Test("No IDs or no repository is the empty state without a request")
    func empty() async {
        let lookup = StubLookup()
        let loader = SavedProductsLoader()

        await loader.load([], from: lookup)
        #expect(loader.state == .empty)
        await loader.load(["gid://shopify/Product/1"], from: nil)
        #expect(loader.state == .empty)
        #expect(await lookup.requests.isEmpty)
    }

    @Test("Products that no longer exist leave an empty list")
    func vanished() async {
        let lookup = StubLookup()
        let loader = SavedProductsLoader()

        await loader.load(["gid://shopify/Product/1"], from: lookup)

        #expect(loader.state == .empty)
        #expect(await lookup.requests == [["gid://shopify/Product/1"]])
    }
}
