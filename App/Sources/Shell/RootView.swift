import AccountFeature
import CartFeature
import CatalogFeature
import CheckoutFeature
import CommerceUI
import Core
import DesignSystem
import HomeFeature
import LegalFeature
import LicensesFeature
import ProductFeature
import SearchFeature
import SettingsFeature
import ShopifyKit
import SupportFeature
import SwiftUI
import UIKit

// MARK: - RootView

/// The root of the app: a tab bar with Start, Shop, Suche, Warenkorb and Konto, each tab with
/// its own `NavigationStack`, and the offline banner on top.
///
/// - Navigation: features ask for ``CommerceRoute``s; ``AppRouter`` pushes them onto the stack of
///   the tab they came from and this view maps them to screens (product, collection, article,
///   search results). `.cart` switches to the Warenkorb tab.
/// - Deep links (`karinex://`) and Universal Links (`karinex.de`) go through `DeepLinkParser`
///   and open the destination in the tab that owns it.
/// - Checkout: "Jetzt kaufen" and "Zur Kasse" present Shopify checkout over the whole app; after
///   "Weiter einkaufen" the Start tab is shown.
/// - Launch: the market is resolved and the stored cart re-read; the cart is read again
///   whenever the app returns from the background. The one-time market confirmation sheet
///   appears after the first resolution (not in UI test runs, see `MarketConfirmationPolicy`).
/// - Opening: ``KXLaunchIntro`` zooms into the logo of the launch screen and reveals the app
///   (not in UI test runs).
/// - The Warenkorb tab shows a shopping bag with the number of items beside it (``CartTabIcon``)
///   instead of a red badge; VoiceOver reads the number as the tab's value.
///
/// The tint is left to the `AccentColor` asset (black in light mode, white in dark mode).
/// A color scheme forced with `-kx.appearance light|dark` overrides the system appearance.
///
/// Each tab item carries the identifier `tab.<name>`. SwiftUI does not forward an identifier set
/// on a `tabItem` label to the tab bar button on every iOS release, so the UI tests fall back to
/// the localized tab title (they run in German).
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

    @State private var router = AppRouter()
    @State private var isCheckoutPresented = false
    @State private var isMarketSheetPresented = false
    @State private var hasStarted = false
    @State private var wasInBackground = false
    @State private var showsLaunchIntro = true

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: path(for: tab)) {
                    rootScreen(for: tab)
                        .navigationDestination(for: CommerceRoute.self) { route in
                            destination(for: route, in: tab)
                        }
                }
                .tabItem {
                    // Outline symbols everywhere, matching the shopping bag of the Warenkorb tab.
                    tabLabel(for: tab)
                        .environment(\.symbolVariants, .none)
                }
                .tag(tab)
            }
        }
        .offlineBanner(monitor: container.networkMonitor)
        .commerceCountry(container.marketStore.selection.country)
        .environment(container.savedProductsStore)
        .environment(container.saveCountStore)
        .environment(container.paymentMethodsStore)
        .environment(\.productLookup, container.productLookup)
        .kxCheckout(isPresented: $isCheckoutPresented, cartStore: container.cartStore) { order in
            container.liveActivities.startDelivery(orderReference: order.id)
            router.finishCheckout()
        }
        .sheet(isPresented: $isMarketSheetPresented) {
            MarketConfirmationSheet(store: container.marketStore)
        }
        .onOpenURL { url in
            router.openDeepLink(url)
        }
        .onChange(of: container.pushCoordinator.pendingURL) { _, url in
            guard let url else { return }
            container.pushCoordinator.pendingURL = nil
            router.openDeepLink(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                router.openDeepLink(url)
            }
        }
        .task {
            await start()
        }
        .onChange(of: scenePhase) { _, phase in
            handle(phase)
        }
        .task(id: container.cartStore.itemCount) {
            await Task.yield()
            TabBarItemAccessibility.setValue(AppTab.cartBadgeAccessibilityValue(count: container.cartStore.itemCount), for: .cart)
        }
        .overlay {
            if scenePhase != .active {
                PrivacyCover()
            }
        }
        .overlay {
            if showsLaunchIntro, !container.launchEnvironment.isUITesting {
                KXLaunchIntro(logo: Image("LaunchLogo")) {
                    showsLaunchIntro = false
                }
            }
        }
        .preferredColorScheme(container.launchEnvironment.forcedAppearance?.colorScheme ?? container.settingsStore.appearance.colorScheme)
    }

    // MARK: Tabs

    @ViewBuilder
    private func tabLabel(for tab: AppTab) -> some View {
        let count = container.cartStore.itemCount
        if tab == .cart, let icon = CartTabIcon.image(count: count, scale: displayScale) {
            Label {
                Text(tab.title)
            } icon: {
                Image(uiImage: icon)
            }
            .accessibilityIdentifier(tab.accessibilityIdentifier)
            .accessibilityValue(AppTab.cartBadgeAccessibilityValue(count: count))
        } else {
            Label(tab.title, systemImage: tab.systemImage)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
        }
    }

    private func path(for tab: AppTab) -> Binding<[CommerceRoute]> {
        Binding(
            get: { router.path(for: tab) },
            set: { router.setPath($0, for: tab) }
        )
    }

    /// The root screen of `tab`.
    @ViewBuilder
    private func rootScreen(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(
                catalog: container.catalogRepository,
                content: container.contentRepository,
                cyclesShowcase: !container.launchEnvironment.isUITesting,
                onRoute: { router.open($0, from: .home) },
                onBrowse: { router.select(.shop) }
            )
        case .shop:
            CatalogView(catalog: container.catalogRepository, onRoute: { router.open($0, from: .shop) })
        case .search:
            SearchView(
                search: container.searchRepository,
                preferences: container.preferences,
                catalog: container.catalogRepository,
                fieldActivation: router.searchFieldRequests,
                onRoute: { router.open($0, from: .search) }
            )
        case .cart:
            cartScreen(in: .cart)
        case .account:
            accountOverview(in: .account)
        }
    }

    private func accountOverview(in tab: AppTab) -> some View {
        AccountView(
            sessionStore: container.sessionStore,
            appVersion: container.configuration.appVersion,
            buildNumber: container.configuration.buildNumber,
            onRoute: { router.open($0, from: tab) }
        )
    }

    /// The screen of a route pushed onto the stack of `tab`.
    @ViewBuilder
    private func destination(for route: CommerceRoute, in tab: AppTab) -> some View {
        switch route {
        case let .product(handle):
            ProductDetailScreen(
                handle: handle,
                catalog: container.catalogRepository,
                cartStore: container.cartStore,
                onRoute: { router.open($0, from: tab) },
                onBuyNow: { isCheckoutPresented = true }
            )
        case let .collection(handle, title):
            CollectionScreen(
                handle: handle,
                title: title,
                catalog: container.catalogRepository,
                onRoute: { router.open($0, from: tab) }
            )
        case let .article(blogHandle, articleHandle):
            ArticleScreen(blogHandle: blogHandle, articleHandle: articleHandle, repository: container.contentRepository)
        case let .search(query):
            SearchResultsScreen(query: query, search: container.searchRepository, onRoute: { router.open($0, from: tab) })
        case .cart:
            // The router switches to the Warenkorb tab instead of pushing `.cart`; the mapping
            // exists so every route has a screen.
            cartScreen(in: tab)
        case let .account(destination):
            accountScreen(for: destination, in: tab)
        }
    }

    /// The screen of an account destination.
    @ViewBuilder
    private func accountScreen(for destination: AccountDestination, in tab: AppTab) -> some View {
        let onRoute: @MainActor (CommerceRoute) -> Void = { router.open($0, from: tab) }
        switch destination {
        case .overview:
            accountOverview(in: tab)
        case .orders:
            AccountSignInGate(sessionStore: container.sessionStore, reason: .orders) {
                OrdersScreen(repository: container.customerRepository, backend: container.backendClient, onRoute: onRoute)
            }
        case .invoices:
            AccountSignInGate(sessionStore: container.sessionStore, reason: .invoices) {
                InvoicesScreen(repository: container.customerRepository, backend: container.backendClient, onRoute: onRoute)
            }
        case .loyalty:
            AccountSignInGate(sessionStore: container.sessionStore, reason: .loyalty) {
                LoyaltyScreen(backend: container.backendClient) { code in
                    await container.cartStore.applyDiscountCode(code) == .applied
                }
            }
        case .referral:
            AccountSignInGate(sessionStore: container.sessionStore, reason: .referral) {
                ReferralScreen(backend: container.backendClient)
            }
        case let .order(id):
            AccountSignInGate(sessionStore: container.sessionStore, reason: .order) {
                OrderDetailScreen(
                    orderID: id,
                    repository: container.customerRepository,
                    backend: container.backendClient,
                    onRoute: onRoute,
                    onReorder: { lines in
                        // "Erneut kaufen": the same products and quantities, then the cart.
                        for line in lines {
                            if let variantID = line.variantID {
                                _ = await container.cartStore.add(variantID: variantID, quantity: line.quantity)
                            }
                        }
                        router.select(.cart)
                    }
                )
            }
        case let .licenses(orderID):
            LicenseVaultScreen(
                orderID: orderID,
                backend: container.backendClient,
                cache: container.licenseCache,
                locksVault: container.settingsStore.locksLicenses,
                onRoute: onRoute
            )
        case .profile:
            AccountSignInGate(sessionStore: container.sessionStore, reason: .profile) {
                ProfileScreen(
                    repository: container.customerRepository,
                    countries: addressCountries,
                    sessionStore: container.sessionStore,
                    onRoute: onRoute
                )
            }
        case .wishlist:
            WishlistScreen(savedProducts: container.savedProductsStore, onRoute: onRoute)
        case let .support(orderName):
            SupportScreen(orderName: orderName, backend: container.backendClient, content: container.contentRepository, onRoute: onRoute)
        case .legal:
            LegalListScreen(onRoute: onRoute)
        case let .legalDocument(kind):
            LegalDocumentScreen(kind: kind, repository: container.legalRepository)
        case .settings:
            SettingsScreen(
                marketStore: container.marketStore,
                settings: container.settingsStore,
                consentStore: container.consentStore,
                pushCoordinator: container.pushCoordinator,
                appVersion: AccountVersionText.summary(
                    version: container.configuration.appVersion,
                    build: container.configuration.buildNumber
                ),
                onRoute: onRoute
            )
        case .deleteAccount:
            DeleteAccountScreen(backend: container.backendClient, sessionStore: container.sessionStore)
        }
    }

    /// The countries of the address form: the store's markets, or Germany before they loaded.
    private var addressCountries: [AddressCountryOption] {
        let countries = container.marketStore.availableCountries()
        guard !countries.isEmpty else {
            return [AddressCountryOption(code: "DE", name: Locale.current.localizedString(forRegionCode: "DE") ?? "DE")]
        }
        return countries.map { AddressCountryOption(code: $0.isoCode.rawValue, name: MarketStore.displayName(of: $0)) }
    }

    private func cartScreen(in tab: AppTab) -> some View {
        CartView(
            cartStore: container.cartStore,
            catalog: container.catalogRepository,
            onRoute: { router.open($0, from: tab) },
            onBrowse: { router.select(.shop) },
            onCheckout: { isCheckoutPresented = true }
        )
    }

    // MARK: Lifecycle

    /// Starts the shared state once per launch and then offers the market confirmation.
    private func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await container.start()
        if container.isMarketConfirmationEnabled, container.marketStore.needsConfirmation, !isCheckoutPresented {
            isMarketSheetPresented = true
        }
    }

    /// Re-reads the cart when the app returns from the background.
    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .background:
            wasInBackground = true
        case .active:
            guard wasInBackground else { return }
            wasInBackground = false
            Task {
                await container.cartStore.refresh()
            }
            Task {
                await container.liveActivities.refresh()
            }
        default:
            break
        }
    }
}

