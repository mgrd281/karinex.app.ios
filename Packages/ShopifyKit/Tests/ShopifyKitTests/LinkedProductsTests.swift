import Foundation
@testable import ShopifyKit
import Testing

/// `Product.linkedProducts`, read from the list metafield `custom.siblings`.
///
/// The recorded product is tokenless (no metafields), so these tests add a `linkedProducts`
/// member to it. Its products are the real summaries of the recorded `RELATED` recommendations.
@Suite("Linked products")
struct LinkedProductsTests {
    @Test("Tokenless products have no linked products")
    func tokenless() throws {
        let product = try #require(try Fixture.decode(ProductByHandleQuery.ResponseData.self, from: Fixture.productDE).product)
        #expect(product.linkedProducts.isEmpty)
    }

    @Test("Product references are kept in order; other references are dropped")
    func references() throws {
        let summaries = try Self.recordedSummaries()
        let product = try Self.product(linkedProducts: [
            "references": ["nodes": [summaries[0], [:], summaries[1]]],
        ])
        let related = try Self.relatedProducts()
        #expect(product.linkedProducts == [related[0], related[1]])
    }

    @Test("A missing or empty metafield means no linked products", arguments: [false, true])
    func missing(hasEmptyReferences: Bool) throws {
        let value: Any = if hasEmptyReferences {
            ["references": ["nodes": [Any]()]]
        } else {
            NSNull()
        }
        let product = try Self.product(linkedProducts: value)
        #expect(product.linkedProducts.isEmpty)
    }

    @Test("Linked products survive encoding")
    func roundTrip() throws {
        let summaries = try Self.recordedSummaries()
        let product = try Self.product(linkedProducts: ["references": ["nodes": Array(summaries.prefix(3))]])
        #expect(product.linkedProducts.count == 3)
        let reencoded = try JSONDecoder().decode(Product.self, from: JSONEncoder().encode(product))
        #expect(reencoded == product)
    }

    @Test("A loaded product converts into the summary of its list entries")
    func summaryOfProduct() throws {
        let product = try #require(try Fixture.decode(ProductByHandleQuery.ResponseData.self, from: Fixture.productDE).product)
        let summary = ProductSummary(product)
        #expect(summary.id == product.id)
        #expect(summary.handle == product.handle)
        #expect(summary.title == product.title)
        #expect(summary.vendor == product.vendor)
        #expect(summary.availableForSale == product.availableForSale)
        #expect(summary.featuredImage == product.featuredImage)
        #expect(summary.price == product.priceRange.minVariantPrice)
        #expect(summary.compareAtPrice == product.compareAtPriceRange.minVariantPrice)
        #expect(summary.requiresShipping == false)
    }

    // MARK: Helpers

    /// The recorded DE product with `linkedProducts` set to `value`.
    private static func product(linkedProducts value: Any) throws -> Product {
        let root = try #require(try JSONSerialization.jsonObject(with: Fixture.data(Fixture.productDE)) as? [String: Any])
        let data = try #require(root["data"] as? [String: Any])
        var product = try #require(data["product"] as? [String: Any])
        product["linkedProducts"] = value
        return try JSONDecoder().decode(Product.self, from: JSONSerialization.data(withJSONObject: product))
    }

    /// The raw product objects of the recorded `RELATED` recommendations.
    private static func recordedSummaries() throws -> [[String: Any]] {
        let root = try #require(
            try JSONSerialization.jsonObject(with: Fixture.data(Fixture.recommendationsRelated)) as? [String: Any]
        )
        let data = try #require(root["data"] as? [String: Any])
        return try #require(data["productRecommendations"] as? [[String: Any]])
    }

    /// The decoded `RELATED` recommendations.
    private static func relatedProducts() throws -> [ProductSummary] {
        try #require(
            try Fixture.decode(ProductRecommendationsQuery.ResponseData.self, from: Fixture.recommendationsRelated)
                .productRecommendations
        )
    }
}
