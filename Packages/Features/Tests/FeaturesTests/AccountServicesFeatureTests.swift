@testable import AccountFeature
import BackendKit
import CommerceUI
import Core
import Foundation
@testable import LegalFeature
@testable import LicensesFeature
@testable import SettingsFeature
import ShopifyKit
@testable import SupportFeature
import Testing

// MARK: - Order status

@Suite("Order status pill")
struct OrderStatusPillTests {
    @Test("A cancelled order is cancelled, whatever else is known")
    func cancelled() {
        let order = AccountFixtures.order(1, cancelled: true)

        #expect(OrderStatusPill(order: order, delivery: .delivered) == .cancelled)
    }

    @Test("A refunded order is refunded")
    func refunded() {
        let order = AccountFixtures.order(1, financial: .refunded)

        #expect(OrderStatusPill(order: order, delivery: nil) == .refunded)
    }

    @Test("The backend's delivery state wins for paid orders")
    func backendDelivery() {
        let order = AccountFixtures.order(1)

        #expect(OrderStatusPill(order: order, delivery: .delivered) == .delivered)
        #expect(OrderStatusPill(order: order, delivery: .shipped) == .shipped)
        #expect(OrderStatusPill(order: order, delivery: .pending) == .paid)
    }

    @Test("Without the backend Shopify's states decide")
    func shopifyStates() {
        #expect(OrderStatusPill(order: AccountFixtures.order(1, fulfillment: .fulfilled), delivery: nil) == .delivered)
        #expect(OrderStatusPill(order: AccountFixtures.order(1), delivery: nil) == .paid)
        #expect(OrderStatusPill(order: AccountFixtures.order(1, financial: .pending), delivery: nil) == .processing)
        #expect(OrderStatusPill(order: AccountFixtures.order(1, financial: nil), delivery: nil) == .processing)
    }

    @Test("Every pill has a title")
    func titles() {
        for pill in OrderStatusPill.allCases {
            #expect(!pill.title.isEmpty)
            #expect(!pill.title.hasPrefix("account."), "Unresolved key for \(pill)")
        }
    }
}

@Suite("Order timeline")
struct OrderTimelineTests {
    private let locale = Locale(identifier: "de_DE")

    @Test("A paid digital order waits for the key")
    func paidWaiting() {
        let steps = OrderTimeline.steps(for: AccountFixtures.order(1), delivery: .pending, locale: locale)

        #expect(steps.map(\.state) == [.done, .done, .current])
        #expect(steps[2].detail != nil)
    }

    @Test("A delivered order is done")
    func delivered() {
        let steps = OrderTimeline.steps(for: AccountFixtures.order(1), delivery: .delivered, locale: locale)

        #expect(steps.map(\.state) == [.done, .done, .done])
        #expect(steps[2].detail == nil)
    }

    @Test("An unpaid order has payment as the current step")
    func unpaid() {
        let steps = OrderTimeline.steps(for: AccountFixtures.order(1, financial: .pending), delivery: nil, locale: locale)

        #expect(steps.map(\.state) == [.done, .current, .upcoming])
    }

    @Test("A successful fulfillment counts as delivered")
    func fulfillment() {
        let fulfillment = OrderFulfillment(id: "gid://shopify/Fulfillment/1", status: "SUCCESS", latestShipmentStatus: nil, updatedAt: nil)
        let order = AccountFixtures.order(1, fulfillments: [fulfillment])

        #expect(OrderTimeline.steps(for: order, delivery: nil, locale: locale).last?.state == .done)
    }

    @Test("A shipped order names the shipment as the last step")
    func shipped() {
        let digital = OrderTimeline.steps(for: AccountFixtures.order(1), delivery: .delivered, locale: locale)
        let shipped = OrderTimeline.steps(for: AccountFixtures.order(1), delivery: .shipped, locale: locale)

        #expect(digital[2].title != shipped[2].title)
    }
}

// MARK: - Orders

