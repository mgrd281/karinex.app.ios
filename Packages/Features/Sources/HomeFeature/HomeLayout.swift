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

/// The ordered live modules of the Start screen. The hero, the trust strip and the support card
/// are fixed; everything in between is described by this value, so a future `app_home`
/// metaobject can replace ``standard`` without touching the view.
///
/// ```swift
/// HomeView(catalog: catalog, content: content, layout: .standard, onRoute: route, onBrowse: browse)
/// ```
public struct HomeLayout: Sendable, Hashable {
    /// The modules in display order. Handles must be unique.
    public let sections: [HomeSection]

    /// Creates a layout. Later sections with a handle that already appeared are dropped, so
    /// every row keeps its own state.
    public init(sections: [HomeSection]) {
        var seen = Set<String>()
        self.sections = sections.filter { seen.insert($0.id).inserted }
    }

    /// The number of products loaded for each collection row (PROMPT.md asks for 4 to 6 cards;
    /// a few more keep the row worth scrolling).
    public static let productsPerRow = 8

    /// The number of guide articles in the Ratgeber row.
    public static let articlesPerRow = 6

    /// The fixed layout with the live store handles (docs/STORE_AUDIT.md): Angebote (`sale`),
    /// Windows (`windows`), Office (`microsoft-office`), Server (`windows-server`), Entwicklung
    /// (`visual-studio-entwicklungstools`), Bestseller (`bestseller`) and Ratgeber (blog
    /// `guides`, 6 articles).
    public static let standard = HomeLayout(sections: [
        HomeSection(
            title: .localized("home.section.deals.title"),
            eyebrow: .localized("home.section.deals.eyebrow"),
            content: .collection(handle: "sale", limit: productsPerRow, highlight: .none)
        ),
        HomeSection(
            title: .localized("home.section.windows.title"),
            eyebrow: .localized("home.section.windows.eyebrow"),
            content: .collection(handle: "windows", limit: productsPerRow, highlight: .none)
        ),
        HomeSection(
            title: .localized("home.section.office.title"),
            eyebrow: .localized("home.section.office.eyebrow"),
            content: .collection(handle: "microsoft-office", limit: productsPerRow, highlight: .none)
        ),
        HomeSection(
            title: .localized("home.section.server.title"),
            eyebrow: .localized("home.section.server.eyebrow"),
            content: .collection(handle: "windows-server", limit: productsPerRow, highlight: .none)
        ),
        HomeSection(
            title: .localized("home.section.development.title"),
            eyebrow: .localized("home.section.development.eyebrow"),
            content: .collection(handle: "visual-studio-entwicklungstools", limit: productsPerRow, highlight: .none)
        ),
        HomeSection(
            title: .localized("home.section.bestseller.title"),
            eyebrow: .localized("home.section.bestseller.eyebrow"),
            content: .collection(handle: "bestseller", limit: productsPerRow, highlight: .bestseller)
        ),
        HomeSection(
            title: .localized("home.section.guides.title"),
            eyebrow: .localized("home.section.guides.eyebrow"),
            content: .blog(handle: "guides", limit: articlesPerRow)
        ),
    ])
}
