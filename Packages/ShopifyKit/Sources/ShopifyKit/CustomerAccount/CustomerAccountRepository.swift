import Core
import Foundation

// MARK: - CustomerAccountAPIClient

/// Runs Customer Account API operations with the customer's access token.
///
/// The GraphQL URL comes from discovery, and the access token is sent as the raw
/// `Authorization` header value, as the Customer Account API expects (no `Bearer` prefix).
/// When Shopify answers 401 or 403, the token is refreshed and the operation is sent once
/// more; Shopify rejected the first request before executing it, so this is safe for
/// mutations too.
public final class CustomerAccountAPIClient: Sendable {
    private let discovery: CustomerAccountDiscovery
    private let session: CustomerAccountSession
    private let httpClient: any HTTPClient
    private let logger: KXLogger
    private let clients = Locked<[URL: GraphQLClient]>([:])

    /// Creates the client.
    public init(
        discovery: CustomerAccountDiscovery,
        session: CustomerAccountSession,
        httpClient: any HTTPClient,
        logger: KXLogger = KXLogger(category: .customerAccount)
    ) {
        self.discovery = discovery
        self.session = session
        self.httpClient = httpClient
        self.logger = logger
    }

    /// Executes `operation`.
    ///
    /// - Throws: `CustomerAccountAuthError` for discovery and token problems (`.signedOut`
    ///   when nobody is signed in), `ShopifyError` for the call itself.
    public func execute<O: GraphQLOperation>(_ operation: O) async throws -> O.ResponseData {
        let client = try await graphQLClient()
        do {
            return try await client.execute(operation)
        } catch ShopifyError.accessDenied {
            logger.notice("\(O.operationName) was denied; refreshing the access token once")
            await session.invalidateAccessToken()
            return try await client.execute(operation)
        }
    }

    private func graphQLClient() async throws -> GraphQLClient {
        let url = try await discovery.endpoints().graphQLEndpoint
        if let existing = clients.withLock({ $0[url] }) {
            return existing
        }
        let session = session
        let endpoint = GraphQLEndpoint(url: url) {
            try await ["Authorization": session.accessToken()]
        }
        let client = GraphQLClient(endpoint: endpoint, httpClient: httpClient, logger: logger)
        return clients.withLock { cache in
            if let existing = cache[url] {
                return existing
            }
            cache[url] = client
            return client
        }
    }
}

// MARK: - Results

/// One page of orders.
public struct CustomerOrderPage: Sendable, Hashable {
    /// The orders, newest first.
    public let orders: [CustomerOrder]
    /// The cursor of the next page, `nil` on the last page.
    public let nextCursor: String?

    /// Creates a page.
    public init(orders: [CustomerOrder], nextCursor: String?) {
        self.orders = orders
        self.nextCursor = nextCursor
    }
}

/// The customer's addresses.
public struct CustomerAddressBook: Sendable, Hashable {
    /// The addresses.
    public let addresses: [CustomerAddress]
    /// The default address, if any.
    public let defaultAddressID: ShopifyID?

    /// Creates the address book.
    public init(addresses: [CustomerAddress], defaultAddressID: ShopifyID?) {
        self.addresses = addresses
        self.defaultAddressID = defaultAddressID
    }
}

// MARK: - CustomerAccountRepository

/// The customer-scoped data of the account screens. Read-only toward everything except the
/// customer's own addresses (PROMPT.md 3.9).
public protocol CustomerAccountRepository: Sendable {
    /// The signed-in customer.
    func customer() async throws -> Customer
    /// A page of orders, newest first.
    func orders(first: Int, after: String?) async throws -> CustomerOrderPage
    /// One order, or `nil` when it does not exist or belongs to someone else.
    func order(id: ShopifyID) async throws -> CustomerOrder?
    /// The addresses.
    func addresses() async throws -> CustomerAddressBook
    /// Adds an address. Throws `ShopifyError.userErrors` with Shopify's messages.
    func createAddress(_ address: CustomerAddressInput, makeDefault: Bool) async throws -> CustomerAddress
    /// Changes an address. Throws `ShopifyError.userErrors` with Shopify's messages.
    func updateAddress(id: ShopifyID, with address: CustomerAddressInput, makeDefault: Bool) async throws -> CustomerAddress
    /// Deletes an address.
    func deleteAddress(id: ShopifyID) async throws
}