@Suite("Orders")
@MainActor
struct OrdersViewModelTests {
    @Test("Loads the first page with the delivery states")
    func firstPage() async {
        let repository = StubCustomerRepository()
        let backend = StubBackend()
        await repository.setPage(CustomerOrderPage(orders: [AccountFixtures.order(1042)], nextCursor: nil), after: nil)
        let status = BackendOrderStatus(orderID: "1042", name: "#1042", deliveryStatus: .delivered, hasLicenses: true, hasInvoice: true)
        await backend.setOrders(.success([status]))
        let model = OrdersViewModel(repository: repository, backend: backend)

        await model.load()

        #expect(model.state.value?.map(\.name) == ["#1042"])
        #expect(model.delivery(for: AccountFixtures.order(1042)) == .delivered)
    }

    @Test("No orders is the empty state")
    func empty() async {
        let model = OrdersViewModel(repository: StubCustomerRepository(), backend: StubBackend())

        await model.load()

        #expect(model.state == .empty)
    }

    @Test("Without a backend the orders still load")
    func withoutBackend() async {
        let repository = StubCustomerRepository()
        await repository.setPage(CustomerOrderPage(orders: [AccountFixtures.order(1)], nextCursor: nil), after: nil)
        let model = OrdersViewModel(repository: repository, backend: UnavailableBackendClient())

        await model.load()

        #expect(model.state.value?.count == 1)
        #expect(model.delivery(for: AccountFixtures.order(1)) == nil)
    }

    @Test("Scrolling near the end loads the next page once")
    func pagination() async {
        let repository = StubCustomerRepository()
        let first = (1...3).map { AccountFixtures.order($0) }
        let second = [AccountFixtures.order(3), AccountFixtures.order(4)]
        await repository.setPage(CustomerOrderPage(orders: first, nextCursor: "c1"), after: nil)
        await repository.setPage(CustomerOrderPage(orders: second, nextCursor: nil), after: "c1")
        let model = OrdersViewModel(repository: repository, backend: StubBackend())

        await model.load()
        await model.loadMoreIfNeeded(after: first[2])
        await model.loadMoreIfNeeded(after: second[1])

        #expect(model.state.value?.map(\.name) == ["#1", "#2", "#3", "#4"])
        #expect(await repository.orderRequests == [nil, "c1"])
    }
}

@Suite("Order detail")
@MainActor
struct OrderDetailViewModelTests {
    @Test("Without a backend the invoice comes by e-mail")
    func invoiceByEmail() async {
        let repository = StubCustomerRepository()
        await repository.setDetail(AccountFixtures.order(1042))
        let model = OrderDetailViewModel(orderID: "gid://shopify/Order/1042", repository: repository, backend: StubBackend())

        await model.load()
        let url = await model.invoiceFile()

        #expect(url == nil)
        #expect(model.invoiceState == .byEmail)
    }

    @Test("An order the customer cannot see is not found")
    func missingOrder() async {
        let model = OrderDetailViewModel(orderID: "gid://shopify/Order/1", repository: StubCustomerRepository(), backend: StubBackend())

        await model.load()

        #expect(model.state == .empty)
    }
}

// MARK: - Persönliche Daten

@Suite("Persönliche Daten")
@MainActor
struct ProfileViewModelTests {
    @Test("Loading shows the customer and an empty address book as content, not as an empty screen")
    func load() async {
        let repository = StubCustomerRepository()
        let model = ProfileViewModel(repository: repository)

        await model.load()

        #expect(model.customer?.displayName == "Anna Schmidt")
        #expect(model.state.value?.addresses.isEmpty == true)
    }

    @Test("Saving a new address reloads the book")
    func create() async {
        let repository = StubCustomerRepository()
        let model = ProfileViewModel(repository: repository)
        await model.load()

        let saved = await model.save(CustomerAddressInput(city: "Berlin", territoryCode: "DE"), id: nil, makeDefault: false)

        #expect(saved)
        #expect(model.state.value?.addresses.map(\.city) == ["Berlin"])
        #expect(model.actionError == nil)
    }

