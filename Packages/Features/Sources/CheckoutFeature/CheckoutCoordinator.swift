import CommerceUI
import Core
import Foundation
import Observation

// MARK: - CheckoutPresentation

/// One presentation of the checkout sheet with the URL it loads.
struct CheckoutPresentation: Sendable, Hashable, Identifiable {
    /// A running number: every presentation, including a retry, is a new sheet.
    let id: Int
    /// The fresh checkout URL of the cart.
    let url: URL
}

// MARK: - CheckoutCoordinator

/// The state machine behind ``SwiftUICore/View/kxCheckout(isPresented:cartStore:onCompleted:)``,
/// free of Checkout Kit so it can be tested.
///
/// 1. ``start()`` asks the URL provider (`CartStore.checkoutURL()`) for a fresh checkout URL
///    while ``isPreparing`` is `true`, then sets ``presentation`` (the sheet).
/// 2. Completion: ``handleCompletion(_:)`` records the order, calls `onOrderCompleted` (which
///    clears the cart) and the sheet switches to the success screen. "Weiter einkaufen"
///    (``finishSuccess()``) closes it.
/// 3. Cancel: ``handleCancel()`` closes the sheet; the cart stays as it is.
/// 4. Failure: ``handleFailure(_:)`` closes the sheet. An expired checkout is retried once
///    automatically with a fresh URL; every other failure (and a second expiry) shows
///    ``alert``, with "Erneut versuchen" when it makes sense.
///
/// Follow-ups of a closing sheet run in ``sheetDidDismiss()``, after the sheet is gone, so the
/// next presentation never collides with the dismissal. Should the sheet's `onDismiss` not
/// arrive (Checkout Kit may dismiss its sheet itself after a failure), the follow-up runs after
/// `dismissalTimeout`, so the flow can never get stuck.
@MainActor
@Observable
final class CheckoutCoordinator {
    /// The follow-up of a closing sheet.
    enum FollowUp: Sendable, Hashable {
        /// Nothing more: the checkout flow ends.
        case finish
        /// Fetch a fresh URL and present the checkout again.
        case retry
        /// Show an error.
        case alert(CheckoutAlert)
    }

    /// Whether a checkout URL is being fetched.
    private(set) var isPreparing = false
    /// The checkout sheet, `nil` when none is shown. The sheet binding sets it to `nil` when the
    /// customer swipes the sheet away.
    var presentation: CheckoutPresentation?
    /// The completed order while the success screen is shown.
    private(set) var completedOrder: CompletedOrder?
    /// The error shown after a failure, `nil` when none is shown.
    private(set) var alert: CheckoutAlert?
    /// What happens once the sheet is gone.
    private(set) var followUp: FollowUp?

    /// Whether the checkout flow is running: preparing, presenting, closing or showing an error.
    var isActive: Bool {
        isPreparing || presentation != nil || alert != nil || followUp != nil
    }

    /// The task of a running preparation, for tests.
    @ObservationIgnored private(set) var preparation: Task<Void, Never>?

    @ObservationIgnored private let urlProvider: @MainActor () async throws -> URL
    @ObservationIgnored private let onOrderCompleted: @MainActor (CompletedOrder) -> Void
    @ObservationIgnored private let onSuccessFinished: @MainActor (CompletedOrder) -> Void
    @ObservationIgnored private let dismissalTimeout: Duration
    @ObservationIgnored private var dismissalFallback: Task<Void, Never>?
    @ObservationIgnored private let logger: KXLogger
    @ObservationIgnored private var hasRetriedExpiredCheckout = false
    @ObservationIgnored private var nextID = 0

