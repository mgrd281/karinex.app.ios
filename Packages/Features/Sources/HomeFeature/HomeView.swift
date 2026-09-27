import DesignSystem
import SwiftUI

// MARK: - HomeView

/// The Start tab: an editorial hero with the call to action into the range, the trust strip
/// with the four brand facts (the money-back promise opens its conditions), and the support card
/// with channels and service hours.
///
/// Phase 0 shows fixed business content only. Product modules (deals, category rows,
/// bestsellers, guides) are added in Phase 1 from the Storefront API.
///
/// Place it inside a `NavigationStack`. The navigation bar is hidden because the hero carries
/// the wordmark; a solid backdrop behind the status bar keeps scrolled content legible.
///
/// ```swift
/// NavigationStack {
///     HomeView(onBrowse: { selectedTab = .shop })
/// }
/// ```
public struct HomeView: View {
    private let onBrowse: @MainActor () -> Void

    @State private var isMoneyBackConditionPresented = false

    /// Creates the Start screen.
    ///
    /// - Parameter onBrowse: Called when the user asks to see the range ("Zum Sortiment"),
    ///   typically by switching to the Shop tab.
    public init(onBrowse: @escaping @MainActor () -> Void) {
        self.onBrowse = onBrowse
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xxl) {
                HomeHero(onBrowse: onBrowse)
                HomeTrustSection(isConditionPresented: $isMoneyBackConditionPresented)
                HomeSupportSection()
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.top, KXSpacing.s)
            .padding(.bottom, KXSpacing.xl)
        }
        .accessibilityIdentifier("screen.home")
        .safeAreaInset(edge: .top, spacing: 0) {
            statusBarBackdrop
        }
        .kxScreenBackground()
        .navigationTitle(Text("home.title", bundle: .module))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isMoneyBackConditionPresented) {
            MoneyBackConditionSheet()
        }
    }

    /// A zero-height view whose page-colored background extends behind the status bar, so that
    /// content scrolling under the hidden navigation bar does not collide with the status bar.
    private var statusBarBackdrop: some View {
        Color.clear
            .frame(height: 0)
            .background(KXColor.background)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("HomeView, light") {
    NavigationStack {
        HomeView(onBrowse: {})
    }
}

#Preview("HomeView, dark") {
    NavigationStack {
        HomeView(onBrowse: {})
    }
    .preferredColorScheme(.dark)
}

#Preview("HomeView, accessibility size") {
    NavigationStack {
        HomeView(onBrowse: {})
    }
    .dynamicTypeSize(.accessibility2)
}
