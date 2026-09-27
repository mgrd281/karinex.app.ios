import Foundation

/// The languages the app UI is localized into.
///
/// Raw values are the BCP 47 identifiers used by the String Catalogs and by
/// `CFBundleLocalizations`. German is the source language.
public enum AppLanguage: String, CaseIterable, Sendable, Codable {
    /// German, the source language.
    case de
    /// English, also the fallback for unsupported device languages.
    case en
    /// Polish.
    case pl
    /// Dutch.
    case nl
    /// European Portuguese. Brazilian Portuguese devices are served this localization too.
    case ptPT = "pt-PT"
    /// Swedish.
    case sv
    /// Danish.
    case da
    /// Spanish.
    case es
    /// French.
    case fr
    /// Italian.
    case it
    /// Finnish.
    case fi

    // MARK: - Constants

    /// The source language of all String Catalogs.
    public static let source: AppLanguage = .de

    // MARK: - Derived values

    /// A `Locale` for formatting in this language (without a region).
    public var locale: Locale {
        Locale(identifier: rawValue)
    }

    /// The ISO 639-1 language code without region, e.g. `pt` for European Portuguese.
    public var languageCode: String {
        switch self {
        case .ptPT: "pt"
        default: rawValue
        }
    }

    /// The language's own name for itself, as shown in a language picker.
    ///
    /// Endonyms are intentionally not localized: a language is always listed under the name
    /// its speakers recognize.
    public var endonym: String {
        switch self {
        case .de: "Deutsch"
        case .en: "English"
        case .pl: "Polski"
        case .nl: "Nederlands"
        case .ptPT: "Português"
        case .sv: "Svenska"
        case .da: "Dansk"
        case .es: "Español"
        case .fr: "Français"
        case .it: "Italiano"
        case .fi: "Suomi"
        }
    }

    // MARK: - Parsing

    /// Maps a BCP 47 or POSIX locale identifier to an app language.
    ///
    /// Matching is case-insensitive and only looks at the primary language subtag, so
    /// `de-AT`, `de_CH` and `DE` all map to `.de`. Every Portuguese variant (`pt`, `pt-BR`,
    /// `pt_PT`) maps to `.ptPT`, the only Portuguese localization. POSIX modifiers
    /// (`@calendar=...`) and encodings (`.UTF-8`) are ignored.
    ///
    /// - Returns: `nil` when the language is not one of the app languages.
    public init?(bcp47 identifier: String) {
        var normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let modifier = normalized.firstIndex(where: { $0 == "@" || $0 == "." }) {
            normalized = String(normalized[..<modifier])
        }
        let primary = normalized
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map { $0.lowercased() }
        guard let primary else { return nil }

        switch primary {
        case "pt":
            self = .ptPT
        default:
            guard let language = AppLanguage.allCases.first(where: { $0.languageCode == primary }) else {
                return nil
            }
            self = language
        }
    }

    /// Returns the first identifier in `identifiers` that maps to an app language.
    ///
    /// Pass `Locale.preferredLanguages` to honor the user's ordered language preferences.
    ///
    /// - Returns: `nil` when none of the identifiers is an app language.
    public static func preferred(from identifiers: [String]) -> AppLanguage? {
        for identifier in identifiers {
            if let language = AppLanguage(bcp47: identifier) {
                return language
            }
        }
        return nil
    }
}

// MARK: - Identifiable

extension AppLanguage: Identifiable {
    /// The BCP 47 identifier.
    public var id: String {
        rawValue
    }
}
