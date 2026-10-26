import Core
import Foundation
import Observation
import ShopifyKit

// MARK: - CustomerSessionStore

/// The login state of the app, shared by the Konto tab, the license vault and the settings.
///
/// It wraps `CustomerAccountSession` (OAuth, tokens in the Keychain) for the UI:
/// - ``status`` is `.unavailable` when this build has no Customer Account client ID or shop ID.
/// - ``signIn(locale:authenticate:)`` runs the whole login: discovery, the hosted Shopify login
///   page through `authenticate` (the Account feature passes `ASWebAuthenticationSession`),
///   the code exchange and the first customer read. A closed login page is no error.
/// - Sign-outs from anywhere (logout, a refresh token Shopify rejects, account deletion) end in
///   ``onSignedOut``, which the App uses to wipe the license key cache.
@MainActor
@Observable
public final class CustomerSessionStore {
    /// The login state.
    public enum Status: Sendable, Equatable {
        /// Login is not configured in this build.
        case unavailable
        /// Nobody is signed in.
        case signedOut
        /// The login page is open or the code is being exchanged.
        case signingIn
        /// A customer is signed in.
        case signedIn
    }

    /// Opens the login page at `url` and returns the redirect to `callbackScheme`.
    public typealias Authenticator = @MainActor (_ url: URL, _ callbackScheme: String) async throws -> URL

    /// The login state.
    public private(set) var status: Status
    /// The signed-in customer, once loaded.
    public private(set) var customer: Customer?
    /// Why the last login failed; `nil` after a success or when the customer closed the page.
    public private(set) var signInError: UserFacingError?

    /// Called once after every transition to signed out.
    @ObservationIgnored public var onSignedOut: (@MainActor () -> Void)?

    @ObservationIgnored private let session: CustomerAccountSession?
    @ObservationIgnored private let repository: (any CustomerAccountRepository)?
    @ObservationIgnored private let callbackScheme: String?
    @ObservationIgnored private let logger: KXLogger
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    /// Creates the store.
    ///
    /// - Parameters:
    ///   - session: The OAuth session, `nil` when login is not configured.
    ///   - repository: Reads the customer.
    ///   - callbackScheme: The custom scheme of the redirect URI, e.g. `shop.91753283851.app`.
    ///   - hasStoredTokens: Whether the Keychain holds tokens from an earlier launch.
    ///   - logger: Logs outcomes without personal data.
    public init(
        session: CustomerAccountSession?,
        repository: (any CustomerAccountRepository)?,
        callbackScheme: String?,
        hasStoredTokens: Bool,
        logger: KXLogger = KXLogger(category: .auth)
    ) {
        self.session = callbackScheme == nil ? nil : session
        self.repository = repository
        self.callbackScheme = callbackScheme
        self.logger = logger
        if session == nil || callbackScheme == nil {
            status = .unavailable
        } else {
            status = hasStoredTokens ? .signedIn : .signedOut
        }
    }

    /// Whether a customer is signed in.
    public var isSignedIn: Bool {
        status == .signedIn
    }

    /// Whether login can be offered at all.
    public var isAvailable: Bool {
        status != .unavailable
    }

    // MARK: Lifecycle

    /// Starts listening for sign-outs the session decides on its own (a rejected refresh
    /// token). Call once at launch.
    public func start() {
        guard eventsTask == nil, let session else { return }
        eventsTask = Task { [weak self] in
            for await event in session.events {
                self?.handle(event)
            }
        }
    }

    // MARK: Login

    /// Runs the login. Errors end up in ``signInError``; closing the login page sets none.
    ///
    /// - Parameters:
    ///   - locale: The language of the login page, e.g. `de`.
    ///   - authenticate: Opens the page and returns the redirect.
    public func signIn(locale: String?, authenticate: Authenticator) async {
        guard let session, let callbackScheme, status == .signedOut else { return }
        status = .signingIn
        signInError = nil
        do {
            let authorization = try await session.beginSignIn(locale: locale)
            let callback = try await authenticate(authorization.url, callbackScheme)
            try await session.completeSignIn(authorization, callbackURL: callback)
            status = .signedIn
            await loadCustomer()
        } catch {
            status = await session.isSignedIn ? .signedIn : .signedOut
            if let failure = UserFacingError(error) {
                logger.notice("Sign-in failed: \(failure.logName)")
                signInError = failure
            }
        }
    }

    /// Clears ``signInError`` after it was shown.
    public func dismissSignInError() {
        signInError = nil
    }

    /// Loads the signed-in customer for the account header. Failures keep the previous value.
    public func loadCustomer() async {
        guard let repository, status == .signedIn else { return }
        do {
            customer = try await repository.customer()
        } catch {
            if let failure = UserFacingError(error) {
                logger.notice("Loading the customer failed: \(failure.logName)")
            }
        }
    }

    // MARK: Checkout

    /// A valid access token for a signed-in checkout (`CartStore.customerAccessToken`), `nil`
    /// when nobody is signed in or the token cannot be refreshed; checkout then opens as a guest
    /// checkout. A refresh token Shopify rejects signs the customer out on its own.
    public func checkoutAccessToken() async -> String? {
        guard status == .signedIn, let session else { return nil }
        do {
            return try await session.accessToken()
        } catch {
            if let failure = UserFacingError(error) {
                logger.notice("No access token for the checkout: \(failure.logName)")
            }
            return nil
        }
    }

    // MARK: Logout

    /// Signs out locally and returns the URL that ends the Shopify session, if any.
    @discardableResult
    public func signOut() async -> URL? {
        guard let session else { return nil }
        let endSession = await session.signOut()
        markSignedOut()
        return endSession
    }

    /// Removes the tokens without contacting Shopify, e.g. after the account deletion request.
    public func discardSession() async {
        await session?.clear()
        markSignedOut()
    }

    // MARK: Private

    private func handle(_ event: CustomerAccountSessionEvent) {
        switch event {
        case .signedIn:
            if status != .signingIn {
                status = .signedIn
            }
        case .signedOut:
            markSignedOut()
        }
    }

    private func markSignedOut() {
        guard status == .signedIn || status == .signingIn || customer != nil else { return }
        status = .signedOut
        customer = nil
        onSignedOut?()
    }
}
