import Foundation
import Testing

// MARK: - LocalizedStrings

/// The strings of one feature module in one language, independent of the simulator language.
///
/// Xcode compiles each String Catalog into `<language>.lproj` folders inside the module's
/// resource bundle; this type opens one of them as a bundle of its own.
struct LocalizedStrings {
    /// The `.lproj` folder as a bundle. Pass it to the content types' `text(in:)` functions.
    let bundle: Bundle

    /// Opens the `.lproj` folder of `language` (for example `de` or `en`) in `moduleBundle`.
    init(language: String, in moduleBundle: Bundle) throws {
        let path = try #require(
            moduleBundle.path(forResource: language, ofType: "lproj"),
            "\(moduleBundle.bundlePath) has no \(language).lproj folder"
        )
        bundle = try #require(Bundle(path: path))
    }

    /// The value of `key`. Foundation returns the key itself when the catalog has no value.
    func callAsFunction(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

// MARK: - Copy rules

/// Whether `text` contains an en dash or an em dash, which app copy never uses (contract rule 6).
func containsForbiddenDash(_ text: String) -> Bool {
    text.contains("\u{2013}") || text.contains("\u{2014}")
}

/// The languages whose values the feature catalogs carry in Phase 0.
let phaseZeroLanguages = ["de", "en"]
