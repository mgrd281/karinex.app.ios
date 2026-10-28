@testable import Core
import Foundation
import Testing

@Suite("AppLanguage")
struct AppLanguageTests {
    @Test("Covers exactly the 13 UI languages in catalog order")
    func allCases() {
        #expect(
            AppLanguage.allCases.map(\.rawValue)
                == ["de", "en", "pl", "nl", "pt-PT", "sv", "da", "es", "fr", "it", "fi", "ro", "el"]
        )
        #expect(AppLanguage.source == .de)
    }

    @Test(
        "Normalizes identifiers",
        arguments: [
            ("de", AppLanguage.de), ("DE", .de), ("de-AT", .de), ("de_CH", .de), ("de-DE@calendar=gregorian", .de),
            ("en", .en), ("en-GB", .en), ("en_US", .en), ("en-US.UTF-8", .en),
            ("pt", .ptPT), ("pt-BR", .ptPT), ("pt_PT", .ptPT), ("PT-pt", .ptPT),
            ("pl-PL", .pl), ("nl-BE", .nl), ("sv-FI", .sv), ("da", .da), ("es-419", .es),
            ("fr-CH", .fr), ("it-CH", .it), ("fi-FI", .fi), (" fr ", .fr),
            ("ro", .ro), ("ro-RO", .ro), ("ro_MD", .ro), ("el", .el), ("el-GR", .el), ("el_CY", .el),
        ]
    )
    func normalizes(identifier: String, expected: AppLanguage) {
        #expect(AppLanguage(bcp47: identifier) == expected)
    }

    @Test("Rejects languages the app does not ship", arguments: ["nb", "no", "cs", "zh-Hans", "", "-", "_"])
    func rejectsUnsupported(identifier: String) {
        #expect(AppLanguage(bcp47: identifier) == nil)
    }

    @Test("Picks the first supported preferred language")
    func preferred() {
        #expect(AppLanguage.preferred(from: ["nb-NO", "de-AT", "en-US"]) == .de)
        #expect(AppLanguage.preferred(from: ["pt-BR", "en"]) == .ptPT)
        #expect(AppLanguage.preferred(from: ["el", "ro"]) == .el)
        #expect(AppLanguage.preferred(from: ["nb", "cs"]) == nil)
        #expect(AppLanguage.preferred(from: []) == nil)
    }

    @Test("Endonyms are the native names")
    func endonyms() {
        #expect(AppLanguage.de.endonym == "Deutsch")
        #expect(AppLanguage.en.endonym == "English")
        #expect(AppLanguage.pl.endonym == "Polski")
        #expect(AppLanguage.nl.endonym == "Nederlands")
        #expect(AppLanguage.ptPT.endonym == "Português")
        #expect(AppLanguage.sv.endonym == "Svenska")
        #expect(AppLanguage.da.endonym == "Dansk")
        #expect(AppLanguage.es.endonym == "Español")
        #expect(AppLanguage.fr.endonym == "Français")
        #expect(AppLanguage.it.endonym == "Italiano")
        #expect(AppLanguage.fi.endonym == "Suomi")
        #expect(AppLanguage.ro.endonym == "Română")
        #expect(AppLanguage.el.endonym == "Ελληνικά")
    }

    @Test("Locales and language codes")
    func locales() {
        #expect(AppLanguage.ptPT.languageCode == "pt")
        #expect(AppLanguage.ptPT.locale.language.languageCode?.identifier == "pt")
        #expect(AppLanguage.fi.locale.language.languageCode?.identifier == "fi")
        #expect(AppLanguage.de.id == "de")
    }

    @Test("Round-trips through Codable as the BCP 47 identifier")
    func codable() throws {
        let data = try JSONEncoder().encode([AppLanguage.ptPT, .de])
        #expect(String(decoding: data, as: UTF8.self) == #"["pt-PT","de"]"#)
        #expect(try JSONDecoder().decode([AppLanguage].self, from: data) == [.ptPT, .de])
    }
}
