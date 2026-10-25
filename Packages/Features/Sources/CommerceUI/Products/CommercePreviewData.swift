import Core
import Foundation
import ShopifyKit

// MARK: - CommercePreviewData

/// Sample values for the previews of this module.
///
/// Recorded from the live Storefront API on 2026-09-26 (collection "bestseller", DE/DE). Titles
/// are store content and rendered as-is, including their dashes (written as \u{2013} escapes).
enum CommercePreviewData {
    /// Microsoft Office 2024 Professional Plus, Windows 11 Pro and Office 2024 Standard für Mac.
    static let products: [ProductSummary] = [
        product(
            id: "gid://shopify/Product/1",
            handle: "office-2024-professional-plus-key",
            title: "Microsoft Office 2024 Professional Plus Download kaufen",
            price: "29.90",
            compareAtPrice: "149.99",
            imageURL: "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Office_2024_Professional_Plus.webp"
        ),
        product(
            id: "gid://shopify/Product/2",
            handle: "windows-11-pro",
            title: "Windows 11 Pro kaufen \u{2013} Dauerlizenz 1 PC, Download",
            price: "12.90",
            compareAtPrice: "79.99",
            imageURL: "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Windows-11-Pro-Key-Download-kaufen..webp?v=1787442708"
        ),
        product(
            id: "gid://shopify/Product/3",
            handle: "office-2024-standard-mac",
            title: "Microsoft Office 2024 Standard für Mac Key \u{2013} Sofort Download",
            price: "13.90",
            compareAtPrice: "39.99",
            imageURL: nil
        ),
    ]

    private static func product(
        id: String,
        handle: String,
        title: String,
        price: String,
        compareAtPrice: String,
        imageURL: String?
    ) -> ProductSummary {
        let priceValue = MoneyV2(amount: Decimal(string: price) ?? 0, currencyCode: .eur)
        let compareAtValue = MoneyV2(amount: Decimal(string: compareAtPrice) ?? 0, currencyCode: .eur)
        return ProductSummary(
            id: ShopifyID(id),
            handle: handle,
            title: title,
            vendor: "karinex",
            availableForSale: true,
            featuredImage: imageURL.flatMap(URL.init(string:)).map { ShopifyImage(url: $0) },
            priceRange: PriceRange(minVariantPrice: priceValue, maxVariantPrice: priceValue),
            compareAtPriceRange: PriceRange(minVariantPrice: compareAtValue, maxVariantPrice: compareAtValue),
            requiresShipping: false
        )
    }
}

// MARK: - Markets

extension CommercePreviewData {
    /// A small excerpt of the recorded store localization: Germany, Austria, Switzerland and
    /// the Netherlands (which only offers Dutch content).
    static let localization: Localization = {
        let german = Language(isoCode: .de, name: "Deutsch", endonymName: "Deutsch")
        let english = Language(isoCode: .en, name: "Englisch", endonymName: "English")
        let french = Language(isoCode: .fr, name: "Französisch", endonymName: "français")
        let dutch = Language(isoCode: .nl, name: "Niederländisch", endonymName: "Nederlands")
        let euro = Currency(isoCode: .eur, name: "Euro", symbol: "€")
        let franc = Currency(isoCode: .chf, name: "Schweizer Franken", symbol: "CHF")
        let germany = Country(isoCode: .de, name: "Deutschland", currency: euro, availableLanguages: [german, english, french])
        return Localization(
            country: germany,
            language: german,
            availableCountries: [
                germany,
                Country(isoCode: .at, name: "Österreich", currency: euro, availableLanguages: [german, english, french]),
                Country(isoCode: .ch, name: "Schweiz", currency: franc, availableLanguages: [german, english, french]),
                Country(isoCode: .nl, name: "Niederlande", currency: euro, availableLanguages: [dutch]),
            ],
            availableLanguages: [german, english, french, dutch]
        )
    }()

    /// A market store on in-memory storage that resolves `regionCode` and `languages` against
    /// ``localization``.
    @MainActor
    static func marketStore(regionCode: String = "US", languages: [String] = ["de-DE"]) -> MarketStore {
        MarketStore(
            localizationRepository: PreviewLocalizationRepository(localization: localization),
            contextProvider: MutableStorefrontContextProvider(context: .germany),
            consentStore: ConsentStore(store: InMemoryKeyValueStore()),
            store: InMemoryKeyValueStore(),
            regionCode: { regionCode },
            preferredLanguages: { languages }
        )
    }
}

/// Serves a fixed localization to previews.
struct PreviewLocalizationRepository: LocalizationRepository {
    let localization: Localization

    func localization() async throws -> Localization {
        localization
    }
}
