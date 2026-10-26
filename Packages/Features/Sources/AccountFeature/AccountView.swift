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
                    profileHeader
                    menu(AccountMenuItem.signedIn)
                } else {
                    benefits
                }
                menu(AccountMenuItem.general)
                if sessionStore.isSignedIn {
                    signedInActions
                }
                versionFooter
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
            .kxReadableWidth()
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

    /// The signed-out header: the promise, the benefits with their symbols on light grey discs,
    /// then "Anmelden" or the note that login is not available yet. No card, as on the account
    /// tab of fashion retail apps.
    private var benefits: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text("account.intro.eyebrow", bundle: .module)
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.textSecondary)
                Text("account.intro.title", bundle: .module)
                    .kxFont(.title1)
                    .foregroundStyle(KXColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                ForEach(AccountBenefit.allCases) { benefit in
                    AccountBenefitRow(benefit: benefit)
                }
            }
            if sessionStore.isAvailable {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
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
                }
            } else {
                Label {
                    Text("account.signin.note", bundle: .module)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "clock")
                        .accessibilityHidden(true)
                }
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textSecondary)
                .padding(KXSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous))
                .accessibilityIdentifier("account.signin.unavailable")
            }
        }
        .padding(.top, KXSpacing.xs)
        .accessibilityElement(children: .contain)
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

    /// The signed-in header: a disc with the person symbol, the name and the e-mail address.
    private var profileHeader: some View {
        HStack(spacing: KXSpacing.m) {
            Image(systemName: "person.fill")
                .kxFont(.title2)
                .foregroundStyle(KXColor.textSecondary)
                .frame(width: KXSpacing.xxxl, height: KXSpacing.xxxl)
                .background(KXColor.surface, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text("account.profile.eyebrow", bundle: .module)
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.textSecondary)
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
        }
        .padding(.top, KXSpacing.xs)
        .accessibilityElement(children: .combine)
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

    /// A list of rows on the page, with hairlines between them and above and below the list.
    private func menu(_ items: [AccountMenuItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            KXDivider()
            ForEach(items) { item in
                Button {
                    onRoute(.account(item.destination))
                } label: {
                    AccountMenuRow(item: item)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.menu.\(item.rawValue)")
                KXDivider()
            }
        }
    }

    // MARK: About

    /// The store logo and the version, small and centered at the end of the page.
    private var versionFooter: some View {
        VStack(spacing: KXSpacing.xs) {
            KXWordmark(size: .small, color: KXColor.textTertiary)
                .accessibilityHidden(true)
            if !appInfo.summary.isEmpty {
                HStack(spacing: KXSpacing.xxs) {
                    Text("account.about.version", bundle: .module)
                    Text(verbatim: appInfo.summary)
                        .monospacedDigit()
                }
                .kxFont(.caption)
                .foregroundStyle(KXColor.textSecondary)
                .accessibilityElement(children: .combine)
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
            .padding(.top, KXSpacing.m)
            .accessibilityIdentifier("account.designSystem")
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.top, KXSpacing.m)
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
                .fontWeight(.light)
                .kxFont(.title3)
                .foregroundStyle(KXColor.textPrimary)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(item.title)
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .fontWeight(.medium)
                .kxFont(.footnote)
                .foregroundStyle(KXColor.iconSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, KXSpacing.s)
        .frame(minHeight: KXSpacing.minimumTapTarget + KXSpacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Benefit row

private struct AccountBenefitRow: View {
    let benefit: AccountBenefit

    @ScaledMetric(relativeTo: .body) private var discSide: CGFloat = 44

    var body: some View {
        HStack(spacing: KXSpacing.m) {
            Image(systemName: benefit.systemImage)
                .fontWeight(.light)
                .kxFont(.title3)
                .foregroundStyle(KXColor.textPrimary)
                .frame(width: discSide, height: discSide)
                .background(KXColor.surface, in: Circle())
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
