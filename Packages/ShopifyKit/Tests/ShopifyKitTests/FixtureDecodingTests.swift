import Core
import Foundation
@testable import ShopifyKit
import Testing

/// Decodes every recorded fixture through the real client and asserts concrete values.
/// Values were recorded from the live Storefront API on 2026-09-26 (see Fixtures/README.md).
@Suite("Recorded fixtures")
struct FixtureDecodingTests {
    private let germany = Locale(identifier: "de_DE")

    @Test("Every fixture listed in the manifest is bundled and well-formed")
    func manifest() throws {
        struct Manifest: Decodable {
            struct Entry: Decodable {
                let file: String
                let source: String
                let apiVersion: String
            }

            let apiVersion: String
            let tokenless: Bool
            let fixtures: [Entry]
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Fixture.data(Fixture.manifest))
        #expect(manifest.apiVersion == "2026-07")
        #expect(manifest.tokenless)
        #expect(Set(manifest.fixtures.map(\.file)) == Set(Fixture.all.filter { $0 != Fixture.manifest }))
        for entry in manifest.fixtures {
            #expect(entry.apiVersion == "2026-07")
            #expect(entry.source == (entry.file.hasPrefix("synthetic_") ? "synthetic" : "live"))
            _ = try JSONSerialization.jsonObject(with: Fixture.data(entry.file))
        }
    }

