import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - HomeView

/// The Start tab: the editorial hero with the call to action into the range, the trust strip
/// with the four brand facts (the money-back promise opens its conditions), the live modules of
/// a ``HomeLayout`` (deals, category rows, bestsellers, guides) and the support card.
///
/// Every live row loads concurrently with its own skeleton and error state; pull to refresh
/// reloads them all. Product facts come only from the Storefront API.
///
/// Place it inside a `NavigationStack`. The navigation bar is hidden because the hero carries
/// the wordmark; a solid backdrop behind the status bar keeps scrolled content legible.
///
/// ```swift
/// NavigationStack(path: $path) {
///     HomeView(
///         catalog: container.catalogRepository,
///         content: container.contentRepository,
///         onRoute: { path.append($0) },
///         onBrowse: { selectedTab = .shop }
///     )
/// }
/// ```
public struct HomeView: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void
    private let onBrowse: @MainActor () -> Void

    @State private var model: HomeViewModel
    @State private var isMoneyBackConditionPresented = false

    /// Creates the Start screen.
    ///
    /// - Parameters:
    ///   - catalog: Loads the collection rows.
    ///   - content: Loads the guide articles.
    ///   - layout: The live modules between the trust strip and the support card.
    ///   - onRoute: Called with the destination of a tap: a product, a collection ("Alle
    ///     anzeigen") or an article.
    ///   - onBrowse: Called when the user asks to see the range ("Zum Sortiment"), typically by
    ///     switching to the Shop tab.
    public init(
        catalog: any CatalogRepository,
        content: any ContentRepository,
        layout: HomeLayout = .standard,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void,
        onBrowse: @escaping @MainActor () -> Void
    ) {
        _model = State(initialValue: HomeViewModel(catalog: catalog, content: content, layout: layout))
        self.onRoute = onRoute
        self.onBrowse = onBrowse
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xxl) {
                VStack(alignment: .leading, spacing: KXSpacing.xxl) {
                    HomeHero(onBrowse: onBrowse)
                    HomeTrustSection(isConditionPresented: $isMoneyBackConditionPresented)
                }
                .padding(.horizontal, KXSpacing.gutter)
                ForEach(model.layout.sections) { section in
                    sectionView(section)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(section.accessibilityIdentifier)
                }
                HomeSupportSection()
                    .padding(.horizontal, KXSpacing.gutter)
            }
            .padding(.top, KXSpacing.s)
            .padding(.bottom, KXSpacing.xl)
        }
        .refreshable {
            await model.reload()
        }
        .task {
            await model.loadIfNeeded()
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

    // MARK: Sections

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        let title = section.title.resolved
        switch section.content {
        case let .collection(handle, _, highlight):
            ProductCarouselSection(
                title: title,
                eyebrow: section.eyebrow?.resolved,
                state: model.productState(for: section),
                highlight: highlight,
                onShowAll: { onRoute(.collection(handle: handle, title: title)) },
                retry: { await model.reload(section) },
                onSelect: { product in onRoute(.product(handle: product.handle)) }
            )
        case let .blog(handle, _):
            HomeArticleSection(
                title: title,
                eyebrow: section.eyebrow?.resolved,
                state: model.articleState(for: section),
                retry: { await model.reload(section) },
                onSelect: { article in
                    onRoute(.article(blogHandle: article.blogHandle.isEmpty ? handle : article.blogHandle, articleHandle: article.handle))
                }
            )
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

#if DEBUG
#Preview("HomeView, light") {
    NavigationStack {
        HomeView(
            catalog: HomePreviewRepository(),
            content: HomePreviewRepository(),
            onRoute: { _ in },
            onBrowse: {}
        )
    }
}

#Preview("HomeView, dark") {
    NavigationStack {
        HomeView(
            catalog: HomePreviewRepository(),
            content: HomePreviewRepository(),
            onRoute: { _ in },
            onBrowse: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("HomeView, failing rows, accessibility size") {
    NavigationStack {
        HomeView(
            catalog: HomePreviewRepository(fails: true),
            content: HomePreviewRepository(fails: true),
            onRoute: { _ in },
            onBrowse: {}
        )
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
