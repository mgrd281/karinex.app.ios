import Core
import Foundation
import ShopifyKit

// MARK: - RecentSearches

/// The last searches of the user, newest first, persisted in a ``KeyValueStore`` as a JSON
/// array under ``key``. At most ``limit`` entries; a repeated query moves to the front (case
/// and surrounding spaces do not matter).
///
/// Search terms stay on the device and are never logged.
struct RecentSearches: Sendable {
    /// The storage key.
    static let key = "search.recent.v1"
    /// The maximum number of entries.
    static let limit = 8

    private let store: any KeyValueStore

    /// Creates the list on `store`.
    init(store: any KeyValueStore) {
        self.store = store
    }

    /// The stored searches, newest first. Unreadable data counts as no searches.
    func load() -> [String] {
        guard let data = store.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Array(entries.prefix(Self.limit))
    }

    /// Puts `query` in front, removes an older equal entry, keeps ``limit`` entries, stores and
    /// returns the new list. Blank queries change nothing.
    @discardableResult
    func add(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries = load()
        guard !trimmed.isEmpty else { return entries }
        entries.removeAll { $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        entries.insert(trimmed, at: 0)
        entries = Array(entries.prefix(Self.limit))
        save(entries)
        return entries
    }

    /// Removes `query`, stores and returns the new list.
    @discardableResult
    func remove(_ query: String) -> [String] {
        var entries = load()
        entries.removeAll { $0 == query }
        save(entries)
        return entries
    }

    /// Removes every stored search.
    func clear() {
        store.removeValue(forKey: Self.key)
    }

    private func save(_ entries: [String]) {
        if entries.isEmpty {
            store.removeValue(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(entries) {
            store.set(data, forKey: Self.key)
        }
    }
}

// MARK: - SearchSuggestion

/// The suggested queries shown while the search field is empty (PROMPT.md section 6.4). The
/// query is the localized text, so translators can adapt it to how customers search.
enum SearchSuggestion: String, CaseIterable, Identifiable, Sendable {
    /// "Office 2024".
    case office2024
    /// "Windows 11 Pro".
    case windows11Pro
    /// "Windows Server".
    case windowsServer
    /// "Visual Studio".
    case visualStudio

    /// Stable identity for `ForEach`.
    var id: String {
        rawValue
    }

    /// The query in the user's language.
    var query: String {
        query(in: SearchResources.bundle)
    }

    /// The query resolved against `bundle`: the module bundle or one of its `.lproj` folders.
    func query(in bundle: Bundle) -> String {
        String(localized: queryKey, bundle: bundle)
    }

    private var queryKey: String.LocalizationValue {
        switch self {
        case .office2024: "search.suggestion.office_2024"
        case .windows11Pro: "search.suggestion.windows_11_pro"
        case .windowsServer: "search.suggestion.windows_server"
        case .visualStudio: "search.suggestion.visual_studio"
        }
    }
}

// MARK: - SearchCategoryShortcut

/// The category shortcuts of the search screen: the main collections of the store
/// (docs/STORE_AUDIT.md), shown while the field is empty and when nothing was found.
enum SearchCategoryShortcut: String, CaseIterable, Identifiable, Sendable {
    /// Collection `windows`.
    case windows
    /// Collection `microsoft-office`.
    case office
    /// Collection `windows-server`.
    case server
    /// Collection `visual-studio-entwicklungstools`.
    case development
    /// Collection `sale`.
    case deals

    /// Stable identity for `ForEach`.
    var id: String {
        rawValue
    }

    /// The collection handle the shortcut opens.
    var handle: String {
        switch self {
        case .windows: "windows"
        case .office: "microsoft-office"
        case .server: "windows-server"
        case .development: "visual-studio-entwicklungstools"
        case .deals: "sale"
        }
    }

    /// The decorative SF Symbol.
    var systemImage: String {
        switch self {
        case .windows: "macwindow"
        case .office: "doc.richtext"
        case .server: "server.rack"
        case .development: "chevron.left.forwardslash.chevron.right"
        case .deals: "tag"
        }
    }

    /// The title in the user's language.
    var title: String {
        title(in: SearchResources.bundle)
    }

    /// The title resolved against `bundle`: the module bundle or one of its `.lproj` folders.
    func title(in bundle: Bundle) -> String {
        String(localized: titleKey, bundle: bundle)
    }

    private var titleKey: String.LocalizationValue {
        switch self {
        case .windows: "search.category.windows"
        case .office: "search.category.office"
        case .server: "search.category.server"
        case .development: "search.category.development"
        case .deals: "search.category.deals"
        }
    }
}

// MARK: - SearchResultSortOption

/// The sort orders of the full search results, in menu order.
enum SearchResultSortOption: String, CaseIterable, Identifiable, Sendable {
    /// "Relevanz".
    case relevance
    /// "Preis aufsteigend".
    case priceAscending
    /// "Preis absteigend".
    case priceDescending

    /// Stable identity for `ForEach`.
    var id: String {
        rawValue
    }

    /// The Storefront sort key.
    var sortKey: SearchSortKey {
        switch self {
        case .relevance: .relevance
        case .priceAscending, .priceDescending: .price
        }
    }

    /// Whether the order is reversed (price high to low).
    var reverse: Bool {
        self == .priceDescending
    }

    /// The menu title in the user's language.
    var title: String {
        title(in: SearchResources.bundle)
    }

    /// The menu title resolved against `bundle`.
    func title(in bundle: Bundle) -> String {
        String(localized: titleKey, bundle: bundle)
    }

    private var titleKey: String.LocalizationValue {
        switch self {
        case .relevance: "search.sort.relevance"
        case .priceAscending: "search.sort.price_ascending"
        case .priceDescending: "search.sort.price_descending"
        }
    }
}