    @Test("Shopify's refusal is shown with its own message")
    func userError() async {
        let repository = StubCustomerRepository()
        let refusal = UserError(field: ["zip"], message: "Die Postleitzahl ist ungültig.", code: nil)
        await repository.setMutationError(ShopifyError.userErrors([refusal]))
        let model = ProfileViewModel(repository: repository)

        let saved = await model.save(CustomerAddressInput(zip: "1"), id: nil, makeDefault: false)

        #expect(!saved)
        #expect(model.actionError?.kind == .rejected(messages: ["Die Postleitzahl ist ungültig."]))
        model.dismissError()
        #expect(model.actionError == nil)
    }

    @Test("Deleting removes the address")
    func delete() async {
        let repository = StubCustomerRepository()
        let address = AccountFixtures.address(1)
        await repository.setBook(CustomerAddressBook(addresses: [address], defaultAddressID: nil))
        let model = ProfileViewModel(repository: repository)
        await model.load()

        await model.delete(address.id)

        #expect(model.state.value?.addresses.isEmpty == true)
        #expect(await repository.deleted == [address.id])
    }

    @Test("Als Standard festlegen makes the address the default one")
    func makeDefault() async {
        let repository = StubCustomerRepository()
        let first = AccountFixtures.address(1)
        let second = AccountFixtures.address(2)
        await repository.setBook(CustomerAddressBook(addresses: [first, second], defaultAddressID: first.id))
        let model = ProfileViewModel(repository: repository)
        await model.load()

        await model.makeDefault(second)

        #expect(model.state.value?.defaultAddressID == second.id)
    }

    @Test("Changing the name trims it and shows the new name")
    func updateName() async {
        let repository = StubCustomerRepository()
        let model = ProfileViewModel(repository: repository)

        let saved = await model.updateName(firstName: " Anna ", lastName: "Berg ")

        #expect(saved)
        #expect(await repository.names == ["Anna Berg"])
        #expect(model.customer?.lastName == "Berg")
    }

    @Test("A refused name keeps the old one and explains why")
    func refusedName() async {
        let repository = StubCustomerRepository()
        await repository.setMutationError(ShopifyError.userErrors([UserError(field: ["lastName"], message: "Zu lang.", code: nil)]))
        let model = ProfileViewModel(repository: repository)

        let saved = await model.updateName(firstName: "Anna", lastName: "Berg")

        #expect(!saved)
        #expect(model.actionError?.kind == .rejected(messages: ["Zu lang."]))
    }
}

// MARK: - Erneut kaufen

@Suite("Erneut kaufen")
struct OrderReorderTests {
    @Test("Only lines with a variant go back into the cart, each with its quantity")
    func lines() {
        let base = AccountFixtures.order(1042)
        let order = CustomerOrder(
            id: base.id,
            name: base.name,
            confirmationNumber: nil,
            processedAt: base.processedAt,
            cancelledAt: nil,
            financialStatus: .paid,
            fulfillmentStatus: .fulfilled,
            totalPrice: base.totalPrice,
            subtotal: nil,
            totalTax: nil,
            totalShipping: nil,
            lineItems: [
                OrderLineItem(
                    id: "gid://shopify/LineItem/1", name: "Windows 11 Pro", variantTitle: nil, quantity: 2,
                    price: nil, total: nil, image: nil, variantID: "gid://shopify/ProductVariant/7"
                ),
                OrderLineItem(
                    id: "gid://shopify/LineItem/2",
                    name: "Versand",
                    variantTitle: nil,
                    quantity: 1,
                    price: nil,
                    total: nil,
                    image: nil
                ),
            ],
            fulfillments: []
        )

        let lines = OrderReorder.lines(of: order)

        #expect(lines.map(\.variantID) == ["gid://shopify/ProductVariant/7"])
        #expect(lines.map(\.quantity) == [2])
        #expect(OrderReorder.lines(of: base).isEmpty)
    }
}

// MARK: - Profile names

