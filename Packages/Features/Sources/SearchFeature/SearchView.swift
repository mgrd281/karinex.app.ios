import DesignSystem
import SwiftUI

// MARK: - SearchView

/// The Suche tab.
///
/// In Phase 0 the screen explains what the search will offer. It deliberately has no search
/// field yet: a field that returns nothing would pretend a feature that does not exist.
/// Predictive search for products, collections and articles, recent searches and suggestions
/// arrive in Phase 1.
///
/// Place it inside a `NavigationStack`; it uses a large title.
public struct SearchView: View {
    /// Creates the search screen.
    public init() {}

    public var body: some View {
        ScrollView {
            KXEmptyState(
                systemImage: "magnifyingglass",
                title: String(localized: "search.empty.title", bundle: .module),
                message: String(localized: "search.empty.message", bundle: .module)
            )
            .accessibilityIdentifier("search.empty")
            .padding(.top, KXSpacing.xl)
        }
        .accessibilityIdentifier("screen.search")
        .kxScreenBackground()
        .navigationTitle(Text("search.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Previews

#Preview("SearchView, light") {
    NavigationStack {
        SearchView()
    }
}

#Preview("SearchView, dark") {
    NavigationStack {
        SearchView()
    }
    .preferredColorScheme(.dark)
}

#Preview("SearchView, accessibility size") {
    NavigationStack {
        SearchView()
    }
    .dynamicTypeSize(.accessibility2)
}
