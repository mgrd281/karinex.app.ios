import AuthenticationServices
import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - AccountView

/// The Konto tab (PROMPT.md 6.7).
///
/// - Signed out: the benefits and "Anmelden" (Shopify's passwordless login in
///   `ASWebAuthenticationSession`, ephemeral, so no cookies are shared with Safari), then
///   "Meine Bestellungen": a tap opens the login and, once signed in, the orders right away.
///   Builds without a Customer Account client ID say that login is not available yet.
/// - Signed in: the monogram, name and e-mail address as a card into "Persönliche Daten" (name,
///   addresses, "Konto und Daten löschen"), Meine Bestellungen, Meine Lizenzen, Persönliche
///   Daten, then Merkliste, Einstellungen, Hilfe und Support, Rechtliches and "Abmelden".
/// - Every row has a short line under its title, like the account tab of fashion retail apps.
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
                    menu(AccountMenuItem.general)
                } else {
                    benefits
                    menu((sessionStore.isAvailable ? AccountMenuItem.signedOut : []) + AccountMenuItem.general)
                }
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
        .accountSignInErrorAlert(sessionStore)
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
        await AccountLogin.signIn(with: sessionStore, using: webAuthenticationSession, locale: locale)
    }

    // MARK: Signed in

    /// The signed-in header: the monogram, the name and the e-mail address as one card that
    /// opens "Persönliche Daten".
    private var profileHeader: some View {
        Button {
            onRoute(.account(.profile))
        } label: {
            HStack(spacing: KXSpacing.m) {
                ProfileMonogram(initials: ProfileName.initials(of: sessionStore.customer))
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Group {
                        if let name = ProfileName.displayName(of: sessionStore.customer) {
                            Text(verbatim: name)
                        } else {
                            Text("account.profile.title", bundle: .module)
                        }
                    }
                    .kxFont(.title2)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    if let email = sessionStore.customer?.emailAddress {
                        Text(verbatim: email)
                            .kxFont(.subheadline)
                            .foregroundStyle(KXColor.textSecondary)
                    }
                    Text("account.profile.open", bundle: .module)
                        .fontWeight(.semibold)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textPrimary)
                        .padding(.top, KXSpacing.xxs)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .fontWeight(.medium)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.iconSecondary)
                    .accessibilityHidden(true)
            }
            .padding(KXSpacing.m)
            .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, KXSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("account.profile")
    }

    /// "Abmelden". "Konto löschen" lives in "Persönliche Daten", next to the personal details.
    private var signedInActions: some View {
        KXButton(
            String(localized: "account.signout", bundle: .module),
            systemImage: "rectangle.portrait.and.arrow.right",
            style: .secondary,
            isFullWidth: true
        ) {
            isSignOutConfirmationPresented = true
        }
        .accessibilityIdentifier("account.signout")
    }

    private func signOut() async {
        await AccountLogin.signOut(sessionStore)
    }

    // MARK: Menu

    /// A list of rows on the page, with hairlines between them and above and below the list.
    private func menu(_ items: [AccountMenuItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            KXDivider()
            ForEach(items) { item in
                Button {
                    open(item)
                } label: {
                    AccountMenuRow(item: item)
                }
                .buttonStyle(.plain)
                .disabled(sessionStore.status == .signingIn)
                .accessibilityIdentifier("account.menu.\(item.rawValue)")
                KXDivider()
            }
        }
    }

    /// Opens the screen of `item`. A row that needs the account first runs the login and then
    /// opens its screen, so "Meine Bestellungen" takes one tap and the e-mail code.
    private func open(_ item: AccountMenuItem) {
        guard item.requiresSignIn, !sessionStore.isSignedIn else {
            onRoute(.account(item.destination))
            return
        }
        Task {
            await signIn()
            if sessionStore.isSignedIn {
                onRoute(.account(item.destination))
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

// MARK: - AccountMenuItem

/// The rows of the Konto tab.
enum AccountMenuItem: String, CaseIterable, Identifiable, Sendable {
    case orders
    case licenses
    case profile
    case wishlist
    case settings
    case support
    case legal

    /// The rows only a signed-in customer sees.
    static let signedIn: [AccountMenuItem] = [.orders, .licenses, .profile]
    /// The rows that lead into the login when nobody is signed in.
    static let signedOut: [AccountMenuItem] = [.orders]
    /// The rows everyone sees.
    static let general: [AccountMenuItem] = [.wishlist, .settings, .support, .legal]

    /// Whether the row's screen needs a signed-in customer.
    var requiresSignIn: Bool {
        switch self {
        case .orders, .licenses, .profile: true
        case .wishlist, .settings, .support, .legal: false
        }
    }

    var id: String {
        rawValue
    }

    var destination: AccountDestination {
        switch self {
        case .orders: .orders
        case .licenses: .licenses(orderID: nil)
        case .profile: .profile
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
        case .profile: "person.text.rectangle"
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
        case .profile: String(localized: "account.menu.profile", bundle: .module)
        case .wishlist: String(localized: "account.menu.wishlist", bundle: .module)
        case .settings: String(localized: "account.menu.settings", bundle: .module)
        case .support: String(localized: "account.menu.support", bundle: .module)
        case .legal: String(localized: "account.menu.legal", bundle: .module)
        }
    }

    /// The short line under the title.
    var subtitle: String {
        switch self {
        case .orders: String(localized: "account.menu.orders.subtitle", bundle: .module)
        case .licenses: String(localized: "account.menu.licenses.subtitle", bundle: .module)
        case .profile: String(localized: "account.menu.profile.subtitle", bundle: .module)
        case .wishlist: String(localized: "account.menu.wishlist.subtitle", bundle: .module)
        case .settings: String(localized: "account.menu.settings.subtitle", bundle: .module)
        case .support: String(localized: "account.menu.support.subtitle", bundle: .module)
        case .legal: String(localized: "account.menu.legal.subtitle", bundle: .module)
        }
    }
}

/// One row of the menu: the symbol, the title with its short line below, and the chevron.
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
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(item.title)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                Text(item.subtitle)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .fontWeight(.medium)
                .kxFont(.footnote)
                .foregroundStyle(KXColor.iconSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, KXSpacing.m)
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
