@testable import CommerceUI
import Core
import Foundation
import ShopifyKit
import Testing

@Suite("UserFacingError")
struct UserFacingErrorTests {
    @Test("Shopify and network errors map to customer-facing kinds", arguments: [
        (ShopifyError.network(.offline) as any Error, UserFacingError.Kind.offline),
        (ShopifyError.network(.timeout), .timeout),
        (ShopifyError.network(.transport(code: -1200)), .server),
        (ShopifyError.throttled, .throttled),
        (ShopifyError.http(statusCode: 408), .timeout),
        (ShopifyError.http(statusCode: 429), .throttled),
        (ShopifyError.http(statusCode: 503), .server),
        (ShopifyError.http(statusCode: 404), .unknown),
        (ShopifyError.graphQL([GraphQLErrorDetail(message: "Internal error", code: "INTERNAL_SERVER_ERROR")]), .server),
        (ShopifyError.graphQL([GraphQLErrorDetail(message: "Field missing", code: nil)]), .unknown),
        (ShopifyError.notFound, .notFound),
        (ShopifyError.accessDenied(requiredAccess: "unauthenticated_read_metafields"), .unknown),
        (ShopifyError.decoding("Cart: lines"), .unknown),
        (NetworkError.offline, .offline),
        (NetworkError.httpStatus(code: 500, retryAfter: nil), .server),
        (URLError(.notConnectedToInternet), .offline),
        (URLError(.timedOut), .timeout),
        (UserFacingError(kind: .notFound), .notFound),
    ])
    func mapping(error: any Error, expected: UserFacingError.Kind) throws {
        let mapped = try #require(UserFacingError(error))
        #expect(mapped.kind == expected)
    }

    @Test("Cancellations are not errors", arguments: [
        ShopifyError.network(.cancelled) as any Error,
        NetworkError.cancelled,
        URLError(.cancelled),
        CancellationError(),
    ])
    func cancellation(error: any Error) {
        #expect(UserFacingError(error) == nil)
        #expect(UserFacingError.isCancellation(error))
    }

    @Test("User errors carry Shopify's messages and are not retryable")
    func userErrors() throws {
        let error = ShopifyError.userErrors([
            UserError(field: ["lines"], message: "Nicht genug Bestand.", code: .merchandiseNotEnoughStock),
            UserError(field: nil, message: "  ", code: nil),
            UserError(field: nil, message: "Bitte prüfen Sie die Menge.", code: .invalid),
        ])
        let mapped = try #require(UserFacingError(error))
        #expect(mapped.message == "Nicht genug Bestand.\nBitte prüfen Sie die Menge.")
        #expect(!mapped.isRetryable)
        #expect(!mapped.title.isEmpty)
    }

    @Test("Every kind has a localized title, message and symbol without dashes")
    func presentation() {
        let kinds: [UserFacingError.Kind] = [.offline, .timeout, .throttled, .server, .rejected(messages: []), .notFound, .unknown]
        for kind in kinds {
            let error = UserFacingError(kind: kind)
            #expect(!error.title.isEmpty)
            #expect(!error.message.isEmpty)
            #expect(!error.systemImage.isEmpty)
            #expect(!(error.title + error.message).contains("\u{2013}"))
            #expect(!(error.title + error.message).contains("\u{2014}"))
        }
        #expect(UserFacingError(kind: .offline).isRetryable)
        #expect(!UserFacingError(kind: .notFound).isRetryable)
        #expect(!UserFacingError.retryTitle.isEmpty)
    }
}
