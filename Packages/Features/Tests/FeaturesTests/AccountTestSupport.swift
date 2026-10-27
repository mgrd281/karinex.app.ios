import BackendKit
import Foundation
import ShopifyKit

// MARK: - AccountFixtures

/// Sample orders, addresses and keys for the account tests.
enum AccountFixtures {
    static func money(_ amount: Decimal) -> MoneyV2 {
        MoneyV2(amount: amount, currencyCode: .eur)
    }

    static func order(
        _ number: Int,
        financial: OrderFinancialStatus? = .paid,
        fulfillment: OrderFulfillmentStatus? = .unfulfilled,
        cancelled: Bool = false,
        fulfillments: [OrderFulfillment] = []
    ) -> CustomerOrder {
        CustomerOrder(
            id: ShopifyID("gid://shopify/Order/\(number)"),
            name: "#\(number)",
            confirmationNumber: nil,
            processedAt: Date(timeIntervalSince1970: 1_790_000_000),
            cancelledAt: cancelled ? Date(timeIntervalSince1970: 1_790_100_000) : nil,
            financialStatus: financial,
            fulfillmentStatus: fulfillment,
            totalPrice: money(119.9),
            subtotal: money(100.76),
            totalTax: money(19.14),
            totalShipping: money(0),
            lineItems: [],
            fulfillments: fulfillments
        )
    }

    static func address(_ id: Int, city: String = "Hamburg") -> CustomerAddress {
        CustomerAddress(
            id: ShopifyID("gid://shopify/CustomerAddress/\(id)"),
            firstName: "Anna",
            lastName: "Schmidt",
            company: nil,
            address1: "Hauptstraße 1",
            address2: nil,
            zip: "22115",
            city: city,
            province: nil,
            zoneCode: nil,
            country: "Deutschland",
            territoryCode: "DE"
        )
    }

    static func key(orderID: String, line: String) -> LicenseKey {
        LicenseKey(
            lineItemID: line,
            productTitle: "Office 2024 Professional Plus",
            sku: nil,
            key: "AAAAA-BBBBB-CCCCC-DDDDD-\(line)EEEE",
            deliveredAt: Date(timeIntervalSince1970: 1_790_000_000),
            activationGuideURL: nil,
            orderID: orderID
        )
    }

    static func legalText(_ handle: String, title: String) -> LegalText {
        LegalText(
            id: ShopifyID("gid://shopify/Page/\(handle)"),
            title: title,
            handle: handle,
            body: "<p>\(title)</p>",
            updatedAt: nil,
            url: nil
        )
    }
}

// MARK: - StubBackend

/// A `BackendClient` with configurable answers that records the calls.
actor StubBackend: BackendClient {
    var config: RemoteAppConfig = .fallback
    var orderStatuses: Result<[BackendOrderStatus], BackendError> = .success([])
    var licensesByOrder: [String: LicenseDelivery] = [:]
    var licenseFailure: BackendError?
    var invoiceResult: Result<InvoiceLink, BackendError> = .failure(.notConfigured)
    var deletionResult: Result<String?, BackendError> = .success("r1")
    var loyaltyResult: Result<LoyaltyStatus, BackendError> = .failure(.notConfigured)
    var redeemResult: Result<LoyaltyRedeemCode, any Error> = .failure(BackendError.notConfigured)
    var walletPassResult: Result<Data, BackendError> = .failure(.notConfigured)
    private(set) var calls: [String] = []

    func setOrders(_ result: Result<[BackendOrderStatus], BackendError>) {
        orderStatuses = result
    }

    func setLicenses(_ delivery: LicenseDelivery, for orderID: String) {
        licensesByOrder[orderID] = delivery
    }

    func setLicenseFailure(_ error: BackendError?) {
        licenseFailure = error
    }

    func setDeletion(_ result: Result<String?, BackendError>) {
        deletionResult = result
    }

    func setLoyalty(_ result: Result<LoyaltyStatus, BackendError>) {
        loyaltyResult = result
    }

    func setRedeem(_ result: Result<LoyaltyRedeemCode, any Error>) {
        redeemResult = result
    }

    func setWalletPass(_ result: Result<Data, BackendError>) {
        walletPassResult = result
    }

    func setConfig(_ config: RemoteAppConfig) {
        self.config = config
    }

    func appConfig() async throws -> RemoteAppConfig {
        calls.append("config")
        return config
    }

    func orders() async throws -> [BackendOrderStatus] {
        calls.append("orders")
        return try orderStatuses.get()
    }

    func licenses(orderID: String) async throws -> LicenseDelivery {
        calls.append("licenses:\(orderID)")
        if let licenseFailure {
            throw licenseFailure
        }
        return licensesByOrder[orderID] ?? .delivered([])
    }

    func invoice(orderID: String) async throws -> InvoiceLink {
        calls.append("invoice:\(orderID)")
        return try invoiceResult.get()
    }

    func requestAccountDeletion() async throws -> String? {
        calls.append("delete")
        return try deletionResult.get()
    }

    func loyalty() async throws -> LoyaltyStatus {
        calls.append("loyalty")
        return try loyaltyResult.get()
    }

    func redeemLoyalty(points: Int, idempotencyKey: String) async throws -> LoyaltyRedeemCode {
        calls.append("redeem:\(points):\(idempotencyKey)")
        return try redeemResult.get()
    }

    func walletPass() async throws -> Data {
        calls.append("walletPass")
        return try walletPassResult.get()
    }

    func registerDevice(_: DeviceRegistration) async throws {
        calls.append("register")
    }

    func unregisterDevice(apnsToken _: String) async throws {
        calls.append("unregister")
    }
}

