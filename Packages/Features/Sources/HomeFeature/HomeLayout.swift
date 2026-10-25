import CommerceUI
import Foundation

// MARK: - HomeText

/// A text of the Start screen layout: either a key of this module's String Catalog (the fixed
/// fallback layout) or a text that already arrives localized (a future `app_home` metaobject
/// served by Shopify in the buyer's content language).
public enum HomeText: Sendable, Hashable {
    /// A key of the HomeFeature String Catalog, resolved in the user's language.
    case localized(String)
    /// A text shown exactly as given.
    case verbatim(String)

    /// The text in the user's language.
    var resolved: String {
        resolved(in: HomeResources.bundle)
    }

    /// The text resolved against `bundle`: the module bundle, or one of its `.lproj` folders.
    func resolved(in bundle: Bundle) -> String {
        switch self {
        case let .localized(key):
            String(localized: String.LocalizationValue(key), bundle: bundle)
        case let .verbatim(text):
            text
        }
    }
}

// MARK: - HomeSection

/// One live module of the Start screen below the trust strip.
public struct HomeSection: Sendable, Hashable, Identifiable {
    /// Where the module's content comes from.
    public enum Content: Sendable, Hashable {
        /// A horizontal product row with the first `limit` products of the collection with
        /// `handle`, in the collection's own order. `highlight` is the editorial badge of every
        /// card (``ProductCardHighlight/bestseller`` only for the bestseller collection).
        case collection(handle: String, limit: Int, highlight: ProductCardHighlight)
        /// A horizontal row with the newest `limit` articles of the blog with `handle`.
        case blog(handle: String, limit: Int)
    }

    /// The section title, e.g. "Office".
    public let title: HomeText
    /// The small label above the title, if any.
    public let eyebrow: HomeText?
    /// Where the content comes from.
    public let content: Content

    /// Creates a section.
    ///
    /// - Parameters:
    ///   - title: The section title.
    ///   - eyebrow: The small label above the title, or `nil`.
    ///   - content: Where the content comes from.
    public init(title: HomeText, eyebrow: HomeText? = nil, content: Content) {
        self.title = title
        self.eyebrow = eyebrow
        self.content = content
    }

    /// The collection or blog handle. Unique within a layout and used as the identity, the
    /// accessibility identifier `home.row.<handle>` and the key of the row's load state.
    public var id: String {
        switch content {
        case let .collection(handle, _, _), let .blog(handle, _):
            handle
        }
    }

    /// The accessibility identifier of the section: `home.row.<handle>`.
    public var accessibilityIdentifier: String {
        "home.row.\(id)"
    }
}

// MARK: - HomeLayout

/// The rows the Start screen loads: every collection and blog its modules show, once each.
/// ``HomeModules/standard`` derives it; the view model loads it.
///
/// ```swift
/// HomeViewModel(catalog: catalog, content: content, layout: HomeModules.standard.layout)
/// ```
public struct HomeLayout: Sendable, Hashable {
    /// The rows in loading order. Handles are unique.
    public let sections: [HomeSection]

    /// Creates a layout. Later sections with a handle that already appeared are dropped, so
    /// every row keeps its own state.
    public init(sections: [HomeSection]) {
        var seen = Set<String>()
        self.sections = sections.filter { seen.insert($0.id).inserted }
    }

    /// The section with `handle`, if the layout loads it.
    public func section(_ handle: String) -> HomeSection? {
        sections.first { $0.id == handle }
    }

    /// The number of products loaded for a collection that shows a row of products (PROMPT.md
    /// asks for 4 to 6 cards; a few more keep the row worth scrolling).
    public static let productsPerRow = 8

    /// The number of products loaded for a tile that shows only its first product's photo.
    public static let productsPerTile = 1

    /// The number of guide articles in the Ratgeber module.
    public static let articlesPerRow = 6
}

// MARK: - HomeCategory

