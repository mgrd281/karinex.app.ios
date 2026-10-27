import AuthenticationServices
import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - AccountLogin

/// Runs Shopify's passwordless login: the hosted login page in an ephemeral
/// `ASWebAuthenticationSession` (no cookies shared with Safari, so iOS asks no extra question),
/// in the app's language. Closing the page is no error.
enum AccountLogin {
    /// Signs in with `sessionStore`, opening the login page with `webAuthenticationSession`.
    @MainActor
    static func signIn(
        with sessionStore: CustomerSessionStore,
        using webAuthenticationSession: WebAuthenticationSession,
        locale: Locale
    ) async {
        await sessionStore.signIn(locale: AccountLoginLocale.code(for: locale)) { url, scheme in
            do {
                return try await webAuthenticationSession.authenticate(
                    using: url,
                    callbackURLScheme: scheme,
                    preferredBrowserSession: .ephemeral
                )
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                throw CustomerAccountAuthError.cancelled
            }
        }
    }
}

extension AccountLogin {
    /// Signs out on this device right away and ends the Shopify session in the background.
    @MainActor
    static func signOut(_ sessionStore: CustomerSessionStore) async {
        guard let endSession = await sessionStore.signOut() else { return }
        _ = try? await URLSession.shared.data(for: URLRequest(url: endSession))
    }
}

// MARK: - AccountLoginLocale

/// The `locale` parameter of the login page: the app's language code, `pt-PT` for Portuguese.
enum AccountLoginLocale {
    static func code(for locale: Locale) -> String? {
        guard let language = locale.language.languageCode?.identifier else { return nil }
        return language == "pt" ? "pt-PT" : language
    }
}

// MARK: - Sign-in error alert

extension View {
    /// Shows why the last login failed, as an alert of this screen while it is on screen. Every
    /// screen that offers "Anmelden" adds it; only the visible one presents the alert.
    func accountSignInErrorAlert(_ sessionStore: CustomerSessionStore) -> some View {
        modifier(AccountSignInErrorAlert(sessionStore: sessionStore))
    }
}

private struct AccountSignInErrorAlert: ViewModifier {
    let sessionStore: CustomerSessionStore

    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            .alert(
                Text("account.signin.error.title", bundle: .module),
                isPresented: Binding(
                    get: { isOnScreen && sessionStore.signInError != nil },
                    set: { if !$0 { sessionStore.dismissSignInError() } }
                ),
                presenting: sessionStore.signInError
            ) { _ in
                Button(role: .cancel) {
                    sessionStore.dismissSignInError()
                } label: {
                    Text("account.signin.error.close", bundle: .module)
                }
            } message: { error in
                Text(error.message)
            }
    }
}

// MARK: - AccountSignInGate

/// A screen that needs the customer account (Bestellungen, one order, Persönliche Daten): the content
/// for a signed-in customer, otherwise a short reason to sign in with "Anmelden" right there.
/// After the login the content appears in place, so every way into the screen (the Konto tab,
/// the service tiles of Start, "Bestellungen ansehen" after a purchase, a link) works the same.
/// Builds without login show that login is not available yet.
///
/// ```swift
/// AccountSignInGate(sessionStore: sessionStore, reason: .orders) {
///     OrdersScreen(repository: repository, backend: backend, onRoute: onRoute)
/// }
/// ```
public struct AccountSignInGate<Content: View>: View {
    private let sessionStore: CustomerSessionStore
    private let reason: AccountSignInReason
    private let content: () -> Content

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title) private var discSide: CGFloat = 88

    /// Creates the gate.
    ///
    /// - Parameters:
    ///   - sessionStore: The login state.
    ///   - reason: What the screen shows, for its title and the reason to sign in.
    ///   - content: The screen for a signed-in customer.
    public init(sessionStore: CustomerSessionStore, reason: AccountSignInReason, @ViewBuilder content: @escaping () -> Content) {
        self.sessionStore = sessionStore
        self.reason = reason
        self.content = content
    }

    public var body: some View {
        if sessionStore.isSignedIn {
            content()
        } else {
            prompt
        }
    }

    private var prompt: some View {
        ScrollView {
            VStack(spacing: KXSpacing.l) {
                Image(systemName: reason.systemImage)
                    .fontWeight(.light)
                    .kxFont(.title1)
                    .foregroundStyle(KXColor.textPrimary)
                    .frame(width: discSide, height: discSide)
                    .background(KXColor.surface, in: Circle())
                    .accessibilityHidden(true)
                VStack(spacing: KXSpacing.s) {
                    Text("account.gate.title", bundle: .module)
                        .kxFont(.title2)
                        .foregroundStyle(KXColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    reason.message
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                if sessionStore.isAvailable {
                    VStack(spacing: KXSpacing.s) {
                        KXButton(
                            String(localized: "account.signin", bundle: .module),
                            systemImage: "person.crop.circle",
                            isFullWidth: true,
                            isLoading: sessionStore.status == .signingIn
                        ) {
                            Task {
                                await AccountLogin.signIn(with: sessionStore, using: webAuthenticationSession, locale: locale)
                            }
                        }
                        .accessibilityIdentifier("account.gate.signin")
                        Text("account.signin.passwordless", bundle: .module)
                            .kxFont(.footnote)
                            .foregroundStyle(KXColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("account.signin.note", bundle: .module)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account.signin.unavailable")
                }
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.xxl)
            .frame(maxWidth: .infinity)
            .kxReadableWidth()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.gate")
        .kxScreenBackground()
        .navigationTitle(reason.title)
        .navigationBarTitleDisplayMode(.large)
        .accountSignInErrorAlert(sessionStore)
    }
}

// MARK: - AccountSignInReason

/// What the screen behind an ``AccountSignInGate`` shows.
public enum AccountSignInReason: Sendable {
    /// The order list.
    case orders
    /// One order.
    case order
    /// "Rechnungen".
    case invoices
    /// "Treueprogramm".
    case loyalty
    /// "Persönliche Daten": the name and the addresses.
    case profile
}

extension AccountSignInReason {
    /// The title of the screen, the same as once signed in.
    var title: Text {
        switch self {
        case .orders: Text("account.orders.title", bundle: .module)
        case .order: Text("account.order.title", bundle: .module)
        case .invoices: Text("account.invoices.title", bundle: .module)
        case .loyalty: Text("account.loyalty.title", bundle: .module)
        case .profile: Text("account.profile.screen.title", bundle: .module)
        }
    }

    /// Why to sign in.
    var message: Text {
        switch self {
        case .orders, .order: Text("account.gate.orders.message", bundle: .module)
        case .invoices: Text("account.gate.invoices.message", bundle: .module)
        case .loyalty: Text("account.gate.loyalty.message", bundle: .module)
        case .profile: Text("account.gate.profile.message", bundle: .module)
        }
    }

    /// The symbol on the disc, the one of the menu row.
    var systemImage: String {
        switch self {
        case .orders, .order: AccountMenuItem.orders.systemImage
        case .invoices: AccountMenuItem.invoices.systemImage
        case .loyalty: AccountMenuItem.loyalty.systemImage
        case .profile: AccountMenuItem.profile.systemImage
        }
    }
}
