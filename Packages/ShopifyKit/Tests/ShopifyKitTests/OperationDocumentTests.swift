import Foundation
@testable import ShopifyKit
import Testing

/// Static checks of the operation documents. The documents themselves were validated against
/// the live Storefront API 2026-10 on 2026-10-24 (the fixtures are their real responses).
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
        Document(name: CartQuery.operationName, keyword: "query", text: CartQuery.document),
        Document(name: CartLinesAddMutation.operationName, keyword: "mutation", text: CartLinesAddMutation.document),
        Document(name: CartLinesUpdateMutation.operationName, keyword: "mutation", text: CartLinesUpdateMutation.document),
        Document(name: CartLinesRemoveMutation.operationName, keyword: "mutation", text: CartLinesRemoveMutation.document),
        Document(
            name: CartDiscountCodesUpdateMutation.operationName,
            keyword: "mutation",
            text: CartDiscountCodesUpdateMutation.document
        ),
        Document(
            name: CartBuyerIdentityUpdateMutation.operationName,
            keyword: "mutation",
            text: CartBuyerIdentityUpdateMutation.document
        ),
        Document(name: CartAttributesUpdateMutation.operationName, keyword: "mutation", text: CartAttributesUpdateMutation.document),
        Document(name: CollectionsQuery.operationName, keyword: "query", text: CollectionsQuery.document),
        Document(name: ProductRecommendationsQuery.operationName, keyword: "query", text: ProductRecommendationsQuery.document),
        Document(name: ProductsByIDQuery.operationName, keyword: "query", text: ProductsByIDQuery.document),
        Document(name: PredictiveSearchQuery.operationName, keyword: "query", text: PredictiveSearchQuery.document),
        Document(name: SearchProductsQuery.operationName, keyword: "query", text: SearchProductsQuery.document),
        Document(name: BlogArticlesQuery.operationName, keyword: "query", text: BlogArticlesQuery.document),
        Document(name: ArticleQuery.operationName, keyword: "query", text: ArticleQuery.document),
        Document(name: PaymentSettingsQuery.operationName, keyword: "query", text: PaymentSettingsQuery.document),
    ]

    static let cartMutationDocuments = documents.filter { $0.keyword == "mutation" }

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
        #expect(CartQuery.kind == .query)
        #expect(CartLinesAddMutation.kind == .mutation)
        #expect(CartLinesUpdateMutation.kind == .mutation)
        #expect(CartLinesRemoveMutation.kind == .mutation)
        #expect(CartDiscountCodesUpdateMutation.kind == .mutation)
        #expect(CartBuyerIdentityUpdateMutation.kind == .mutation)
        #expect(CartAttributesUpdateMutation.kind == .mutation)
        #expect(CollectionsQuery.kind == .query)
        #expect(ProductRecommendationsQuery.kind == .query)
        #expect(ProductsByIDQuery.kind == .query)
        #expect(PredictiveSearchQuery.kind == .query)
        #expect(SearchProductsQuery.kind == .query)
        #expect(BlogArticlesQuery.kind == .query)
        #expect(ArticleQuery.kind == .query)
        #expect(PaymentSettingsQuery.kind == .query)
    }

    @Test("Every cart operation selects the shared CartFields fragment", arguments: cartMutationDocuments)
    func cartFields(document: Document) {
        #expect(document.text.contains("cart {\n      ...CartFields\n    }"))
        #expect(document.text.contains(StorefrontFragments.cart))
        #expect(document.text.contains("userErrors {\n      field\n      message\n      code\n    }"))
        #expect(document.text.contains("warnings {\n      code\n      message\n      target\n    }"))
    }

    @Test("The cart fragment uses the 2026-10 discount fields and no deprecated cart fields")
    func cartFragment() {
        let fragment = StorefrontFragments.cart
        #expect(fragment.contains("discountApplications {"))
        #expect(fragment.contains("discountAllocations {"))
        #expect(!fragment.contains("totalTaxAmount"))
        #expect(!fragment.contains("estimatedCost"))
        #expect(fragment.components(separatedBy: "discountAllocations").count == 2)
        #expect(CartQuery.document.contains("cart(id: $id) {\n    ...CartFields\n  }"))
    }

    @Test("The article query never selects the author's e-mail address")
    func articleAuthor() {
        #expect(ArticleQuery.document.contains("authorV2 {\n        name\n      }"))
        #expect(!ArticleQuery.document.contains("email"))
    }

    @Test("The product query only selects metafields behind @include")
    func metafieldsAreConditional() {
        #expect(ProductByHandleQuery.document.contains("metafields(identifiers: $metafieldIdentifiers) @include(if: $includeMetafields)"))
        #expect(ProductByHandleQuery.document.components(separatedBy: "metafields(").count == 2)
        #expect(
            ProductByHandleQuery.document.contains(
                #"linkedProducts: metafield(namespace: "custom", key: "siblings") @include(if: $includeMetafields)"#
            )
        )
        #expect(ProductByHandleQuery.document.components(separatedBy: "metafield(").count == 2)
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
