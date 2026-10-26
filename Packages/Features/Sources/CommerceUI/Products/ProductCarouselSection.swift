import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - ProductRowCardSize

/// The size of the cards of a ``ProductRow`` and its ``ProductRowSkeleton``. Both follow
/// Dynamic Type (wider at large text sizes, capped so two cards stay recognisable on a phone).
public enum ProductRowCardSize: Sendable, Hashable, CaseIterable {
    /// Cards 164 points wide with square photos, for the rows of a page.
    case regular
    /// Cards 184 points wide with portrait photos (3:4), about a fifth taller, for the large
    /// panels of the Start tab.
    case large

    /// The width of a card at the default text size.
    public var baseWidth: CGFloat {
        switch self {
        case .regular: 164
        case .large: 184
        }
    }

    /// The width of a card at the largest text sizes.
    public var maximumWidth: CGFloat {
        switch self {
        case .regular: 300
        case .large: 336
        }
    }

    /// The width of the photo tile divided by its height.
    public var imageAspectRatio: CGFloat {
        switch self {
        case .regular: 1
        case .large: 3.0 / 4.0
        }
    }

    /// The width of a card when text is `textScale` times its default size.
    public func width(textScale: CGFloat) -> CGFloat {
        min(baseWidth * textScale, maximumWidth)
    }
}

// MARK: - ProductRow

/// A horizontal, scrolling row of ``ProductCardView``s in one ``ProductRowCardSize``. Each card
/// is a button that calls `onSelect`. The images of the row are prefetched as soon as it
/// appears.
public struct ProductRow: View {
    private let products: [ProductSummary]
    private let highlight: ProductCardHighlight
    private let cardSize: ProductRowCardSize
    private let onSelect: @MainActor (ProductSummary) -> Void

    /// How much larger than the default text is; the card width grows with it.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    @Environment(\.displayScale) private var displayScale
    @State private var prefetcher = ProductImagePrefetcher()

    /// Creates a product row.
    ///
    /// - Parameters:
    ///   - products: The products, in store order.
    ///   - highlight: The editorial badge for every card (``ProductCardHighlight/bestseller``
    ///     only in the bestseller row).
    ///   - cardSize: The size of the cards (``ProductRowCardSize/regular`` by default).
    ///   - onSelect: Called with the tapped product.
    public init(
        products: [ProductSummary],
        highlight: ProductCardHighlight = .none,
        cardSize: ProductRowCardSize = .regular,
        onSelect: @escaping @MainActor (ProductSummary) -> Void
    ) {
        self.products = products
        self.highlight = highlight
        self.cardSize = cardSize
        self.onSelect = onSelect
    }

    /// The width of one card.
    var cardWidth: CGFloat {
        cardSize.width(textScale: textScale)
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: KXSpacing.xs) {
                ForEach(products) { product in
                    Button {
                        onSelect(product)
                    } label: {
                        ProductCardView(product, highlight: highlight, imageAspectRatio: cardSize.imageAspectRatio)
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

// MARK: - ProductRowSkeleton

/// The placeholder of a ``ProductRow`` while it loads: three ``KXProductCardSkeleton``s of the
/// row's card size, so the row keeps its height when the products arrive. VoiceOver reads it
/// once as "Wird geladen".
public struct ProductRowSkeleton: View {
    /// The number of placeholder cards, enough to fill a phone's width.
    static let cardCount = 3

    private let cardSize: ProductRowCardSize

    /// How much larger than the default text is; the card width grows with it.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    /// Creates the placeholder.
    ///
    /// - Parameter cardSize: The size of the cards it stands in for.
    public init(cardSize: ProductRowCardSize = .regular) {
        self.cardSize = cardSize
    }

    public var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.xs) {
            ForEach(0..<Self.cardCount, id: \.self) { _ in
                KXProductCardSkeleton(imageAspectRatio: cardSize.imageAspectRatio)
                    .frame(width: cardSize.width(textScale: textScale))
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("commerce.loading", bundle: .module))
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
            ProductRowSkeleton()
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