/// A store collection the Start screen features, with the app's short name, an optional small
/// label and a symbol. The collection's own title in the store is often long (it is written for
/// search engines), so the screen uses these names.
public struct HomeCategory: Sendable, Hashable, Identifiable {
    /// The collection handle, e.g. `windows`.
    public let handle: String
    /// The short name, e.g. "Windows".
    public let title: HomeText
    /// The small label above the name in panels, e.g. "Betriebssysteme".
    public let eyebrow: HomeText?
    /// The SF Symbol of the category tile.
    public let systemImage: String

    /// Creates a category.
    public init(handle: String, title: HomeText, eyebrow: HomeText? = nil, systemImage: String) {
        self.handle = handle
        self.title = title
        self.eyebrow = eyebrow
        self.systemImage = systemImage
    }

    /// The handle.
    public var id: String {
        handle
    }
}

// MARK: - HomeStory

/// One card of the story carousel at the top of the Start screen: a category with the small tag
/// above its photo.
public struct HomeStory: Sendable, Hashable, Identifiable {
    /// The featured collection.
    public let category: HomeCategory
    /// The tag above the photo, e.g. "Bestseller".
    public let tag: HomeText

    /// Creates a story.
    public init(category: HomeCategory, tag: HomeText) {
        self.category = category
        self.tag = tag
    }

    /// The collection handle.
    public var id: String {
        category.handle
    }
}

// MARK: - HomeModules

/// The modules of the Start screen, in the style of fashion retail apps, and the store
/// collections behind them (docs/STORE_AUDIT.md):
///
/// - ``stories``: the story carousel at the top (one card per collection).
/// - ``showcase``: the category tiles with the dark product panel of the chosen one.
/// - ``bestsellers``: the row of cards with prices below the showcase.
/// - ``deals``: the dark sale panel.
/// - ``versions``: the two by two grid of product versions (one photo each).
/// - ``guidesBlog``: the Ratgeber stories.
/// - ``feed``: the chips at the bottom that switch the screen to one category.
///
/// The fixed texts, the trust facts, "Zuletzt angesehen", the service tiles and the support
/// card need no store data and are not listed here.
public struct HomeModules: Sendable, Hashable {
    /// The cards of the story carousel.
    public let stories: [HomeStory]
    /// The tiles of the category showcase, the first one chosen at start.
    public let showcase: [HomeCategory]
    /// The collection of the bestseller row.
    public let bestsellers: HomeCategory
    /// The collection of the sale panel.
    public let deals: HomeCategory
    /// The tiles of the version grid.
    public let versions: [HomeCategory]
    /// The blog of the Ratgeber stories.
    public let guidesBlog: String
    /// The categories of the feed chips.
    public let feed: [HomeCategory]

    /// Creates the modules.
    public init(
        stories: [HomeStory],
        showcase: [HomeCategory],
        bestsellers: HomeCategory,
        deals: HomeCategory,
        versions: [HomeCategory],
        guidesBlog: String,
        feed: [HomeCategory]
    ) {
        self.stories = stories
        self.showcase = showcase
        self.bestsellers = bestsellers
        self.deals = deals
        self.versions = versions
        self.guidesBlog = guidesBlog
        self.feed = feed
    }

    /// The rows to load: every collection once, with the larger size when a collection is both
    /// a row and a tile, then the guides blog.
    public var layout: HomeLayout {
        let rowCategories = stories.map(\.category) + showcase + [bestsellers, deals] + feed
        let rowHandles = rowCategories.map(\.handle)
        let rows = Set(rowHandles)
        var sections = rowHandles.map { handle in
            HomeSection(
                title: .verbatim(handle),
                content: .collection(
                    handle: handle,
                    limit: HomeLayout.productsPerRow,
                    highlight: handle == HomeModules.bestsellerHandle ? .bestseller : .none
                )
            )
        }
        sections += versions.filter { !rows.contains($0.handle) }.map { version in
            HomeSection(
                title: .verbatim(version.handle),
                content: .collection(handle: version.handle, limit: HomeLayout.productsPerTile, highlight: .none)
            )
        }
        sections.append(
            HomeSection(
                title: .localized("home.section.guides.title"),
                eyebrow: .localized("home.section.guides.eyebrow"),
                content: .blog(handle: guidesBlog, limit: HomeLayout.articlesPerRow)
            )
        )
        return HomeLayout(sections: sections)
    }