@Suite("Profile names")
struct ProfileNameTests {
    private func customer(first: String?, last: String?, display: String, email: String?) -> Customer {
        Customer(
            id: "gid://shopify/Customer/3029680329",
            displayName: display,
            firstName: first,
            lastName: last,
            emailAddress: email,
            defaultAddress: nil
        )
    }

    @Test("The name comes from first and last name, else from a display name that is not the e-mail address")
    func names() {
        #expect(ProfileName.displayName(of: customer(first: "Anna", last: "Schmidt", display: "x", email: nil)) == "Anna Schmidt")
        #expect(ProfileName.displayName(of: customer(first: nil, last: " ", display: "Anna", email: nil)) == "Anna")
        #expect(ProfileName.displayName(of: customer(first: nil, last: nil, display: "a@b.de", email: "a@b.de")) == nil)
        #expect(ProfileName.displayName(of: nil) == nil)
    }

    @Test("Initials: first and last word, the e-mail address's first letter, or none")
    func initials() {
        #expect(ProfileName.initials(of: customer(first: "Mgrdegh", last: "Ghazarian", display: "", email: nil)) == "MG")
        #expect(ProfileName.initials(of: customer(first: "anna", last: nil, display: "", email: nil)) == "A")
        #expect(ProfileName.initials(of: customer(first: nil, last: nil, display: "", email: "kunde@karinex.de")) == "K")
        #expect(ProfileName.initials(of: nil).isEmpty)
    }

    @Test("Address cards take most of the width so the next one peeks in, at most 340 points")
    func cardWidth() {
        #expect(ProfileLayout.cardWidth(in: 400) == 320)
        #expect(ProfileLayout.cardWidth(in: 1000) == 340)
    }
}

// MARK: - Account deletion

@Suite("Account deletion")
@MainActor
struct DeleteAccountViewModelTests {
    private func signedOutStore() -> CustomerSessionStore {
        CustomerSessionStore(session: nil, repository: nil, callbackScheme: nil, hasStoredTokens: false)
    }

    @Test("A sent request is confirmed")
    func requested() async {
        let backend = StubBackend()
        let model = DeleteAccountViewModel(backend: backend, sessionStore: signedOutStore())

        await model.requestDeletion()

        #expect(model.state == .requested)
        #expect(await backend.calls == ["delete"])
    }

    @Test("Without a backend the request goes by e-mail")
    func byEmail() async {
        let model = DeleteAccountViewModel(backend: UnavailableBackendClient(), sessionStore: signedOutStore())

        await model.requestDeletion()

        #expect(model.state == .byEmail)
    }

    @Test("A failure can be retried")
    func failure() async {
        let backend = StubBackend()
        await backend.setDeletion(.failure(.server(statusCode: 503, code: nil, requestID: nil)))
        let model = DeleteAccountViewModel(backend: backend, sessionStore: signedOutStore())

        await model.requestDeletion()

        guard case let .failed(error) = model.state else {
            Issue.record("Expected a failure, got \(model.state)")
            return
        }
        #expect(error.isRetryable)
    }
}

// MARK: - License vault

@Suite("License vault")
@MainActor
struct LicenseVaultViewModelTests {
    private func makeCache() -> LicenseKeyCache {
        LicenseKeyCache(store: InMemorySecureStore())
    }

    @Test("Delivered keys are cached and pending orders listed by name")
    func refresh() async {
        let backend = StubBackend()
        let cache = makeCache()
        await backend.setOrders(.success([
            BackendOrderStatus(orderID: "1", name: "#1001", deliveryStatus: .delivered, hasLicenses: true, hasInvoice: true),
            BackendOrderStatus(orderID: "2", name: "#1002", deliveryStatus: .pending, hasLicenses: true, hasInvoice: false),
            BackendOrderStatus(orderID: "3", name: "#1003", deliveryStatus: .shipped, hasLicenses: false, hasInvoice: true),
        ]))
        await backend.setLicenses(.delivered([AccountFixtures.key(orderID: "1", line: "A")]), for: "1")
        await backend.setLicenses(.pending, for: "2")
        let model = LicenseVaultViewModel(orderID: nil, backend: backend, cache: cache)

        await model.refresh()

        #expect(model.backendState == .available)
        #expect(model.keys.map(\.lineItemID) == ["A"])
        #expect(model.pendingOrders == ["#1002"])
        #expect(cache.keys(orderID: "1").count == 1)
        #expect(await !backend.calls.contains("licenses:3"))
        #expect(model.orderName(for: model.keys[0]) == "#1001")
    }

