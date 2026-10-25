@testable import CheckoutFeature
import CommerceUI
import Foundation
import Testing

// MARK: - CompletedOrder

@Suite("Completed order")
struct CompletedOrderTests {
    private let germany = Locale(identifier: "de_DE")

    @Test("Only the presence of the e-mail address is kept")
    func emailPresence() {
        let withEmail = CompletedOrder(
            id: "gid://shopify/OrderIdentity/1",
            email: "kunde@example.com",
            totalAmount: 29.9,
            currencyCode: "EUR",
            locale: germany
        )
        #expect(withEmail.hasEmail)
        #expect(withEmail.id == "gid://shopify/OrderIdentity/1")
        #expect(!String(describing: withEmail).contains("example.com"), "The address must not be kept anywhere")

        let blank = CompletedOrder(id: "2", email: "  ", totalAmount: nil, currencyCode: nil, locale: germany)
        #expect(!blank.hasEmail)
        let missing = CompletedOrder(id: "3", email: nil, totalAmount: nil, currencyCode: nil, locale: germany)
        #expect(!missing.hasEmail)
    }

    @Test("The total is Shopify's amount formatted for the locale, never rounded")
    func formattedTotal() throws {
        let order = CompletedOrder(id: "1", email: nil, totalAmount: 29.9, currencyCode: "eur", locale: germany)
        let total = try #require(order.formattedTotal)
        #expect(total.contains("29,90"))
        #expect(total.contains("€"))

        let swiss = CompletedOrder(id: "1", email: nil, totalAmount: 1234.5, currencyCode: "CHF", locale: Locale(identifier: "de_CH"))
        #expect(swiss.formattedTotal?.contains("CHF") == true)
    }

    @Test("A missing or unusable total is left out")
    func unusableTotals() {
        #expect(CompletedOrder.formattedTotal(amount: nil, currencyCode: "EUR", locale: germany) == nil)
        #expect(CompletedOrder.formattedTotal(amount: 10, currencyCode: nil, locale: germany) == nil)
        #expect(CompletedOrder.formattedTotal(amount: 10, currencyCode: "EURO", locale: germany) == nil)
        #expect(CompletedOrder.formattedTotal(amount: 10, currencyCode: "E1R", locale: germany) == nil)
        #expect(CompletedOrder.formattedTotal(amount: -1, currencyCode: "EUR", locale: germany) == nil)
        #expect(CompletedOrder.formattedTotal(amount: .infinity, currencyCode: "EUR", locale: germany) == nil)
    }
}

// MARK: - CheckoutFailure

@Suite("Checkout failure")
struct CheckoutFailureTests {
    @Test("Retry is offered for recoverable failures and expired checkouts only")
    func canRetry() {
        #expect(CheckoutFailure(kind: .expired, isRecoverable: false).canRetry)
        #expect(CheckoutFailure(kind: .unavailable, isRecoverable: true).canRetry)
        #expect(CheckoutFailure(kind: .sdk, isRecoverable: true).canRetry)
        #expect(!CheckoutFailure(kind: .unavailable, isRecoverable: false).canRetry)
        #expect(!CheckoutFailure(kind: .configuration, isRecoverable: false).canRetry)
    }

    @Test("The alert explains an expired checkout and an unavailable one differently")
    func alertTexts() {
        let expired = CheckoutAlert(id: 1, failure: CheckoutFailure(kind: .expired, isRecoverable: false))
        let unavailable = CheckoutAlert(id: 2, failure: CheckoutFailure(kind: .unavailable, isRecoverable: false))
        #expect(expired.message != unavailable.message)
        #expect(expired.title == unavailable.title)
        #expect(expired.canRetry)
        #expect(!unavailable.canRetry)

        let offline = CheckoutAlert(id: 3, error: UserFacingError(kind: .offline))
        #expect(offline.title == UserFacingError(kind: .offline).title)
        #expect(offline.canRetry)
        let expiredCart = CheckoutAlert(id: 4, error: CartStore.expiredCartError)
        #expect(!expiredCart.canRetry)
    }
}

// MARK: - CheckoutCoordinator

/// Records the calls of the coordinator's callbacks and serves checkout URLs.
@MainActor
private final class CheckoutProbe {
    var urls: [Result<URL, any Error>]
    private(set) var urlRequests = 0
    private(set) var completedOrders: [CompletedOrder] = []
    private(set) var finishedOrders: [CompletedOrder] = []

    init(urls: [Result<URL, any Error>]) {
        self.urls = urls
    }

