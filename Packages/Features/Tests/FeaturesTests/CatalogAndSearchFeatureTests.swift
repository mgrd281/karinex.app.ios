@testable import CatalogFeature
import Foundation
@testable import SearchFeature
import Testing

@Suite("Catalog and search strings")
struct CatalogAndSearchStringTests {
    @Test("The Shop placeholder explains where the range will appear")
    func catalogPlaceholder() throws {
        let german = try LocalizedStrings(language: "de", in: CatalogResources.bundle)

        #expect(german("catalog.title") == "Shop")
        #expect(german("catalog.empty.title") == "Das Sortiment wird hier angezeigt")
    }

    @Test("The search placeholder explains what search will offer")
    func searchPlaceholder() throws {
        let german = try LocalizedStrings(language: "de", in: SearchResources.bundle)

        #expect(german("search.title") == "Suche")
        #expect(german("search.empty.title") == "Die Suche wird hier angezeigt")
    }

    @Test("Every catalog and search text resolves without dashes", arguments: phaseZeroLanguages)
    func allTexts(language: String) throws {
        let catalog = try LocalizedStrings(language: language, in: CatalogResources.bundle)
        let search = try LocalizedStrings(language: language, in: SearchResources.bundle)
        let resolved = [
            ("catalog.title", catalog("catalog.title")),
            ("catalog.empty.title", catalog("catalog.empty.title")),
            ("catalog.empty.message", catalog("catalog.empty.message")),
            ("search.title", search("search.title")),
            ("search.empty.title", search("search.empty.title")),
            ("search.empty.message", search("search.empty.message")),
        ]

        for (key, text) in resolved {
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }
}
