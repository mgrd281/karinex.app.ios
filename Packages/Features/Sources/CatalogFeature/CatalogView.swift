import DesignSystem
import SwiftUI

// MARK: - CatalogView

/// The Shop tab.
///
/// In Phase 0 the screen explains where the range will appear; it shows no products, because
/// every product fact must come from the Storefront API (PROMPT.md section 3). The collections
/// grid, product lists with sorting and filters, and pagination arrive in Phase 1.
///
/// Place it inside a `NavigationStack`; it uses a large title.
public struct CatalogView: View {
    /// Creates the Shop screen.
    public init() {}

    public var body: some View {
        ScrollView {
            KXEmptyState(
                systemImage: "square.grid.2x2",
                title: String(localized: "catalog.empty.title", bundle: .module),
                message: String(localized: "catalog.empty.message", bundle: .module)
            )
            .accessibilityIdentifier("catalog.empty")
            .padding(.top, KXSpacing.xl)
        }
        .accessibilityIdentifier("screen.catalog")
        .kxScreenBackground()
        .navigationTitle(Text("catalog.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Previews

#Preview("CatalogView, light") {
    NavigationStack {
        CatalogView()
    }
}

#Preview("CatalogView, dark") {
    NavigationStack {
        CatalogView()
    }
    .preferredColorScheme(.dark)
}

#Preview("CatalogView, accessibility size") {
    NavigationStack {
        CatalogView()
    }
    .dynamicTypeSize(.accessibility2)
}