    /// The bestseller collection, the only one whose cards may say "Bestseller".
    public static let bestsellerHandle = "bestseller"

    /// The standard modules with the live store handles.
    public static let standard = HomeModules(
        stories: [
            HomeStory(category: .bestseller, tag: .localized("home.story.tag.bestseller")),
            HomeStory(category: .windows, tag: .localized("home.story.tag.range")),
            HomeStory(category: .office, tag: .localized("home.story.tag.range")),
            HomeStory(category: .server, tag: .localized("home.story.tag.range")),
            HomeStory(category: .development, tag: .localized("home.story.tag.range")),
        ],
        showcase: [.windows, .office, .server, .mac, .development, .microsoft365],
        bestsellers: .bestseller,
        deals: .deals,
        versions: [
            HomeCategory(handle: "windows-11", title: .verbatim("Windows 11"), systemImage: "macwindow"),
            HomeCategory(handle: "windows-10", title: .verbatim("Windows 10"), systemImage: "macwindow"),
            HomeCategory(handle: "microsoft-office-2024", title: .verbatim("Office 2024"), systemImage: "doc.richtext"),
            HomeCategory(handle: "microsoft-office-2021", title: .verbatim("Office 2021"), systemImage: "doc.richtext"),
        ],
        guidesBlog: "guides",
        feed: [.windows, .office, .server, .mac, .development, .deals]
    )
}

// MARK: - Standard categories

extension HomeCategory {
    /// `bestseller`.
    public static let bestseller = HomeCategory(
        handle: HomeModules.bestsellerHandle,
        title: .localized("home.section.bestseller.title"),
        eyebrow: .localized("home.section.bestseller.eyebrow"),
        systemImage: "sparkles"
    )
    /// `windows`.
    public static let windows = HomeCategory(
        handle: "windows",
        title: .localized("home.section.windows.title"),
        eyebrow: .localized("home.section.windows.eyebrow"),
        systemImage: "macwindow"
    )
    /// `microsoft-office`.
    public static let office = HomeCategory(
        handle: "microsoft-office",
        title: .localized("home.section.office.title"),
        eyebrow: .localized("home.section.office.eyebrow"),
        systemImage: "doc.richtext"
    )
    /// `windows-server`.
    public static let server = HomeCategory(
        handle: "windows-server",
        title: .localized("home.section.server.title"),
        eyebrow: .localized("home.section.server.eyebrow"),
        systemImage: "server.rack"
    )
    /// `microsoft-office-fur-mac`.
    public static let mac = HomeCategory(
        handle: "microsoft-office-fur-mac",
        title: .localized("home.category.mac.title"),
        eyebrow: .localized("home.category.mac.eyebrow"),
        systemImage: "laptopcomputer"
    )
    /// `visual-studio-entwicklungstools`.
    public static let development = HomeCategory(
        handle: "visual-studio-entwicklungstools",
        title: .localized("home.section.development.title"),
        eyebrow: .localized("home.section.development.eyebrow"),
        systemImage: "chevron.left.forwardslash.chevron.right"
    )
    /// `microsoft-365-abonnement`.
    public static let microsoft365 = HomeCategory(
        handle: "microsoft-365-abonnement",
        title: .verbatim("Microsoft 365"),
        eyebrow: .localized("home.category.microsoft365.eyebrow"),
        systemImage: "icloud"
    )
    /// `sale`.
    public static let deals = HomeCategory(
        handle: "sale",
        title: .localized("home.section.deals.title"),
        eyebrow: .localized("home.section.deals.eyebrow"),
        systemImage: "tag"
    )
}
