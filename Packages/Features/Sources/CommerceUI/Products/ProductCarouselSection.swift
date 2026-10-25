import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductRow

/// A horizontal, scrolling row of ``ProductCardView``s. Each card is a button that calls
/// `onSelect`. The images of the row are prefetched as soon as it appears.
///
/// Card width follows Dynamic Type (wider at large text sizes, capped so two cards stay
/// recognisable on a phone).
public struct ProductRow: View {
    private let products: [ProductSummary]
    private let highlight: ProductCardHighlight
    private let onSelect: @MainActor (ProductSummary) -> Void

    @ScaledMetric(relativeTo: .body) private var scaledCardWidth: CGFloat = 164
    @Environment(\.displayScale) private var displayScale
    @State private var prefetcher = ProductImagePrefetcher()

    /// Creates a product row.
    ///
    /// - Parameters:
    ///   - products: The products, in store order.
    ///   - highlight: The editorial badge for every card (``ProductCardHighlight/bestseller``
    ///     only in the bestseller row).
    ///   - onSelect: Called with the tapped product.
    public init(
        products: [ProductSummary],
        highlight: ProductCardHighlight = .none,
        onSelect: @escaping @MainActor (ProductSummary) -> Void
    ) {
        self.products = products
        self.highlight = highlight
        self.onSelect = onSelect
    }

    /// The width of one card.
    var cardWidth: CGFloat {
        min(scaledCardWidth, 300)
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: KXSpacing.xs) {
                ForEach(products) { product in
                    Button {
                        onSelect(product)
                    } label: {
                        ProductCardView(product, highlight: highlight)
                            .frame(width: cardWidth)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("product.card.\(product.handle)")
                }
            }
            .padding(.horizontal, KXSpacing.gutter)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .task(id: products.map(\.id)) {
            prefetcher.prefetch(products.map(\.featuredImage), pointWidth: cardWidth, scale: displayScale)
        }
    }
}

// MARK: - ProductCarouselSection

/// A titled product row for Home, Catalog, the cart cross-sell and the product comparison:
/// a ``KXSectionHeader`` with an optional "Alle anzeigen" action above a ``ProductRow``.
///
/// The state-based initializer renders its own skeleton while loading, a compact error with
/// "Erneut versuchen" when the row failed, and nothing at all when the row is empty, so one
/// failing row never blocks a screen.
public struct ProductCarouselSection: View {
    private let title: String
    private let eyebrow: String?
    private let state: LoadState<[ProductSummary]>
    private let highlight: ProductCardHighlight
    private let showAllTitle: String?
    private let onShowAll: (@MainActor () -> Void)?
    private let retry: (@MainActor () async -> Void)?
    private let onSelect: @MainActor (ProductSummary) -> Void

    @ScaledMetric(relativeTo: .body) private var skeletonCardWidth: CGFloat = 164

    /// Creates a section for a row that loads.
    ///
    /// - Parameters:
    ///   - title: The localized section title.
    ///   - eyebrow: An optional localized eyebrow above the title.
    ///   - state: The row's load state.
    ///   - highlight: The editorial badge for every card.
    ///   - showAllTitle: The label of the header action; `nil` uses "Alle anzeigen".
    ///   - onShowAll: The header action, e.g. opening the collection. No action, no button.
    ///   - retry: Reloads the row after a failure.
    ///   - onSelect: Called with the tapped product.
    public init(
        title: String,
        eyebrow: String? = nil,
        state: LoadState<[ProductSummary]>,
        highlight: ProductCardHighlight = .none,
        showAllTitle: String? = nil,
        onShowAll: (@MainActor () -> Void)? = nil,
        retry: (@MainActor () async -> Void)? = nil,
        onSelect: @escaping @MainActor (ProductSummary) -> Void
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.state = state
        self.highlight = highlight
        self.showAllTitle = showAllTitle
        self.onShowAll = onShowAll
        self.retry = retry
        self.onSelect = onSelect
    }

    /// Creates a section for products that are already loaded.
    ///
    /// - Parameters:
    ///   - title: The localized section title.
    ///   - eyebrow: An optional localized eyebrow above the title.
    ///   - products: The products; an empty list hides the section.
    ///   - highlight: The editorial badge for every card.
    ///   - showAllTitle: The label of the header action; `nil` uses "Alle anzeigen".
    ///   - onShowAll: The header action. No action, no button.
    ///   - onSelect: Called with the tapped product.
    public init(
        title: String,
        eyebrow: String? = nil,
        products: [ProductSummary],
        highlight: ProductCardHighlight = .none,
        showAllTitle: String? = nil,
        onShowAll: (@MainActor () -> Void)? = nil,
        onSelect: @escaping @MainActor (ProductSummary) -> Void
    ) {
        self.init(
            title: title,
            eyebrow: eyebrow,
            state: LoadState(collection: products),
            highlight: highlight,
            showAllTitle: showAllTitle,
            onShowAll: onShowAll,
            onSelect: onSelect
        )
    }

    public var body: some View {
        switch state {
        case .empty:
            EmptyView()
        default:
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                KXSectionHeader(
                    title,
                    eyebrow: eyebrow,
                    actionTitle: showAllTitle,
                    action: state.value == nil ? nil : onShowAll.map { action in { action() } }
                )
                .padding(.horizontal, KXSpacing.gutter)
                rowContent
            }
        }
    }

    @ViewBuilder private var rowContent: some View {
        switch state {
        case .idle, .loading:
            skeletonRow
        case let .loaded(products):
            ProductRow(products: products, highlight: highlight, onSelect: onSelect)
        case let .failed(error):
            KXBanner(
                .error,
                message: error.message,
                actionTitle: UserFacingError.retryTitle,
                action: error.isRetryable ? retryAction : nil
            )
            .padding(.horizontal, KXSpacing.gutter)
        case .empty:
            EmptyView()
        }
    }

    /// Starts `retry` in a task, or `nil` without a retry action.
    private var retryAction: (() -> Void)? {
        guard let retry else { return nil }
        return {
            Task { @MainActor in
                await retry()
            }
        }
    }

    private var skeletonRow: some View {
        let width = min(skeletonCardWidth, 300)
        return HStack(alignment: .top, spacing: KXSpacing.xs) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXSkeleton(cornerRadius: KXRadius.image)
                        .aspectRatio(1, contentMode: .fit)
                    KXSkeleton()
                        .frame(height: KXSpacing.m)
                    KXSkeleton()
                        .frame(width: width / 2, height: KXSpacing.m)
                }
                .frame(width: width)
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("commerce.loading", bundle: .module))
    }
}

// MARK: - Previews

#Preview("ProductCarouselSection") {
    ScrollView {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            ProductCarouselSection(
                title: "Bestseller",
                products: CommercePreviewData.products,
                highlight: .bestseller,
                onShowAll: {},
                onSelect: { _ in }
            )
            ProductCarouselSection(title: "Windows", state: .loading, onSelect: { _ in })
            ProductCarouselSection(
                title: "Office",
                state: .failed(UserFacingError(kind: .server)),
                retry: {},
                onSelect: { _ in }
            )
        }
        .padding(.vertical, KXSpacing.m)
    }
    .kxScreenBackground()
}

#Preview("ProductCarouselSection, dark, accessibility size") {
    ScrollView {
        ProductCarouselSection(title: "Angebote", products: CommercePreviewData.products, onSelect: { _ in })
    }
    .kxScreenBackground()
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}