// MARK: - ShopifyCustomerAccountRepository

/// `CustomerAccountRepository` on the Customer Account API.
public final class ShopifyCustomerAccountRepository: CustomerAccountRepository {
    private let client: CustomerAccountAPIClient

    /// Creates the repository.
    public init(client: CustomerAccountAPIClient) {
        self.client = client
    }

    public func customer() async throws -> Customer {
        try await client.execute(CustomerQuery()).customer
    }

    public func orders(first: Int, after: String?) async throws -> CustomerOrderPage {
        let orders = try await client.execute(CustomerOrdersQuery(first: first, after: after)).customer.orders
        return CustomerOrderPage(orders: orders.nodes, nextCursor: orders.pageInfo?.nextPageCursor)
    }

    public func order(id: ShopifyID) async throws -> CustomerOrder? {
        try await client.execute(CustomerOrderQuery(id: id)).order
    }

    public func addresses() async throws -> CustomerAddressBook {
        let customer = try await client.execute(CustomerAddressesQuery()).customer
        return CustomerAddressBook(addresses: customer.addresses.nodes, defaultAddressID: customer.defaultAddress?.id)
    }

    public func createAddress(_ address: CustomerAddressInput, makeDefault: Bool) async throws -> CustomerAddress {
        let payload = try await client.execute(CustomerAddressCreateMutation(address: address, defaultAddress: makeDefault))
            .customerAddressCreate.throwingUserErrors()
        guard let created = payload.customerAddress else { throw ShopifyError.notFound }
        return created
    }

    public func updateAddress(id: ShopifyID, with address: CustomerAddressInput, makeDefault: Bool) async throws -> CustomerAddress {
        let mutation = CustomerAddressUpdateMutation(addressID: id, address: address, defaultAddress: makeDefault)
        let payload = try await client.execute(mutation).customerAddressUpdate.throwingUserErrors()
        guard let updated = payload.customerAddress else { throw ShopifyError.notFound }
        return updated
    }

    public func deleteAddress(id: ShopifyID) async throws {
        try await client.execute(CustomerAddressDeleteMutation(addressID: id)).customerAddressDelete.throwingUserErrors()
    }
}

// MARK: - UnavailableCustomerAccountRepository

/// The repository of builds without login (no client ID or shop ID): every call throws
/// `CustomerAccountAuthError.signedOut`, so account screens show the signed-out state.
public struct UnavailableCustomerAccountRepository: CustomerAccountRepository {
    /// Creates the repository.
    public init() {}

    public func customer() async throws -> Customer {
        throw CustomerAccountAuthError.signedOut
    }

    public func orders(first _: Int, after _: String?) async throws -> CustomerOrderPage {
        throw CustomerAccountAuthError.signedOut
    }

    public func order(id _: ShopifyID) async throws -> CustomerOrder? {
        throw CustomerAccountAuthError.signedOut
    }

    public func addresses() async throws -> CustomerAddressBook {
        throw CustomerAccountAuthError.signedOut
    }

    public func createAddress(_: CustomerAddressInput, makeDefault _: Bool) async throws -> CustomerAddress {
        throw CustomerAccountAuthError.signedOut
    }

    public func updateAddress(id _: ShopifyID, with _: CustomerAddressInput, makeDefault _: Bool) async throws -> CustomerAddress {
        throw CustomerAccountAuthError.signedOut
    }

    public func deleteAddress(id _: ShopifyID) async throws {
        throw CustomerAccountAuthError.signedOut
    }
}