// MARK: - StubCustomerRepository

/// A `CustomerAccountRepository` with configurable pages, addresses and failures.
actor StubCustomerRepository: CustomerAccountRepository {
    var pages: [String?: CustomerOrderPage] = [:]
    var detail: CustomerOrder?
    var book = CustomerAddressBook(addresses: [], defaultAddressID: nil)
    var mutationError: (any Error)?
    private(set) var orderRequests: [String?] = []
    private(set) var created: [CustomerAddressInput] = []
    private(set) var deleted: [ShopifyID] = []
    private(set) var names: [String] = []

    func setPage(_ page: CustomerOrderPage, after cursor: String?) {
        pages[cursor] = page
    }

    func setBook(_ book: CustomerAddressBook) {
        self.book = book
    }

    func setMutationError(_ error: (any Error)?) {
        mutationError = error
    }

    func setDetail(_ order: CustomerOrder?) {
        detail = order
    }

    func customer() async throws -> Customer {
        Customer(
            id: "gid://shopify/Customer/1",
            displayName: "Anna Schmidt",
            firstName: "Anna",
            lastName: "Schmidt",
            emailAddress: nil,
            defaultAddress: nil
        )
    }

    func updateName(firstName: String, lastName: String) async throws -> Customer {
        if let mutationError {
            throw mutationError
        }
        names.append("\(firstName) \(lastName)")
        return Customer(
            id: "gid://shopify/Customer/1",
            displayName: "\(firstName) \(lastName)",
            firstName: firstName,
            lastName: lastName,
            emailAddress: nil,
            defaultAddress: nil
        )
    }

    func orders(first _: Int, after: String?) async throws -> CustomerOrderPage {
        orderRequests.append(after)
        return pages[after] ?? CustomerOrderPage(orders: [], nextCursor: nil)
    }

    func order(id _: ShopifyID) async throws -> CustomerOrder? {
        detail
    }

    func addresses() async throws -> CustomerAddressBook {
        book
    }

    func createAddress(_ address: CustomerAddressInput, makeDefault _: Bool) async throws -> CustomerAddress {
        if let mutationError {
            throw mutationError
        }
        created.append(address)
        let new = AccountFixtures.address(book.addresses.count + 1, city: address.city ?? "")
        book = CustomerAddressBook(addresses: book.addresses + [new], defaultAddressID: book.defaultAddressID)
        return new
    }

    func updateAddress(id: ShopifyID, with _: CustomerAddressInput, makeDefault: Bool) async throws -> CustomerAddress {
        if let mutationError {
            throw mutationError
        }
        if makeDefault {
            book = CustomerAddressBook(addresses: book.addresses, defaultAddressID: id)
        }
        return book.addresses.first { $0.id == id } ?? AccountFixtures.address(1)
    }

    func deleteAddress(id: ShopifyID) async throws {
        if let mutationError {
            throw mutationError
        }
        deleted.append(id)
        book = CustomerAddressBook(addresses: book.addresses.filter { $0.id != id }, defaultAddressID: book.defaultAddressID)
    }
}

// MARK: - StubLegalRepository

/// A `LegalContentRepository` with configurable pages and policies.
actor StubLegalRepository: LegalContentRepository {
    var pagesByHandle: [String: LegalText] = [:]
    var shopPolicies = ShopPolicies(privacyPolicy: nil, refundPolicy: nil, shippingPolicy: nil, termsOfService: nil)
    private(set) var requestedPages: [String] = []

    func setPage(_ text: LegalText) {
        pagesByHandle[text.handle] = text
    }

    func setPolicies(_ policies: ShopPolicies) {
        shopPolicies = policies
    }

    func policies() async throws -> ShopPolicies {
        shopPolicies
    }

    func page(handle: String) async throws -> LegalText? {
        requestedPages.append(handle)
        return pagesByHandle[handle]
    }
}
