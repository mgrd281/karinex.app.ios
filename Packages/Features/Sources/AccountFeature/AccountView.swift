import AuthenticationServices
import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - AccountView

/// The Konto tab (PROMPT.md 6.7).
///
/// - Signed out: the benefits and "Anmelden" (Shopify's passwordless login in
///   `ASWebAuthenticationSession`, ephemeral, so no cookies are shared with Safari). Builds
///   without a Customer Account client ID say that login is not available yet.
/// - Signed in: the name and e-mail address, Bestellungen, Meine Lizenzen, Adressen, then
///   Einstellungen, Hilfe und Support, Rechtliches, "Abmelden" and "Konto löschen".
/// - Support, legal texts and settings are reachable in both states, so the Impressum and the
///   privacy policy are always within two taps.
public struct AccountView: View {
    private let appInfo: AccountAppInfo
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @Bindable private var sessionStore: CustomerSessionStore
    @State private var isSignOutConfirmationPresented = false

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    /// Creates the Konto tab.
    ///
    /// - Parameters:
    ///   - sessionStore: The login state.
    ///   - appVersion: The marketing version.
    ///   - buildNumber: The build number.
    ///   - onRoute: Opens the account screens.
    public init(
        sessionStore: CustomerSessionStore,
        appVersion: String,
        buildNumber: String,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        _sessionStore = Bindable(sessionStore)
        appInfo = AccountAppInfo(version: appVersion, build: buildNumber)
        self.onRoute = onRoute
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                if sessionStore.isSignedIn {
                    profileCard
                    menu(AccountMenuItem.signedIn)
                } else {
                    benefitsCard
                }
                menu(AccountMenuItem.general)
                if sessionStore.isSignedIn {
                    signedInActions
                }
                aboutSection
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.account")
        .kxScreenBackground()
        .navigationTitle(Text("account.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await sessionStore.loadCustomer() }
        .task {
            if sessionStore.isSignedIn, sessionStore.customer == nil {
                await sessionStore.loadCustomer()
            }
        }
        .alert(
            Text("account.signin.error.title", bundle: .module),
            isPresented: Binding(
                get: { sessionStore.signInError != nil },
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
        .confirmationDialog(
            Text("account.signout.confirm.title", bundle: .module),
            isPresented: $isSignOutConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await signOut() }
            } label: {
                Text("account.signout", bundle: .module)
            }
        }
    }

    // MARK: Signed out

    private var benefitsCard: some View {
        KXCard(showsInsetRing: true) {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    Text("account.intro.eyebrow", bundle: .module)
                        .kxFont(.eyebrow)
                        .foregroundStyle(KXColor.accentText)
                    Text("account.intro.title", bundle: .module)
                        .kxFont(.title2)
                        .foregroundStyle(KXColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    ForEach(AccountBenefit.allCases) { benefit in
                        AccountBenefitRow(benefit: benefit)
                    }
                }
                KXDivider()
                if sessionStore.isAvailable {
                    KXButton(
                        String(localized: "account.signin", bundle: .module),
                        systemImage: "person.crop.circle",
                        isFullWidth: true,
                        isLoading: sessionStore.status == .signingIn
                    ) {
                        Task { await signIn() }
                    }
                    .accessibilityIdentifier("account.signin")
                    Text("account.signin.passwordless", bundle: .module)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("account.signin.note", bundle: .module)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account.signin.unavailable")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(KXSpacing.xs)
        }
        .accessibilityIdentifier("account.benefits")
    }

    private func signIn() async {
        let session = webAuthenticationSession
        await sessionStore.signIn(locale: AccountLoginLocale.code(for: locale)) { url, scheme in
            do {
                return try await session.authenticate(using: url, callbackURLScheme: scheme, preferredBrowserSession: .ephemeral)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                throw CustomerAccountAuthError.cancelled
            }
        }
    }

    // MARK: Signed in

    private var profileCard: some View {
        KXCard(showsInsetRing: true) {
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text("account.profile.eyebrow", bundle: .module)
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.accentText)
                if let customer = sessionStore.customer {
                    Text(customer.displayName)
                        .kxFont(.title2)
                        .foregroundStyle(KXColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let email = customer.emailAddress, email != customer.displayName {
                        Text(email)
                            .kxFont(.subheadline)
                            .foregroundStyle(KXColor.textSecondary)
                    }
                } else {
                    Text("account.profile.title", bundle: .module)
                        .kxFont(.title2)
                        .foregroundStyle(KXColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(KXSpacing.xs)
        }
        .accessibilityIdentifier("account.profile")
    }

    private var signedInActions: some View {
        VStack(spacing: KXSpacing.s) {
            KXButton(
                String(localized: "account.signout", bundle: .module),
                systemImage: "rectangle.portrait.and.arrow.right",
                style: .secondary,
                isFullWidth: true
            ) {
                isSignOutConfirmationPresented = true
            }
            .accessibilityIdentifier("account.signout")
            KXButton(
                String(localized: "account.delete", bundle: .module),
                style: .tertiary,
                isFullWidth: true
            ) {
                onRoute(.account(.deleteAccount))
            }
            .accessibilityIdentifier("account.delete")
        }
    }

    private func signOut() async {
        guard let endSession = await sessionStore.signOut() else { return }
        // Ends the Shopify session in the background; the local logout is already complete.
        let request = URLRequest(url: endSession)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: Menu

    private func menu(_ items: [AccountMenuItem]) -> some View {
        KXCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    Button {
                        onRoute(.account(item.destination))
                    } label: {
                        AccountMenuRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.menu.\(item.rawValue)")
                    if item != items.last {
                        KXDivider()
                            .padding(.leading, KXSpacing.m)
                    }
                }
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "account.about.title", bundle: .module))
            if !appInfo.summary.isEmpty {
                KXCard {
                    KXSpecRow(String(localized: "account.about.version", bundle: .module), value: appInfo.summary)
                }
                .accessibilityIdentifier("account.about")
            }
            #if DEBUG
            NavigationLink {
                KXDesignSystemGallery()
            } label: {
                // DEBUG-only developer tool; never shipped, so the label is not localized.
                Label {
                    Text(verbatim: "Design System")
                } icon: {
                    Image(systemName: "paintpalette")
                }
            }
            .buttonStyle(.kx(.secondary, isFullWidth: true))
            .accessibilityIdentifier("account.designSystem")
            #endif
        }
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

// MARK: - AccountMenuItem

/// The rows of the Konto tab.
enum AccountMenuItem: String, CaseIterable, Identifiable, Sendable {
    case orders
    case licenses
    case addresses
    case wishlist
    case settings
    case support
    case legal

    /// The rows only a signed-in customer sees.
    static let signedIn: [AccountMenuItem] = [.orders, .licenses, .addresses]
    /// The rows everyone sees.
    static let general: [AccountMenuItem] = [.wishlist, .settings, .support, .legal]

    var id: String {
        rawValue
    }

    var destination: AccountDestination {
        switch self {
        case .orders: .orders
        case .licenses: .licenses(orderID: nil)
        case .addresses: .addresses
        case .wishlist: .wishlist
        case .settings: .settings
        case .support: .support(orderName: nil)
        case .legal: .legal
        }
    }

    var systemImage: String {
        switch self {
        case .orders: "shippingbox"
        case .licenses: "key"
        case .addresses: "house"
        case .wishlist: "heart"
        case .settings: "gearshape"
        case .support: "questionmark.bubble"
        case .legal: "doc.text"
        }
    }

    var title: String {
        switch self {
        case .orders: String(localized: "account.menu.orders", bundle: .module)
        case .licenses: String(localized: "account.menu.licenses", bundle: .module)
        case .addresses: String(localized: "account.menu.addresses", bundle: .module)
        case .wishlist: String(localized: "account.menu.wishlist", bundle: .module)
        case .settings: String(localized: "account.menu.settings", bundle: .module)
        case .support: String(localized: "account.menu.support", bundle: .module)
        case .legal: String(localized: "account.menu.legal", bundle: .module)
        }
    }
}

/// One row of the menu.
private struct AccountMenuRow: View {
    let item: AccountMenuItem

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: KXSpacing.m) {
            Image(systemName: item.systemImage)
                .kxFont(.body)
                .foregroundStyle(KXColor.brand)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(item.title)
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .kxFont(.footnote)
                .foregroundStyle(KXColor.iconSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, KXSpacing.m)
        .frame(minHeight: KXSpacing.minimumTapTarget + KXSpacing.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Benefit row

private struct AccountBenefitRow: View {
    let benefit: AccountBenefit

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
            Image(systemName: benefit.systemImage)
                .fontWeight(.medium)
                .kxFont(.body)
                .foregroundStyle(KXColor.brand)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(benefit.text)
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("AccountView, signed out") {
    NavigationStack {
        AccountView(
            sessionStore: CustomerSessionStore(session: nil, repository: nil, callbackScheme: nil, hasStoredTokens: false),
            appVersion: "0.2.0",
            buildNumber: "1",
            onRoute: { _ in }
        )
    }
}
