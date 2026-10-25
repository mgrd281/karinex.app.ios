import Foundation
@testable import ShopifyKit
import Testing

@Suite("ProductMetafields")
struct ProductMetafieldsTests {
    private typealias ID = ProductMetafields.Identifier

    private func metafields(_ fields: [(MetafieldIdentifier, String, String)]) -> ProductMetafields {
        ProductMetafields(fields.map { Metafield(namespace: $0.0.namespace, key: $0.0.key, type: $0.1, value: $0.2) })
    }

    @Test("Identifier constants cover PROMPT 5.1 and the existing store keys")
    func identifiers() {
        let names = Set(ProductMetafields.allIdentifiers.map(\.description))
        #expect(names == [
            "karinex.faq", "karinex.lizenztyp", "karinex.architektur", "karinex.geraeteanzahl", "karinex.lieferform",
            "karinex.aktivierungsart", "karinex.sprachen", "karinex.support_status", "custom.details_content",
            "custom.shipping_content", "custom.warranty_content", "custom.mpn", "karinex.deal_ends_at",
            "custom.angebotsende", "mm-google-shopping.mpn", "karinex.lowest_price_30d",
        ])
        #expect(ProductMetafields.allIdentifiers.count == names.count)
    }

    @Test("FAQ JSON is parsed; blank and repeated entries are dropped")
    func faq() {
        let json = """
            [{"question": " Wie aktiviere ich? ", "answer": "Datei > Konto > Product Key eingeben."},
             {"question": "Leer", "answer": "  "},
             {"question": "Wie aktiviere ich?", "answer": "Duplikat"},
             {"frage": "falsch"},
             "kein Objekt",
             {"question": "Wie schnell kommt der Key?", "answer": "In wenigen Minuten per E-Mail."}]
            """
        let entries = metafields([(ID.faq, "json", json)]).faq
        #expect(entries == [
            FAQEntry(question: "Wie aktiviere ich?", answer: "Datei > Konto > Product Key eingeben."),
            FAQEntry(question: "Wie schnell kommt der Key?", answer: "In wenigen Minuten per E-Mail."),
        ])
        #expect(entries?.first?.id == "Wie aktiviere ich?")
    }

    @Test("Invalid FAQ values are nil, an empty array is empty", arguments: ["", "not json", "{\"question\": \"q\"}", "[1, 2"])
    func invalidFAQ(value: String) {
        #expect(metafields([(ID.faq, "json", value)]).faq == nil)
    }

    @Test("Empty FAQ array and missing metafields")
    func emptyAndMissing() {
        #expect(metafields([(ID.faq, "json", "[]")]).faq == [])
        let none = ProductMetafields([])
        #expect(none.isEmpty)
        #expect(none.faq == nil)
        #expect(none.licenseType == nil)
        #expect(none.dealEndsAt == nil)
        #expect(none.detailsContent == nil)
        #expect(none.lowestPrice30Days(currency: .eur) == nil)
    }

    @Test("Text accessors trim and treat blanks as missing")
    func strings() {
        let values = metafields([
            (ID.licenseType, "single_line_text_field", " Dauerlizenz "),
            (ID.architecture, "single_line_text_field", "   "),
            (ID.deviceCount, "number_integer", "1"),
            (ID.deliveryForm, "single_line_text_field", "Download"),
            (ID.activationMethod, "single_line_text_field", "Online"),
            (ID.supportStatus, "single_line_text_field", "Unterstützt bis 2029"),
        ])
        #expect(values.licenseType == "Dauerlizenz")
        #expect(values.architecture == nil)
        #expect(values.deviceCount == "1")
        #expect(values.integer(ID.deviceCount) == 1)
        #expect(values.deliveryForm == "Download")
        #expect(values.activationMethod == "Online")
        #expect(values.supportStatus == "Unterstützt bis 2029")
    }

    @Test("List metafields")
    func lists() {
        let values = metafields([
            (ID.languages, "list.single_line_text_field", #"["Deutsch", " Englisch ", ""]"#),
            (ID.deviceCount, "list.number_integer", "[1, 5]"),
            (ID.architecture, "list.single_line_text_field", "not json"),
        ])
        #expect(values.languages == ["Deutsch", "Englisch"])
        #expect(values.string(ID.languages) == "Deutsch, Englisch")
        #expect(values.strings(ID.deviceCount) == ["1", "5"])
        #expect(values.architecture == nil)
        #expect(metafields([(ID.languages, "single_line_text_field", "Deutsch")]).languages == ["Deutsch"])
    }

    @Test("date_time values in ISO 8601; the existing offer end is the fallback")
    func dates() {
        let utc = metafields([(ID.dealEndsAt, "date_time", "2026-10-01T22:00:00Z")])
        #expect(utc.dealEndsAt == Date(timeIntervalSince1970: 1_790_892_000))

        let offset = metafields([(ID.dealEndsAt, "date_time", "2026-10-02T00:00:00+02:00")])
        #expect(offset.dealEndsAt == Date(timeIntervalSince1970: 1_790_892_000))

        let fractional = metafields([(ID.dealEndsAt, "date_time", "2026-10-01T22:00:00.500Z")])
        #expect(fractional.dealEndsAt == Date(timeIntervalSince1970: 1_790_892_000.5))

        let fallback = metafields([(ID.offerEndsAt, "date_time", "2026-10-01T22:00:00Z")])
        #expect(fallback.dealEndsAt == Date(timeIntervalSince1970: 1_790_892_000))

        let dateOnly = metafields([(ID.dealEndsAt, "date", "2026-10-02")])
        #expect(dateOnly.dealEndsAt == Date(timeIntervalSince1970: 1_790_892_000))

        #expect(metafields([(ID.dealEndsAt, "date_time", "morgen")]).dealEndsAt == nil)
        #expect(metafields([(ID.dealEndsAt, "date_time", "2026-13-45T99:00:00Z")]).dealEndsAt == nil)
    }

    @Test("MPN prefers custom.mpn and falls back to the Google Shopping MPN")
    func mpn() {
        #expect(metafields([(ID.googleShoppingMPN, "single_line_text_field", "DG7GMGF0D7FV")]).mpn == "DG7GMGF0D7FV")
        #expect(
            metafields([
                (ID.mpn, "single_line_text_field", "MPN-1"),
                (ID.googleShoppingMPN, "single_line_text_field", "MPN-2"),
            ]).mpn == "MPN-1"
        )
    }

    @Test("Rich text, HTML and plain text contents")
    func contents() {
        let richText = """
            {"type":"root","children":[
              {"type":"heading","level":2,"children":[{"type":"text","value":"Aktivierung"}]},
              {"type":"paragraph","children":[{"type":"text","value":"Öffnen Sie "},{"type":"text","value":"Word","bold":true},
                {"type":"text","value":"."}]},
              {"type":"list","listType":"ordered","children":[
                {"type":"list-item","children":[{"type":"text","value":"Datei"}]},
                {"type":"list-item","children":[{"type":"link","url":"https://www.karinex.de","title":"KARINEX",
                  "children":[{"type":"text","value":"Konto"}]}]}]}
            ]}
            """
        let values = metafields([
            (ID.detailsContent, "rich_text_field", richText),
            (ID.shippingContent, "multi_line_text_field", "<p>Lieferung per <strong>E-Mail</strong></p>"),
            (ID.warrantyContent, "multi_line_text_field", "Gesetzliche Gewährleistung, 2 < 3 > 1"),
        ])

        guard case let .richText(node)? = values.detailsContent else {
            Issue.record("Expected rich text")
            return
        }
        #expect(node.type == "root")
        #expect(node.children.first?.level == 2)
        #expect(node.plainText == "Aktivierung\nÖffnen Sie Word.\nDatei\nKonto")
        #expect(values.string(ID.detailsContent) == "Aktivierung\nÖffnen Sie Word.\nDatei\nKonto")
        #expect(values.shippingContent == .html("<p>Lieferung per <strong>E-Mail</strong></p>"))
        #expect(values.warrantyContent == .plainText("Gesetzliche Gewährleistung, 2 < 3 > 1"))
        #expect(metafields([(ID.detailsContent, "rich_text_field", "{\"type\":\"paragraph\"}")]).detailsContent == nil)
        #expect(metafields([(ID.detailsContent, "rich_text_field", "kaputt")]).detailsContent == nil)
    }

    @Test("Lowest price of 30 days as money JSON or plain decimal")
    func lowestPrice() {
        let money = metafields([(ID.lowestPrice30Days, "money", #"{"amount":"24.90","currency_code":"EUR"}"#)])
        #expect(money.lowestPrice30Days(currency: .chf) == MoneyV2(amount: decimal("24.9"), currencyCode: .eur))

        let number = metafields([(ID.lowestPrice30Days, "number_decimal", "24.90")])
        #expect(number.lowestPrice30Days(currency: .eur) == MoneyV2(amount: decimal("24.9"), currencyCode: .eur))

        #expect(metafields([(ID.lowestPrice30Days, "money", "{}")]).lowestPrice30Days(currency: .eur) == nil)
        #expect(metafields([(ID.lowestPrice30Days, "number_decimal", "24,90")]).lowestPrice30Days(currency: .eur) == nil)
    }

    @Test("Products decode metafields from a nullable array and drop nulls")
    func productDecodingDropsNulls() throws {
        let json = """
            {"id":"gid://shopify/Product/1","handle":"h","title":"T","vendor":"V","productType":"P","tags":[],
             "availableForSale":true,"descriptionHtml":"","featuredImage":null,"images":{"nodes":[]},"options":[],
             "variants":{"nodes":[]},"seo":{"title":null,"description":null},"collections":{"nodes":[]},
             "priceRange":{"minVariantPrice":{"amount":"1.0","currencyCode":"EUR"},"maxVariantPrice":{"amount":"1.0","currencyCode":"EUR"}},
             "compareAtPriceRange":{"minVariantPrice":{"amount":"0.0","currencyCode":"EUR"},
               "maxVariantPrice":{"amount":"0.0","currencyCode":"EUR"}},
             "onlineStoreUrl":null,
             "metafields":[null,{"namespace":"karinex","key":"lizenztyp","type":"single_line_text_field","value":"Dauerlizenz"},null]}
            """
        let product = try JSONDecoder().decode(Product.self, from: Data(json.utf8))
        #expect(product.metafields.count == 1)
        #expect(product.productMetafields.licenseType == "Dauerlizenz")
        #expect(product.compareAtPriceRange.isZero)
        #expect(!product.isDigitalOnly)
        #expect(product.defaultVariant == nil)
    }
}