    func nextURL() throws -> URL {
        urlRequests += 1
        guard !urls.isEmpty else { throw UserFacingError(kind: .notFound) }
        return try urls.removeFirst().get()
    }

    func makeCoordinator(dismissalTimeout: Duration = .seconds(30)) -> CheckoutCoordinator {
        CheckoutCoordinator(
            urlProvider: { try self.nextURL() },
            onOrderCompleted: { self.completedOrders.append($0) },
            onSuccessFinished: { self.finishedOrders.append($0) },
            dismissalTimeout: dismissalTimeout
        )
    }
}

@MainActor
@Suite("Checkout coordinator")
struct CheckoutCoordinatorTests {
    private let firstURL = URL(fileURLWithPath: "/checkout/1")
    private let secondURL = URL(fileURLWithPath: "/checkout/2")
    private let order = CompletedOrder(id: "gid://shopify/OrderIdentity/7", hasEmail: true, formattedTotal: "29,90 €")

    private func started(_ coordinator: CheckoutCoordinator) async {
        coordinator.start()
        #expect(coordinator.isPreparing)
        #expect(coordinator.isActive)
        await coordinator.preparation?.value
    }

    @Test("Start fetches a fresh URL and presents the checkout")
    func startPresents() async {
        let probe = CheckoutProbe(urls: [.success(firstURL)])
        let coordinator = probe.makeCoordinator()

        await started(coordinator)

        #expect(!coordinator.isPreparing)
        #expect(coordinator.presentation?.url == firstURL)
        #expect(probe.urlRequests == 1)

        coordinator.start()
        #expect(probe.urlRequests == 1, "A running flow is not started twice")
    }

    @Test("Completion clears the cart once, shows the success screen and finishes with the order")
    func completion() async {
        let probe = CheckoutProbe(urls: [.success(firstURL)])
        let coordinator = probe.makeCoordinator()
        await started(coordinator)

        coordinator.handleCompletion(order)
        coordinator.handleCompletion(order)
        coordinator.handleCancel()

        #expect(probe.completedOrders == [order])
        #expect(coordinator.completedOrder == order)
        #expect(coordinator.presentation != nil, "The sheet stays for the success screen")

        coordinator.finishSuccess()
        #expect(coordinator.presentation == nil)
        coordinator.sheetDidDismiss()

        #expect(probe.finishedOrders == [order])
        #expect(coordinator.completedOrder == nil)
        #expect(!coordinator.isActive)
    }

    @Test("Swiping the success screen away finishes like \"Weiter einkaufen\"")
    func successSwipedAway() async {
        let probe = CheckoutProbe(urls: [.success(firstURL)])
        let coordinator = probe.makeCoordinator()
        await started(coordinator)
        coordinator.handleCompletion(order)

        coordinator.presentation = nil
        coordinator.sheetDidDismiss()

        #expect(probe.finishedOrders == [order])
        #expect(!coordinator.isActive)
    }

    @Test("Cancel closes the checkout and keeps the cart")
    func cancel() async {
        let probe = CheckoutProbe(urls: [.success(firstURL)])
        let coordinator = probe.makeCoordinator()
        await started(coordinator)

        coordinator.handleCancel()
        #expect(coordinator.presentation == nil)
        #expect(coordinator.isActive, "The flow ends once the sheet is gone")
        coordinator.sheetDidDismiss()

        #expect(probe.completedOrders.isEmpty)
        #expect(probe.finishedOrders.isEmpty)
        #expect(coordinator.alert == nil)
        #expect(!coordinator.isActive)
    }

    @Test("An expired checkout is retried once with a fresh URL, a second expiry shows the error")
    func expiredRetriesOnce() async throws {
        let probe = CheckoutProbe(urls: [.success(firstURL), .success(secondURL)])
        let coordinator = probe.makeCoordinator()
        await started(coordinator)
        let firstPresentation = try #require(coordinator.presentation)

        coordinator.handleFailure(CheckoutFailure(kind: .expired, isRecoverable: false))
        #expect(coordinator.presentation == nil)
        coordinator.sheetDidDismiss()
        #expect(coordinator.isPreparing)
        await coordinator.preparation?.value

        let secondPresentation = try #require(coordinator.presentation)
        #expect(secondPresentation.url == secondURL)
        #expect(secondPresentation.id != firstPresentation.id)
        #expect(coordinator.alert == nil)

        coordinator.handleFailure(CheckoutFailure(kind: .expired, isRecoverable: false))
        coordinator.sheetDidDismiss()

        let alert = try #require(coordinator.alert)
        #expect(alert.canRetry)
        #expect(probe.urlRequests == 2)
        #expect(probe.completedOrders.isEmpty)
    }