    @Test("Without a backend the cached keys stay and the e-mail notice applies")
    func unavailable() async {
        let cache = makeCache()
        cache.store([AccountFixtures.key(orderID: "1", line: "A")], orderID: "1")
        let model = LicenseVaultViewModel(orderID: nil, backend: UnavailableBackendClient(), cache: cache)
        #expect(model.keys.count == 1)

        await model.refresh()

        #expect(model.backendState == .unavailable)
        #expect(model.keys.count == 1)
    }

    @Test("One order's vault shows only that order")
    func singleOrder() async {
        let cache = makeCache()
        cache.store([AccountFixtures.key(orderID: "1", line: "A")], orderID: "1")
        cache.store([AccountFixtures.key(orderID: "2", line: "B")], orderID: "2")
        let backend = StubBackend()
        let model = LicenseVaultViewModel(orderID: "2", backend: backend, cache: cache)

        #expect(model.keys.map(\.orderID) == ["2"])
        await model.refresh()
        #expect(await backend.calls == ["licenses:2"])
    }

    @Test("A failed refresh keeps the keys and reports the failure")
    func failure() async {
        let cache = makeCache()
        cache.store([AccountFixtures.key(orderID: "1", line: "A")], orderID: "1")
        let backend = StubBackend()
        await backend.setOrders(.failure(.server(statusCode: 500, code: nil, requestID: nil)))
        let model = LicenseVaultViewModel(orderID: nil, backend: backend, cache: cache)

        await model.refresh()

        guard case .failed = model.backendState else {
            Issue.record("Expected a failure, got \(model.backendState)")
            return
        }
        #expect(model.keys.count == 1)
    }

    @Test("Keys are hidden until revealed, and hidden again together")
    func reveal() {
        let cache = makeCache()
        cache.store([AccountFixtures.key(orderID: "1", line: "A")], orderID: "1")
        let model = LicenseVaultViewModel(orderID: nil, backend: StubBackend(), cache: cache)
        let key = model.keys[0]

        #expect(!model.isRevealed(key))
        model.setRevealed(true, for: key)
        #expect(model.isRevealed(key))
        model.hideAll()
        #expect(!model.isRevealed(key))
    }
}

// MARK: - Support

@Suite("Support")
struct SupportTests {
    private func config(whatsApp: String?, liveChat: URL?) -> RemoteAppConfig {
        RemoteAppConfig(
            supportHours: .standard,
            whatsappNumber: whatsApp,
            liveChatURL: liveChat,
            supportEmail: "kundenservice@karinex.de",
            featureFlags: [:],
            minSupportedAppVersion: nil
        )
    }

    @Test("The fallback offers e-mail only")
    func fallback() {
        let contact = SupportContact(config: .fallback, orderName: nil)

        #expect(contact.whatsApp == nil)
        #expect(contact.liveChat == nil)
        #expect(contact.email?.scheme == "mailto")
        #expect(contact.emailAddress == "kundenservice@karinex.de")
    }

    @Test("WhatsApp and live chat come from the backend")
    func backendChannels() throws {
        let chat = try #require(URL(string: "https://karinex.de/pages/chat"))
        let contact = SupportContact(config: config(whatsApp: "4940123456", liveChat: chat), orderName: "#1042")

        #expect(contact.whatsApp?.host == "wa.me")
        #expect(contact.whatsApp?.absoluteString.contains("1042") == true)
        #expect(contact.liveChat == chat)
        #expect(contact.email?.absoluteString.contains("1042") == true)
    }

