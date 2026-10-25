import AccountFeature
import CartFeature
import CatalogFeature
import CheckoutFeature
import Combine
import CommerceUI
import Core
import DesignSystem
import HomeFeature
import LegalFeature
import LicensesFeature
import ProductFeature
import SearchFeature
import SettingsFeature
import SupportFeature
import SwiftUI
import UIKit

// MARK: - RootView

/// The root of the app: five tabs (Shop, Suche, Start, Warenkorb, Konto), each with its own
/// `NavigationStack`, the KARINEX bottom bar (``AppTabBar``) in place of the system tab bar, and
/// the offline banner on top.
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
/// - The Warenkorb item shows the number of items as a badge.
/// - The bottom bar hides while the keyboard is up, like the system tab bar.
///
/// The tint is left to the `AccentColor` asset (black in light mode, white in dark mode).
/// A color scheme forced with `-kx.appearance light|dark` overrides the system appearance.
///
/// The bar carries the identifier `tab.bar`, each item `tab.<name>` and its title as the
/// VoiceOver label.
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = AppRouter()
    @State private var isCheckoutPresented = false
    @State private var isMarketSheetPresented = false
    @State private var hasStarted = false
    @State private var wasInBackground = false
    @State private var isKeyboardVisible = false

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: path(for: tab)) {
                    rootScreen(for: tab)
                        .toolbar(.hidden, for: .tabBar)
                        .navigationDestination(for: CommerceRoute.self) { route in
                            destination(for: route, in: tab)
                                .toolbar(.hidden, for: .tabBar)
                        }
                }
                // One bar per tab: an inset on the navigation stack reaches every pushed screen,
                // so bars of those screens (the product purchase bar) sit on top of it.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isKeyboardVisible {
                        AppTabBar(selection: router.selectedTab, cartCount: container.cartStore.itemCount) { selected in
                            router.select(selected, popToRoot: selected == router.selectedTab)
                        }
                    }
                }
                .tag(tab)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .offlineBanner(monitor: container.networkMonitor)
        .commerceCountry(container.marketStore.selection.country)
        .environment(container.savedProductsStore)
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
        .overlay {
            if scenePhase != .active {
                PrivacyCover()
            }
        }
        .preferredColorScheme(container.launchEnvironment.forcedAppearance?.colorScheme ?? container.settingsStore.appearance.colorScheme)
    }

    // MARK: Tabs

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
                onRoute: { router.open($0, from: .home) },
                onBrowse: { router.select(.shop) }
            )
        case .shop:
            CatalogView(catalog: container.catalogRepository, onRoute: { router.open($0, from: .shop) })
        case .search:
            SearchView(
                search: container.searchRepository,
                preferences: container.preferences,
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
            OrdersScreen(repository: container.customerRepository, backend: container.backendClient, onRoute: onRoute)
        case let .order(id):
            OrderDetailScreen(orderID: id, repository: container.customerRepository, backend: container.backendClient, onRoute: onRoute)
        case let .licenses(orderID):
            LicenseVaultScreen(
                orderID: orderID,
                backend: container.backendClient,
                cache: container.licenseCache,
                locksVault: container.settingsStore.locksLicenses,
                onRoute: onRoute
            )
        case .addresses:
            AddressesScreen(repository: container.customerRepository, countries: addressCountries)
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

// MARK: - AppTabBar

/// The bottom bar in the style of fashion retail apps: thin line icons without titles and the
/// KARINEX wordmark in the middle for Start, on the page background with a hairline on top. A
/// short ink line marks the selected tab. Tapping the selected tab again shows its root screen
/// (handled by the caller). The Warenkorb icon carries the number of items.
///
/// VoiceOver reads each item with its title, the selected state and, for Warenkorb, the number
/// of items ("Warenkorb, 2 Artikel").
private struct AppTabBar: View {
    let selection: AppTab
    let cartCount: Int
    let onSelect: @MainActor (AppTab) -> Void

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 22

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
                    .frame(maxWidth: tab == .home ? nil : .infinity)
            }
        }
        .padding(.horizontal, KXSpacing.xs)
        .padding(.top, KXSpacing.xxs)
        .frame(maxWidth: .infinity)
        .background {
            KXColor.background
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            KXDivider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tab.bar")
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: KXSpacing.xs) {
                glyph(tab)
                    .frame(minHeight: min(iconSize, 30) + KXSpacing.xxs)
                Capsule(style: .continuous)
                    .fill(isSelected ? KXColor.textPrimary : Color.clear)
                    .frame(width: tab == .home ? nil : min(iconSize, 30) + KXSpacing.xs, height: KXBorder.emphasis)
                    .frame(maxWidth: tab == .home ? .infinity : nil)
            }
            .padding(.horizontal, tab == .home ? KXSpacing.s : 0)
            .padding(.vertical, KXSpacing.xxs)
            .frame(minWidth: KXSpacing.minimumTapTarget, minHeight: KXSpacing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityValue(Text(tab == .cart ? AppTab.cartBadgeAccessibilityValue(count: cartCount) : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    @ViewBuilder
    private func glyph(_ tab: AppTab) -> some View {
        if tab == .home {
            KXWordmark(size: .small)
                .accessibilityHidden(true)
        } else {
            Image(systemName: tab.systemImage)
                .font(.system(size: min(iconSize, 30), weight: .light))
                .foregroundStyle(KXColor.textPrimary)
                .overlay(alignment: .topTrailing) {
                    if tab == .cart, cartCount > 0 {
                        Text(cartCount, format: .number)
                            .monospacedDigit()
                            .kxFont(.caption)
                            .foregroundStyle(KXColor.textOnBrand)
                            .padding(.horizontal, KXSpacing.xxs)
                            .frame(minWidth: KXSpacing.m, minHeight: KXSpacing.m)
                            .background(KXColor.brand, in: Capsule(style: .continuous))
                            .offset(x: KXSpacing.xs, y: -KXSpacing.xxs)
                    }
                }
                .accessibilityHidden(true)
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