// MARK: - Previews

#Preview("RootView, light") {
    RootView()
        .environment(AppContainer.preview())
}

#Preview("RootView, dark") {
    RootView()
        .environment(AppContainer.preview())
        .preferredColorScheme(.dark)
}

#Preview("RootView, offline") {
    RootView()
        .environment(AppContainer.preview(networkStatus: .offline))
}

#Preview("RootView, accessibility size") {
    RootView()
        .environment(AppContainer.preview())
        .dynamicTypeSize(.accessibility2)
}

// MARK: - CartTabIcon

/// The Warenkorb tab icon in the style of fashion retail apps: ``CartBagIcon``, the outline tote
/// with its tall handle and the number of items beside it, in the tab's color, instead of a red
/// badge.
///
/// A tab bar item takes only an image and a title, so the icon is rendered into a template image
/// that the tab bar tints like its other symbols. An invisible copy of the figure on the leading
/// side keeps the bag centered above the title. The icon keeps one size at every text size, like
/// the system tab symbols.
struct CartTabIcon: View {
    /// The number of items in the cart.
    let count: Int

    var body: some View {
        CartBagIcon(count: count, isCentered: true)
            .dynamicTypeSize(.large)
    }

    /// The icon for `count` items as a template image at `scale`, or `nil` if rendering fails.
    @MainActor
    static func image(count: Int, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: CartTabIcon(count: count))
        renderer.scale = scale
        return renderer.uiImage?.withRenderingMode(.alwaysTemplate)
    }
}

// MARK: - TabBarItemAccessibility

/// Gives a tab its VoiceOver value, such as "2 Artikel" for the Warenkorb tab. The cart count is
/// drawn into the icon instead of a badge, and SwiftUI does not forward accessibility modifiers
/// of a `tabItem` label, so the value goes onto the `UITabBarItem` of the tab bar that SwiftUI
/// creates.
@MainActor
enum TabBarItemAccessibility {
    /// Sets `value` (empty clears it) on the item of `tab` in every window's tab bar.
    static func setValue(_ value: String, for tab: AppTab) {
        guard let index = AppTab.allCases.firstIndex(of: tab) else { return }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows {
            guard let items = tabBarController(in: window.rootViewController)?.tabBar.items,
                  items.indices.contains(index)
            else { continue }
            items[index].accessibilityValue = value.isEmpty ? nil : value
        }
    }

    /// The first tab bar controller in the hierarchy below `controller`.
    private static func tabBarController(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tabBarController = controller as? UITabBarController {
            return tabBarController
        }
        for child in controller.children {
            if let found = tabBarController(in: child) {
                return found
            }
        }
        return nil
    }
}