    @Test("Only plausible addresses become mailto links")
    func mailto() {
        #expect(SupportContact.mailtoURL(address: "kundenservice@karinex.de", subject: "Frage")?.absoluteString
            == "mailto:kundenservice@karinex.de?subject=Frage")
        #expect(SupportContact.mailtoURL(address: "kein Postfach", subject: "Frage") == nil)
        #expect(SupportContact.mailtoURL(address: "a@b.de?cc=c@d.de", subject: "Frage") == nil)
    }

    @Test("The hours show 6:00 and 23:00 in German time")
    func hours() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-26T12:00:00Z"))

        let text = SupportHoursText.text(for: .standard, on: date, locale: Locale(identifier: "de_DE"))

        #expect(text.contains("6:00"))
        #expect(text.contains("23:00"))
        #expect(!containsForbiddenDash(text))
    }

    @Test("Support messages resolve without dashes", arguments: appLanguages)
    func noPhone(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: SupportResources.bundle)
        let keys = ["support.whatsapp.message", "support.email.subject"]

        for key in keys {
            let text = strings(key)
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }
}

// MARK: - Legal

@Suite("Legal texts")
struct LegalTextTests {
    @Test("The imprint is the shop's legal notice policy when the store has one")
    func imprintPolicy() async throws {
        let repository = StubLegalRepository()
        let notice = AccountFixtures.legalText("legal-notice", title: "Impressum")
        let policies = ShopPolicies(privacyPolicy: nil, refundPolicy: nil, shippingPolicy: nil, termsOfService: nil, legalNotice: notice)
        await repository.setPolicies(policies)
        await repository.setPage(AccountFixtures.legalText("rechtliche-hinweise", title: "Rechtliche Hinweise"))

        let text = try await LegalDocumentViewModel.text(for: .imprint, from: repository)

        #expect(text == notice)
        #expect(await repository.requestedPages.isEmpty)
    }

    @Test("Without the legal notice the imprint is the page rechtliche-hinweise")
    func imprint() async throws {
        let repository = StubLegalRepository()
        await repository.setPage(AccountFixtures.legalText("rechtliche-hinweise", title: "Impressum"))

        let text = try await LegalDocumentViewModel.text(for: .imprint, from: repository)

        #expect(text?.title == "Impressum")
    }

    @Test("The withdrawal page falls back to the refund policy")
    func withdrawalFallback() async throws {
        let repository = StubLegalRepository()
        let refund = AccountFixtures.legalText("refund-policy", title: "Rückerstattung")
        await repository.setPolicies(ShopPolicies(privacyPolicy: nil, refundPolicy: refund, shippingPolicy: nil, termsOfService: nil))

        let text = try await LegalDocumentViewModel.text(for: .withdrawal, from: repository)

        #expect(text == refund)
        #expect(await repository.requestedPages == ["widerrufsrecht"])
    }

    @Test("Terms, privacy and shipping are shop policies")
    func policies() async throws {
        let repository = StubLegalRepository()
        let privacy = AccountFixtures.legalText("privacy-policy", title: "Datenschutz")
        let shipping = AccountFixtures.legalText("shipping-policy", title: "Versand")
        let terms = AccountFixtures.legalText("terms-of-service", title: "AGB")
        await repository.setPolicies(ShopPolicies(
            privacyPolicy: privacy,
            refundPolicy: nil,
            shippingPolicy: shipping,
            termsOfService: terms
        ))

        #expect(try await LegalDocumentViewModel.text(for: .privacy, from: repository) == privacy)
        #expect(try await LegalDocumentViewModel.text(for: .shipping, from: repository) == shipping)
        #expect(try await LegalDocumentViewModel.text(for: .terms, from: repository) == terms)
        #expect(await repository.requestedPages.isEmpty)
    }

    @Test("A legal text splits into sections at the level that repeats, without the title heading")
    func outline() {
        let document = HTMLDocument(html: """
            <h1>AGB</h1><p>Vorwort</p>
            <h2>1. Geltungsbereich</h2><p>Text eins</p><h3>1.1 Detail</h3><p>Mehr</p>
            <h2>2. Vertragsschluss</h2><p>Text zwei</p>
            """)

        let outline = LegalOutline.split(document.blocks, title: "AGB")

        #expect(outline.intro.count == 1)
        #expect(outline.sections.map(\.title) == ["1. Geltungsbereich", "2. Vertragsschluss"])
        #expect(outline.sections.map(\.id) == [0, 1])
        #expect(outline.sections[0].blocks.count == 3)
    }

