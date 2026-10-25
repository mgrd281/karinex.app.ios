import Core
import Foundation
@testable import ShopifyKit
import Testing

/// `ProductsByIDQuery` and `ProductLookupRepository`: the wishlist and recently viewed lists
/// keep only IDs and load the products fresh.
@Suite("Product lookup")
struct ProductLookupTests {
    private func context() -> StaticStorefrontContextProvider {
        StaticStorefrontContextProvider(context: germanyContext)
    }

    /// The recorded recommendations as a `nodes` answer with a deleted product (`null`) and a
    /// node of another type (`{}`) in front.
    private func nodesResponse() throws -> String {
        let text = try #require(String(data: Fixture.data(Fixture.recommendationsRelated), encoding: .utf8))
        let nodes = text.replacingOccurrences(of: #""productRecommendations": ["#, with: #""nodes": [null, {}, "#)
        #expect(nodes != text)
        return nodes
    }

    @Test("Missing and foreign nodes are left out")
    func decoding() throws {
        let data = try Data(nodesResponse().utf8)
        let response = try JSONDecoder().decode(GraphQLResponse<ProductsByIDQuery.ResponseData>.self, from: data)

        #expect(response.data?.products.count == 10)
    }

    @Test("IDs are de-duplicated and capped")
    func variables() {
        let ids = (0..<300).map { ShopifyID("gid://shopify/Product/\($0)") }
        let query = ProductsByIDQuery(ids: [ids[1], ids[1]] + ids)

        #expect(query.variables.ids.count == ProductsByIDQuery.maximumIDs)
        #expect(query.variables.ids.first == ids[1])
        #expect(query.variables.ids[1] == ids[0])
    }

    @Test("Products come back in the order of the IDs")
    func order() async throws {
        let decoded = try JSONDecoder().decode(
            GraphQLResponse<ProductsByIDQuery.ResponseData>.self,
            from: Data(nodesResponse().utf8)
        )
        let products = try #require(decoded.data?.products)
        let stub = try StubHTTPClient([.json(nodesResponse())])
        let repository = StorefrontCatalogRepository(client: makeStorefrontClient(stub), contextProvider: context())

        let loaded = try await repository.products(ids: [products[2].id, products[0].id])

        #expect(loaded.prefix(2).map(\.id) == [products[2].id, products[0].id])
        let body = try SentGraphQLBody(#require(stub.requests.first))
        #expect(body.variables["ids"] == .array([.string(products[2].id.rawValue), .string(products[0].id.rawValue)]))
    }

    @Test("An empty list makes no request")
    func empty() async throws {
        let stub = StubHTTPClient([])
        let repository = StorefrontCatalogRepository(client: makeStorefrontClient(stub), contextProvider: context())

        #expect(try await repository.products(ids: []).isEmpty)
        #expect(stub.requests.isEmpty)
    }
}