    @Test("Product in DE/DE: German content, EUR prices, digital variant")
    func productGermany() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.productDE)])
        let data = try await makeStorefrontClient(stub).execute(
            ProductByHandleQuery(handle: "office-2024-professional-plus-key", includeMetafields: false),
            context: germanyContext
        )
        let product = try #require(data.product)

        #expect(product.id == "gid://shopify/Product/10534352027915")
        #expect(product.id.resourceType == "Product")
        #expect(product.handle == "office-2024-professional-plus-key")
        #expect(product.title == "Microsoft Office 2024 Professional Plus Download kaufen")
        #expect(product.vendor == "Microsoft")
        #expect(product.availableForSale)
        #expect(product.tags.contains("Dauerlizenz"))
        #expect(product.descriptionHtml.hasPrefix("<div"))
        #expect(product.seo.title == "Microsoft Office 2024 Professional Plus kaufen | Dauerlizenz")
        #expect(product.onlineStoreUrl?.absoluteString == "https://www.karinex.de/products/office-2024-professional-plus-key")
        #expect(product.collections.map(\.handle) == ["bestseller", "sale", "microsoft-office", "microsoft-office-2024", "all"])
        #expect(product.metafields.isEmpty)
        #expect(product.productMetafields.faq == nil)

        let image = try #require(product.featuredImage)
        #expect(
            image.url.absoluteString
                == "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Office_2024_Professional_Plus.webp?v=1787443066"
        )
        #expect(image.width == 2048)
        #expect(image.height == 2048)
        #expect(image.altText?.hasPrefix("Microsoft Office 2024 Professional Plus Lizenz Key") == true)
        #expect(product.images == [image])

        #expect(product.variants.count == 1)
        let variant = try #require(product.defaultVariant)
        #expect(variant.id == "gid://shopify/ProductVariant/52710041846027")
        #expect(variant.title == "Default Title")
        #expect(variant.sku == "4260712033710")
        #expect(variant.requiresShipping == false)
        #expect(variant.availableForSale)
        #expect(variant.price == MoneyV2(amount: decimal("29.90"), currencyCode: .eur))
        #expect(variant.compareAtPrice == MoneyV2(amount: decimal("149.99"), currencyCode: .eur))
        #expect(variant.isDiscounted)
        #expect(variant.selectedOptions == [SelectedOption(name: "Title", value: "Default Title")])
        #expect(product.isDigitalOnly)
        #expect(product.selectableOptions.isEmpty)
        #expect(product.options.first?.isDefaultPlaceholder == true)
        #expect(product.variant(matching: ["Title": "Default Title"]) == variant)

        #expect(product.priceRange.isSinglePrice)
        #expect(product.priceRange.minVariantPrice.amount == decimal("29.9"))
        #expect(product.compareAtPriceRange.minVariantPrice.amount == decimal("149.99"))

        let formatted = variant.price.formatted(locale: germany)
        #expect(formatted.contains("29,90"))
        #expect(formatted.contains("€"))
        #expect(variant.compareAtPrice?.formatted(locale: germany).contains("149,99") == true)
    }

    @Test("Product in CH/FR: French content, CHF prices")
    func productSwitzerland() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.productCHFR)])
        let data = try await makeStorefrontClient(stub).execute(
            ProductByHandleQuery(handle: "office-2024-professional-plus-key", includeMetafields: false),
            context: switzerlandFrenchContext
        )
        let product = try #require(data.product)

        #expect(product.id == "gid://shopify/Product/10534352027915")
        #expect(product.title.hasPrefix("Acheter Microsoft Office 2024 Professional Plus"))
        #expect(product.title.contains("Téléchargement"))
        #expect(product.onlineStoreUrl?.absoluteString == "https://www.karinex.de/fr/products/office-2024-professional-plus-key")

        let variant = try #require(product.variants.first)
        #expect(variant.price == MoneyV2(amount: decimal("29"), currencyCode: .chf))
        #expect(variant.compareAtPrice == MoneyV2(amount: decimal("145"), currencyCode: .chf))
        #expect(variant.requiresShipping == false)
        #expect(variant.price.formatted(locale: Locale(identifier: "fr_CH")).contains("29"))
        #expect(variant.price.formatted(locale: Locale(identifier: "de_CH")).contains("CHF"))

        let request = try SentGraphQLBody(#require(stub.requests.first))
        #expect(request.query.contains("@inContext(country: CH, language: FR,"))
    }

    @Test("Unknown product handle decodes as nil")
    func productNotFound() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.productNotFound)])
        let data = try await makeStorefrontClient(stub).execute(
            ProductByHandleQuery(handle: "kx-fixture-no-such-product", includeMetafields: false),
            context: germanyContext
        )
        #expect(data.product == nil)
    }

    @Test("Bestseller collection: first 8 products with prices, images and page info")
    func bestsellerCollection() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.collectionBestseller)])
        let data = try await makeStorefrontClient(stub).execute(
            CollectionProductsQuery(handle: "bestseller", first: 8, sortKey: .collectionDefault),
            context: germanyContext
        )
        let collection = try #require(data.collection)

        #expect(collection.id == "gid://shopify/Collection/641997734155")
        #expect(collection.handle == "bestseller")
        #expect(collection.title == "Bestseller günstig kaufen")
        #expect(collection.image == nil)
        #expect(collection.products.nodes.count == 8)

        let pageInfo = try #require(collection.products.pageInfo)
        #expect(pageInfo.hasNextPage)
        #expect(!pageInfo.hasPreviousPage)
        #expect(pageInfo.endCursor == "eyJsYXN0X2lkIjoxMDY1MTQ4Mjc4NDAxMSwibGFzdF92YWx1ZSI6NjUsIm9mZnNldCI6N30=")
        #expect(pageInfo.nextPageCursor == pageInfo.endCursor)

        let first = collection.products.nodes[0]
        #expect(first.handle == "office-2024-professional-plus-key")
        #expect(first.price == MoneyV2(amount: decimal("29.9"), currencyCode: .eur))
        #expect(first.compareAtPrice == MoneyV2(amount: decimal("149.99"), currencyCode: .eur))

        let windows = collection.products.nodes[1]
        #expect(windows.handle == "windows-11-pro-key-kaufen-download")
        #expect(windows.title.hasPrefix("Windows 11 Pro kaufen"))
        #expect(windows.price.amount == decimal("12.9"))
        #expect(windows.compareAtPrice?.amount == decimal("79.99"))
        #expect(windows.price.formatted(locale: germany).contains("12,90"))
        #expect(
            windows.featuredImage?.url.absoluteString
                == "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Windows-11-Pro-Key-Download-kaufen..webp?v=1787442708"
        )

        let mac = collection.products.nodes[2]
        #expect(mac.handle == "office-2024-standard-mac-key-download")
        #expect(mac.price.amount == decimal("13.9"))
        #expect(mac.compareAtPrice?.amount == decimal("39.99"))

        #expect(collection.products.nodes.allSatisfy { $0.requiresShipping == false })
        #expect(collection.products.nodes.allSatisfy { $0.price.currencyCode == .eur })
        #expect(Set(collection.products.nodes.map(\.id)).count == 8)

        let page = CollectionPage(collection: collection)
        #expect(page.collection.handle == "bestseller")
        #expect(page.products.count == 8)
        #expect(page.pageInfo == pageInfo)
    }

    @Test("Localization: 28 countries, currencies and content languages")
    func localization() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.localization)])
        let data = try await makeStorefrontClient(stub).execute(LocalizationQuery(), context: germanyContext)
        let localization = data.localization

        #expect(localization.country.isoCode == .de)
        #expect(localization.country.name == "Deutschland")
        #expect(localization.language == Language(isoCode: .de, name: "Deutsch", endonymName: "Deutsch"))
        #expect(localization.availableCountries.map(\.isoCode) == CountryCode.recordedStoreCountries)
        #expect(localization.availableLanguages.map(\.isoCode) == LanguageCode.recordedStoreLanguages)

        let switzerland = try #require(localization.country(for: .ch))
        #expect(switzerland.name == "Schweiz")
        #expect(switzerland.currency.isoCode == .chf)
        #expect(switzerland.offers(.fr))
        #expect(localization.country(for: .de)?.currency == Currency(isoCode: .eur, name: "Euro", symbol: "€"))
        #expect(localization.country(for: .se)?.currency.isoCode == .sek)
        #expect(localization.country(for: .nl)?.availableLanguages.map(\.isoCode) == [.nl])
        #expect(!localization.sells(to: .us))
        #expect(!localization.sells(to: .no))

        let currencies = Set(localization.availableCountries.map(\.currency.isoCode))
        #expect(currencies == [.eur, .chf, .czk, .dkk, .huf, .pln, .ron, .sek])
    }

    @Test("cartCreate with an unknown variant: user error INVALID, no cart")
    func cartCreateUserErrors() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.cartCreateInvalidMerchandise)])
        let data = try await makeStorefrontClient(stub).execute(GraphQLClientRetryTests.cartCreate, context: germanyContext)
        let payload = try #require(data.cartCreate)

        #expect(payload.cart == nil)
        #expect(payload.warnings.isEmpty)
        #expect(payload.userErrors.count == 1)
        let error = try #require(payload.userErrors.first)
        #expect(error.code == .invalid)
        #expect(error.field == ["input", "lines", "0", "merchandiseId"])
        #expect(error.message.contains("gid://shopify/ProductVariant/1"))

        #expect(throws: ShopifyError.userErrors(payload.userErrors)) {
            try payload.throwingUserErrors()
        }
    }

    @Test("Response extensions report the resolved context and cost")
    func extensions() throws {
        let response = try JSONDecoder().decode(
            GraphQLResponse<ProductByHandleQuery.ResponseData>.self,
            from: Fixture.data(Fixture.productCHFR)
        )
        #expect(response.errors.isEmpty)
        #expect(response.extensions?.context == GraphQLResponseContext(country: .ch, language: .fr))
        #expect(response.extensions?.cost == GraphQLQueryCost(requestedQueryCost: 46))
        #expect(response.data?.product?.handle == "office-2024-professional-plus-key")

        let denied = try JSONDecoder().decode(
            GraphQLResponse<ProductByHandleQuery.ResponseData>.self,
            from: Fixture.data(Fixture.metafieldsAccessDenied)
        )
        let error = try #require(denied.errors.first)
        #expect(error.code == GraphQLErrorDetail.Code.accessDenied)
        #expect(error.path == [.key("product"), .key("metafields")])
        #expect(error.requiredAccess == "`unauthenticated_read_metafields` access scope.")
        #expect(denied.data?.product == nil)
    }

    @Test("Decoded models encode back into the same shape")
    func roundTrip() throws {
        let product = try #require(
            try JSONDecoder().decode(
                GraphQLResponse<ProductByHandleQuery.ResponseData>.self,
                from: Fixture.data(Fixture.productDE)
            ).data?.product
        )
        let reencodedProduct = try JSONDecoder().decode(Product.self, from: JSONEncoder().encode(product))
        #expect(reencodedProduct == product)

        let collection = try #require(
            try JSONDecoder().decode(
                GraphQLResponse<CollectionProductsQuery.ResponseData>.self,
                from: Fixture.data(Fixture.collectionBestseller)
            ).data?.collection
        )
        let reencodedCollection = try JSONDecoder().decode(ProductCollection.self, from: JSONEncoder().encode(collection))
        #expect(reencodedCollection == collection)

        let localization = try #require(
            try JSONDecoder().decode(GraphQLResponse<LocalizationQuery.ResponseData>.self, from: Fixture.data(Fixture.localization))
                .data?.localization
        )
        #expect(try JSONDecoder().decode(Localization.self, from: JSONEncoder().encode(localization)) == localization)
    }
}