    @Test("A text without repeating headings stays one block")
    func outlineFlat() {
        let document = HTMLDocument(html: "<h2>Impressum</h2><p>KARINEX</p><p>Hamburg</p>")

        let outline = LegalOutline.split(document.blocks, title: "Impressum")

        #expect(outline.sections.isEmpty)
        #expect(outline.intro.count == 2)
    }

    @Test("A missing text is empty, not an error")
    @MainActor
    func missing() async {
        let model = LegalDocumentViewModel(kind: .terms, repository: StubLegalRepository())

        await model.load()

        #expect(model.state == .empty)
    }
}

// MARK: - Strings

@Suite("Phase 2 strings")
struct AccountServicesStringTests {
    @Test("The new modules carry every language", arguments: appLanguages)
    func bundles(language: String) throws {
        for bundle in [LicensesResources.bundle, SupportResources.bundle, LegalResources.bundle, SettingsResources.bundle] {
            _ = try LocalizedStrings(language: language, in: bundle)
        }
    }
}

@Suite("Invoices")
@MainActor
struct InvoicesViewModelTests {
    @Test("Lists only the orders the backend has an invoice for, in Shopify's order")
    func listsInvoices() async {
        let repository = StubCustomerRepository()
        await repository.setPage(
            CustomerOrderPage(
                orders: [AccountFixtures.order(1043), AccountFixtures.order(1042), AccountFixtures.order(1041)],
                nextCursor: nil
            ),
            after: nil
        )
        let backend = StubBackend()
        await backend.setOrders(.success([
            BackendOrderStatus(orderID: "1042", name: "#1042", deliveryStatus: .delivered, hasLicenses: true, hasInvoice: true),
            BackendOrderStatus(orderID: "1043", name: "#1043", deliveryStatus: .pending, hasLicenses: false, hasInvoice: false),
            BackendOrderStatus(orderID: "1041", name: "#1041", deliveryStatus: .delivered, hasLicenses: true, hasInvoice: true),
        ]))
        let model = InvoicesViewModel(repository: repository, backend: backend)

        await model.load()

        #expect(model.state.value?.map(\.order.name) == ["#1042", "#1041"])
    }

    @Test("Without a backend there is no invoice to list")
    func withoutBackend() async {
        let repository = StubCustomerRepository()
        await repository.setPage(CustomerOrderPage(orders: [AccountFixtures.order(1042)], nextCursor: nil), after: nil)
        let backend = StubBackend()
        await backend.setOrders(.failure(.notConfigured))
        let model = InvoicesViewModel(repository: repository, backend: backend)

        await model.load()

        #expect(model.state == .empty)
    }

    @Test("A failed PDF download shows an error and no preview")
    func openFailure() async {
        let repository = StubCustomerRepository()
        await repository.setPage(CustomerOrderPage(orders: [AccountFixtures.order(1042)], nextCursor: nil), after: nil)
        let backend = StubBackend()
        let status = BackendOrderStatus(orderID: "1042", name: "#1042", deliveryStatus: .delivered, hasLicenses: true, hasInvoice: true)
        await backend.setOrders(.success([status]))
        let model = InvoicesViewModel(repository: repository, backend: backend)
        await model.load()

        if let item = model.state.value?.first {
            await model.open(item)
        }

        #expect(model.preview == nil)
        #expect(model.openError != nil)
        #expect(model.openingID == nil)
    }

    @Test("The PDF file name carries the order number")
    func fileName() {
        #expect(InvoicePDF.fileName(orderName: "#3689") == "Rechnung-3689.pdf")
        #expect(InvoicePDF.fileName(orderName: "#") == "Rechnung-KARINEX.pdf")
    }
}
