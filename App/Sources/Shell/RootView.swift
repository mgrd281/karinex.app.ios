import AccountFeature
import CartFeature
import CatalogFeature
import Core
import HomeFeature
import SearchFeature
import SwiftUI

// MARK: - RootView

/// The root of the app: a tab bar with Start, Shop, Suche, Warenkorb and Konto, each tab with
/// its own `NavigationStack`, and the offline banner on top.
///
/// The tint is left to the `AccentColor` asset (forest green in light mode, gold in dark mode).
/// A color scheme forced with `-kx.appearance light|dark` overrides the system appearance.
struct RootView: View {
    @Environment(AppContainer.self) private var container

    @State private var selectedTab = AppTab.home

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    rootScreen(for: tab)
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                        .accessibilityIdentifier(tab.accessibilityIdentifier)
                }
                .tag(tab)
            }
        }
        .offlineBanner(monitor: container.networkMonitor)
        .preferredColorScheme(container.launchEnvironment.forcedAppearance?.colorScheme)
    }

    /// The root screen of `tab`. Screens that lead into the range switch to the Shop tab.
    @ViewBuilder
    private func rootScreen(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(onBrowse: { selectedTab = .shop })
        case .shop:
            CatalogView()
        case .search:
            SearchView()
        case .cart:
            CartView(onBrowse: { selectedTab = .shop })
        case .account:
            AccountView(
                appVersion: container.configuration.appVersion,
                buildNumber: container.configuration.buildNumber
            )
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