    @Test("A recoverable failure offers a retry that fetches a fresh URL")
    func recoverableFailure() async throws {
        let probe = CheckoutProbe(urls: [.success(firstURL), .success(secondURL)])
        let coordinator = probe.makeCoordinator()
        await started(coordinator)

        coordinator.handleFailure(CheckoutFailure(kind: .unavailable, isRecoverable: true))
        coordinator.sheetDidDismiss()
        let alert = try #require(coordinator.alert)
        #expect(alert.canRetry)
        #expect(coordinator.isActive)

        coordinator.retryFromAlert()
        #expect(coordinator.alert == nil)
        #expect(coordinator.isActive)
        await coordinator.preparation?.value

        #expect(coordinator.presentation?.url == secondURL)
        #expect(probe.urlRequests == 2)
    }

    @Test("A permanent failure shows the error without retry; closing it ends the flow")
    func permanentFailure() async throws {
        let probe = CheckoutProbe(urls: [.success(firstURL)])
        let coordinator = probe.makeCoordinator()
        await started(coordinator)

        coordinator.handleFailure(CheckoutFailure(kind: .configuration, isRecoverable: false))
        coordinator.sheetDidDismiss()
        let alert = try #require(coordinator.alert)
        #expect(!alert.canRetry)

        coordinator.dismissAlert()
        #expect(!coordinator.isActive)
    }

    @Test("When the cart cannot give a URL, its error is shown and nothing is presented")
    func preparationFailure() async throws {
        let probe = CheckoutProbe(urls: [.failure(CartStore.expiredCartError)])
        let coordinator = probe.makeCoordinator()

        await started(coordinator)

        #expect(coordinator.presentation == nil)
        let alert = try #require(coordinator.alert)
        #expect(alert.message == CartStore.expiredCartError.message)
        #expect(!alert.canRetry)
    }

    @Test("A cancelled preparation ends the flow quietly")
    func cancelledPreparation() async {
        let probe = CheckoutProbe(urls: [.failure(CancellationError())])
        let coordinator = probe.makeCoordinator()

        await started(coordinator)

        #expect(coordinator.presentation == nil)
        #expect(coordinator.alert == nil)
        #expect(!coordinator.isActive)
    }

    @Test("Events of a sheet that is no longer shown are ignored")
    func lateEventsAreIgnored() {
        let probe = CheckoutProbe(urls: [])
        let coordinator = probe.makeCoordinator()

        coordinator.handleCompletion(order)
        coordinator.handleFailure(CheckoutFailure(kind: .expired, isRecoverable: false))
        coordinator.handleCancel()
        coordinator.finishSuccess()

        #expect(probe.completedOrders.isEmpty)
        #expect(!coordinator.isActive)
    }

    @Test("Without the sheet's dismissal callback the follow-up still runs")
    func dismissalFallback() async throws {
        let probe = CheckoutProbe(urls: [.success(firstURL)])
        let coordinator = probe.makeCoordinator(dismissalTimeout: .milliseconds(20))
        await started(coordinator)

        coordinator.handleFailure(CheckoutFailure(kind: .configuration, isRecoverable: false))

        var waited = 0
        while coordinator.alert == nil, waited < 200 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        #expect(coordinator.alert != nil)
        #expect(coordinator.followUp == nil)
    }
}

// MARK: - Checkout strings

@Suite("Checkout strings")
struct CheckoutStringTests {
    @Test("The success screen reads as in the brand copy")
    func successCopy() throws {
        let german = try LocalizedStrings(language: "de", in: CheckoutFeatureResources.bundle)

        #expect(german("checkout.title") == "Kasse")
        #expect(german("checkout.success.title") == "Bestellung eingegangen")
        #expect(german("checkout.success.message") == "Ihr Lizenzschlüssel wird per E-Mail zugestellt.")
        #expect(german("checkout.success.continue") == "Weiter einkaufen")
    }

    @Test("Every checkout text exists without dashes", arguments: ["de", "en"])
    func texts(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: CheckoutFeatureResources.bundle)
        let keys = [
            "checkout.title",
            "checkout.preparing",
            "checkout.success.eyebrow",
            "checkout.success.title",
            "checkout.success.message",
            "checkout.success.total",
            "checkout.success.continue",
            "checkout.error.title",
            "checkout.error.message",
            "checkout.error.expired",
            "checkout.error.retry",
            "checkout.error.close",
        ]
        for key in keys {
            let text = strings(key)
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }
}