    /// Creates the coordinator.
    ///
    /// - Parameters:
    ///   - urlProvider: Returns a fresh checkout URL, normally `CartStore.checkoutURL()`.
    ///   - onOrderCompleted: Called once when checkout reports the order as completed, normally
    ///     `CartStore.clearAfterCheckout()`.
    ///   - onSuccessFinished: Called after the success screen was closed ("Weiter einkaufen"
    ///     or swiped away), e.g. to switch to the Start tab.
    ///   - dismissalTimeout: How long a closing sheet may take before its follow-up runs
    ///     without the sheet's `onDismiss`. Defaults to 2 seconds.
    ///   - logger: The logger. Defaults to the `checkout` category.
    init(
        urlProvider: @escaping @MainActor () async throws -> URL,
        onOrderCompleted: @escaping @MainActor (CompletedOrder) -> Void,
        onSuccessFinished: @escaping @MainActor (CompletedOrder) -> Void,
        dismissalTimeout: Duration = .seconds(2),
        logger: KXLogger = KXLogger(category: .checkout)
    ) {
        self.urlProvider = urlProvider
        self.onOrderCompleted = onOrderCompleted
        self.onSuccessFinished = onSuccessFinished
        self.dismissalTimeout = dismissalTimeout
        self.logger = logger
    }

    // MARK: Flow

    /// Starts the checkout flow, unless it is already running.
    func start() {
        guard !isActive else { return }
        hasRetriedExpiredCheckout = false
        completedOrder = nil
        prepare()
    }

    /// Fetches a fresh URL and presents the checkout, or shows the error.
    private func prepare() {
        isPreparing = true
        preparation = Task { [weak self] in
            await self?.loadURL()
        }
    }

    private func loadURL() async {
        do {
            let url = try await urlProvider()
            isPreparing = false
            nextID += 1
            presentation = CheckoutPresentation(id: nextID, url: url)
        } catch {
            isPreparing = false
            guard let failure = UserFacingError(error) else { return }
            nextID += 1
            alert = CheckoutAlert(id: nextID, error: failure)
        }
    }

    /// Records a completed order: the cart is cleared and the sheet shows the success screen.
    func handleCompletion(_ order: CompletedOrder) {
        guard presentation != nil, completedOrder == nil else { return }
        logger.notice("Checkout completed")
        completedOrder = order
        onOrderCompleted(order)
    }

    /// The customer closed the checkout: the cart stays as it is.
    func handleCancel() {
        guard presentation != nil, completedOrder == nil else { return }
        logger.info("Checkout cancelled")
        close(then: .finish)
    }

    /// Checkout failed: an expired checkout is retried once with a fresh URL, every other
    /// failure closes the sheet and shows the error.
    func handleFailure(_ failure: CheckoutFailure) {
        guard presentation != nil, completedOrder == nil else { return }
        logger.error("Checkout failed: \(failure.kind), recoverable: \(failure.isRecoverable)")
        if failure.kind == .expired, !hasRetriedExpiredCheckout {
            hasRetriedExpiredCheckout = true
            close(then: .retry)
        } else {
            nextID += 1
            close(then: .alert(CheckoutAlert(id: nextID, failure: failure)))
        }
    }

    /// "Weiter einkaufen" on the success screen: closes the sheet.
    func finishSuccess() {
        guard completedOrder != nil else { return }
        close(then: .finish)
    }

    /// Runs the follow-up once the sheet is gone (the sheet's `onDismiss`). After the success
    /// screen it calls `onSuccessFinished` with the order.
    func sheetDidDismiss() {
        dismissalFallback?.cancel()
        dismissalFallback = nil
        presentation = nil
        let next = followUp ?? .finish
        followUp = nil
        let order = completedOrder
        completedOrder = nil
        switch next {
        case .finish:
            break
        case .retry:
            prepare()
        case let .alert(newAlert):
            alert = newAlert
        }
        if let order {
            onSuccessFinished(order)
        }
    }

    /// "Erneut versuchen" in the error: fetches a fresh URL and presents the checkout again.
    func retryFromAlert() {
        alert = nil
        prepare()
    }

    /// Closes the error without trying again; the flow ends.
    func dismissAlert() {
        alert = nil
    }

    // MARK: Private

    private func close(then next: FollowUp) {
        followUp = next
        presentation = nil
        dismissalFallback?.cancel()
        let timeout = dismissalTimeout
        dismissalFallback = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, followUp != nil, presentation == nil else { return }
            logger.notice("Checkout sheet dismissal was not reported; continuing")
            sheetDidDismiss()
        }
    }
}
