import Foundation
@testable import ShopifyKit
import Testing

/// Static checks of the operation documents. The documents themselves were validated against
/// the live Storefront API 2026-07 on 2026-09-26 (the fixtures are their real responses).
@Suite("Operation documents")
struct OperationDocumentTests {
    struct Document: CustomTestStringConvertible, Sendable {
        let name: String
        let keyword: String
        let text: String

        var testDescription: String { name }
    }

    static let documents = [
        Document(name: LocalizationQuery.operationName, keyword: "query", text: LocalizationQuery.document),
        Document(name: ProductByHandleQuery.operationName, keyword: "query", text: ProductByHandleQuery.document),
        Document(name: CollectionProductsQuery.operationName, keyword: "query", text: CollectionProductsQuery.document),
        Document(name: CartCreateMutation.operationName, keyword: "mutation", text: CartCreateMutation.document),
    ]

    @Test("The operation comes first and carries the operation name", arguments: documents)
    func operationFirst(document: Document) {
        #expect(document.text.hasPrefix("\(document.keyword) \(document.name)"))
        #expect(!document.text.contains("@inContext"))
    }

    @Test("Every spread fragment is defined exactly once and every defined fragment is used", arguments: documents)
    func fragmentsMatch(document: Document) {
        let spreads = Set(Self.matches(of: #"\.\.\.([A-Za-z_][A-Za-z0-9_]*)"#, in: document.text))
        let definitions = Self.matches(of: #"fragment ([A-Za-z_][A-Za-z0-9_]*) on"#, in: document.text)
        #expect(Set(definitions) == spreads)
        #expect(definitions.count == Set(definitions).count)
    }

    @Test("Kinds match the documents")
    func kinds() {
        #expect(LocalizationQuery.kind == .query)
        #expect(ProductByHandleQuery.kind == .query)
        #expect(CollectionProductsQuery.kind == .query)
        #expect(CartCreateMutation.kind == .mutation)
    }

    @Test("The product query only selects metafields behind @include")
    func metafieldsAreConditional() {
        #expect(ProductByHandleQuery.document.contains("metafields(identifiers: $metafieldIdentifiers) @include(if: $includeMetafields)"))
        #expect(ProductByHandleQuery.document.components(separatedBy: "metafields(").count == 2)
    }

    @Test("The cart mutation requests user errors and warnings")
    func cartSelections() {
        #expect(CartCreateMutation.document.contains("userErrors {\n      field\n      message\n      code\n    }"))
        #expect(CartCreateMutation.document.contains("warnings {\n      code\n      message\n      target\n    }"))
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
