import Core
import DesignTokens
import Foundation
import ShopifyKit
import SwiftUI
import WidgetKit

// MARK: - Timeline

/// One snapshot of the bestseller collection, exactly as Shopify returned it.
struct BestsellerEntry: TimelineEntry {
    /// One product row.
    struct Item: Hashable {
        let handle: String
        let title: String
        let price: MoneyV2
    }

    let date: Date
    let items: [Item]
    /// Whether the store could not be reached; the widget then asks to open the app.
    let isUnavailable: Bool
}

/// Loads the first products of the collection `bestseller` (docs/STORE_AUDIT.md) from the
/// Storefront API in the device's country and language, every two hours. The widget never
/// shows anything that does not come from Shopify: without an answer it shows a neutral hint.
struct BestsellerProvider: TimelineProvider {
    static let collectionHandle = "bestseller"
    static let refreshInterval: TimeInterval = 2 * 60 * 60

    func placeholder(in _: Context) -> BestsellerEntry {
        BestsellerEntry(date: Date(), items: [], isUnavailable: false)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (BestsellerEntry) -> Void) {
        let count = Self.itemCount(for: context.family)
        Task {
            await completion(Self.load(count: count))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<BestsellerEntry>) -> Void) {
        let count = Self.itemCount(for: context.family)
        Task {
            let entry = await Self.load(count: count)
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(Self.refreshInterval))))
        }
    }

    static func itemCount(for family: WidgetFamily) -> Int {
        family == .systemSmall ? 1 : 3
    }

    /// Reads the collection with the app's configuration (tokenless unless a token is set).
    static func load(count: Int) async -> BestsellerEntry {
        let info = Bundle.main.infoDictionary ?? [:]
        let configuration = (try? AppConfiguration(infoDictionary: info)) ?? .preview
        let client = StorefrontClient(
            configuration: StorefrontConfiguration(appConfiguration: configuration),
            httpClient: URLSessionHTTPClient(configuration: .ephemeral)
        )
        let repository = StorefrontCatalogRepository(client: client, contextProvider: StaticStorefrontContextProvider(context: context()))
        do {
            let page = try await repository.collection(handle: collectionHandle, first: count)
            let items = (page?.products ?? []).prefix(count).map { product in
                BestsellerEntry.Item(handle: product.handle, title: product.title, price: product.priceRange.minVariantPrice)
            }
            return BestsellerEntry(date: Date(), items: items, isUnavailable: items.isEmpty)
        } catch {
            return BestsellerEntry(date: Date(), items: [], isUnavailable: true)
        }
    }

    /// The buyer context of the device: its region and the widget's UI language.
    private static func context() -> StorefrontContext {
        let region = Locale.current.region?.identifier ?? "DE"
        let language = AppLanguage.preferred(from: Bundle.main.preferredLocalizations) ?? .source
        return StorefrontContext(country: CountryCode(rawValue: region), language: LanguageCode(appLanguage: language))
    }
}

// MARK: - Views

struct BestsellerWidgetView: View {
    let entry: BestsellerEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.xs) {
            Text("widget.bestseller.eyebrow")
                .font(WidgetPalette.font(.eyebrow))
                .textCase(.uppercase)
                .foregroundStyle(WidgetPalette.color(.accent))
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Group {
                    if entry.isUnavailable {
                        Text("widget.bestseller.unavailable")
                    } else {
                        Text("widget.bestseller.loading")
                    }
                }
                .font(WidgetPalette.font(.footnote))
                .foregroundStyle(WidgetPalette.color(.textOnBrand))
                Spacer(minLength: 0)
            } else {
                ForEach(entry.items, id: \.handle) { item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            WidgetPalette.color(.brand)
        }
        .widgetURL(entry.items.first.flatMap { URL(string: "karinex://product/\($0.handle)") } ?? URL(string: "karinex://"))
    }

    @ViewBuilder
    private func row(_ item: BestsellerEntry.Item) -> some View {
        let content = VStack(alignment: .leading, spacing: SpacingToken.xxs) {
            Text(verbatim: item.title)
                .font(WidgetPalette.font(family == .systemSmall ? .title3 : .headline))
                .foregroundStyle(WidgetPalette.color(.textOnBrand))
                .lineLimit(family == .systemSmall ? 3 : 1)
            Text(verbatim: item.price.formatted(locale: locale))
                .font(WidgetPalette.font(.price))
                .foregroundStyle(WidgetPalette.color(.accent))
        }
        if family == .systemSmall {
            content
        } else if let url = URL(string: "karinex://product/\(item.handle)") {
            Link(destination: url) {
                content
            }
        }
    }
}

// MARK: - Widget

struct BestsellerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.karinex.widget.bestseller", provider: BestsellerProvider()) { entry in
            BestsellerWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("widget.bestseller.name"))
        .description(Text("widget.bestseller.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
