import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - HomeView

/// The Start tab, laid out like a fashion retail app (PROMPT.md section 6.1):
///
/// - On top the KARINEX logo with the Merkliste heart, which scroll away, and the search field,
///   which stays pinned and opens the Suche tab.
/// - Below: the story carousel of featured collections in the store color,
///   the trust facts (the money-back promise opens its conditions), the category showcase with
///   its dark product panel, which moves on from category to category by itself, the
///   bestsellers, the dark sale panel, "Zuletzt angesehen", the version grid, the service
///   tiles, the Ratgeber stories and the support card.
///
/// Every collection loads concurrently with its own skeleton and error state; pull to refresh
/// reloads them all. Product facts come only from the Storefront API.
///
/// Place it inside a `NavigationStack`. The navigation bar is hidden; a solid backdrop behind the
/// status bar keeps scrolled content legible.
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
    private let modules: HomeModules
    private let cyclesShowcase: Bool
    private let onRoute: @MainActor (CommerceRoute) -> Void
    private let onBrowse: @MainActor () -> Void

    @State private var model: HomeViewModel
    @State private var isMoneyBackConditionPresented = false
    /// The height of the logo bar: how far the page scrolls before the search field pins.
    @State private var brandBarHeight = CGFloat.infinity
    @State private var isSearchPinned = false

    /// The coordinate space of the page content.
    private static let contentSpace = "home.content"

    /// Creates the Start screen.
    ///
    /// - Parameters:
    ///   - catalog: Loads the collections.
    ///   - content: Loads the guide articles.
    ///   - modules: The modules and the store collections behind them.
    ///   - cyclesShowcase: Whether the category showcase moves on to the next category by
    ///     itself (`true` by default; UI tests turn it off for a still screen).
    ///   - onRoute: Called with the destination of a tap: a product, a collection, an article,
    ///     the search or a screen of the account area.
    ///   - onBrowse: Called when the user asks to see the whole range ("Alle Kategorien"),
    ///     typically by switching to the Shop tab.
    public init(
        catalog: any CatalogRepository,
        content: any ContentRepository,
        modules: HomeModules = .standard,
        cyclesShowcase: Bool = true,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void,
        onBrowse: @escaping @MainActor () -> Void
    ) {
        _model = State(initialValue: HomeViewModel(catalog: catalog, content: content, layout: modules.layout))
        self.modules = modules
        self.cyclesShowcase = cyclesShowcase
        self.onRoute = onRoute
        self.onBrowse = onBrowse
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                HomeBrandBar {
                    onRoute(.account(.wishlist))
                }
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    brandBarHeight = height
                }
                Section {
                    // One plain stack, so every module exists as soon as the page loads.
                    forYou
                        .padding(.top, KXSpacing.s)
                        .padding(.bottom, KXSpacing.xl)
                } header: {
                    searchField
                }
            }
            .coordinateSpace(.named(Self.contentSpace))
        }
        .refreshable {
            await model.reload()
        }
        .accessibilityIdentifier("screen.home")
        .task {
            await model.loadIfNeeded()
        }
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

    // MARK: Header

    /// The search field, pinned below the status bar once the logo bar has scrolled away.
    private var searchField: some View {
        let space = Self.contentSpace
        let threshold = brandBarHeight
        return HomeSearchField(isPinned: isSearchPinned) {
            onRoute(.search(query: ""))
        }
        .onGeometryChange(for: Bool.self) { geometry in
            // A pinned header moves down the content while the page scrolls under it.
            geometry.frame(in: .named(space)).minY > threshold + 0.5
        } action: { isPinned in
            isSearchPinned = isPinned
        }
    }

    // MARK: Content

    /// The modules, top to bottom.
    private var forYou: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxl) {
            HomeStoryCarousel(
                items: modules.stories.map { HomeStoryItem(story: $0, state: model.productState(for: $0.id)) },
                retry: { await model.reload(handles: modules.stories.map(\.id)) },
                onOpen: openCategory,
                onSelect: openProduct
            )
            HomeTrustSection(isConditionPresented: $isMoneyBackConditionPresented)
                .padding(.horizontal, KXSpacing.gutter)
            HomeCategoryShowcase(
                categories: modules.showcase,
                cyclesAutomatically: cyclesShowcase,
                state: { model.productState(for: $0.handle) },
                retry: { await model.reload(handles: [$0.handle]) },
                onOpen: openCategory,
                onBrowseAll: onBrowse,
                onSelect: openProduct
            )
            bestsellers
            deals
            RecentlyViewedSection(onSelect: openProduct)
            HomeVersionGrid(
                versions: modules.versions,
                state: { model.productState(for: $0.handle) },
                onOpen: openCategory
            )
            HomeServiceTiles(onRoute: onRoute)
            guides
            HomeSupportSection()
                .padding(.horizontal, KXSpacing.gutter)
        }
    }

    /// The bestsellers as a row of cards with prices.
    private var bestsellers: some View {
        let category = modules.bestsellers
        return ProductCarouselSection(
            title: category.title.resolved,
            eyebrow: category.eyebrow?.resolved,
            state: model.productState(for: category.handle),
            highlight: category.handle == HomeModules.bestsellerHandle ? .bestseller : .none,
            onShowAll: { openCategory(category) },
            retry: { await model.reload(handles: [category.handle]) },
            onSelect: openProduct
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.row.\(category.handle)")
    }

    /// The dark sale panel.
    private var deals: some View {
        let category = modules.deals
        return HomeProductPanel(
            eyebrow: category.eyebrow?.resolved,
            title: category.title.resolved,
            isSale: true,
            state: model.productState(for: category.handle),
            retry: { await model.reload(handles: [category.handle]) },
            onShowAll: { openCategory(category) },
            onSelect: openProduct
        )
        .padding(.horizontal, KXSpacing.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.panel.\(category.handle)")
    }

    /// The Ratgeber stories.
    @ViewBuilder private var guides: some View {
        if let section = model.layout.section(modules.guidesBlog) {
            HomeArticleSection(
                title: section.title.resolved,
                eyebrow: section.eyebrow?.resolved,
                state: model.articleState(for: section),
                retry: { await model.reload(section) },
                onSelect: openArticle
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(section.accessibilityIdentifier)
        }
    }

    // MARK: Routes

    private func openProduct(_ product: ProductSummary) {
        onRoute(.product(handle: product.handle))
    }

    private func openCategory(_ category: HomeCategory) {
        onRoute(.collection(handle: category.handle, title: category.title.resolved))
    }

    private func openArticle(_ article: ArticleSummary) {
        let blog = article.blogHandle.isEmpty ? modules.guidesBlog : article.blogHandle
        onRoute(.article(blogHandle: blog, articleHandle: article.handle))
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
