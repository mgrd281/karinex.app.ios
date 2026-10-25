import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - HomeStoryItem

/// A story of the carousel with the load state of its collection.
struct HomeStoryItem: Identifiable, Hashable {
    /// The story.
    let story: HomeStory
    /// The products of the story's collection.
    let state: LoadState<[ProductSummary]>

    /// The collection handle.
    var id: String {
        story.id
    }

    /// The photo of the story: the image of the collection's first product.
    var photo: ShopifyImage? {
        state.value?.first?.featuredImage
    }
}

// MARK: - HomeStoryCarousel

/// The story carousel at the top of the Start screen, in the style of the campaign cards of
/// fashion retail apps: one large rounded panel in which the stories page sideways, the
/// neighbours peeking in at the edges, with the page dots fixed at the bottom.
///
/// The panel takes the color of the photo of the story in view (``ProductImageTint``), dark
/// enough for light text, or the neutral dark panel when the photo has no clear color. While a
/// collection loads, its story is a skeleton; an empty or failed collection drops out. When
/// every collection failed, one compact error with "Erneut versuchen" replaces the carousel.
struct HomeStoryCarousel: View {
    let items: [HomeStoryItem]
    let retry: @MainActor () async -> Void
    let onOpen: @MainActor (HomeCategory) -> Void
    let onSelect: @MainActor (ProductSummary) -> Void

    /// The story in view, `nil` until the customer pages (the first one).
    @State private var currentID: String?
    /// The panel colors by photo URL, filled as the photos are sampled.
    @State private var tints: [URL: ProductPanelTint] = [:]

    /// The stories that are loading or have products.
    private var visible: [HomeStoryItem] {
        items.filter { item in
            switch item.state {
            case .idle, .loading, .loaded: true
            case .empty, .failed: false
            }
        }
    }

    var body: some View {
        let stories = visible
        if stories.isEmpty, let error = items.compactMap(\.state.error).first {
            KXBanner(
                .error,
                message: error.message,
                action: error.isRetryable ? { Task { await retry() } } : nil
            )
            .padding(.horizontal, KXSpacing.gutter)
        } else if !stories.isEmpty {
            panel(stories)
        }
    }

    private func panel(_ stories: [HomeStoryItem]) -> some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.large, style: .continuous)
        let index = stories.firstIndex { $0.id == currentID } ?? 0
        let tint = stories[index].photo.flatMap { tints[$0.url] }
        return VStack(spacing: KXSpacing.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: KXSpacing.s) {
                    ForEach(stories) { item in
                        HomeStoryPage(item: item, onOpen: onOpen, onSelect: onSelect)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, KXSpacing.m, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentID)
            // The tag of a story sits on the top edge of its photo; the panel clips instead.
            .scrollClipDisabled()
            HomePageDots(index: index, count: stories.count)
        }
        .padding(.top, KXSpacing.l)
        .padding(.bottom, KXSpacing.m)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [tint?.top ?? KXColor.surfaceElevated, tint?.bottom ?? KXColor.surface],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
        .kxAnimation(.fade, value: tint)
        .padding(.horizontal, KXSpacing.gutter)
        // On a wide iPad window the panel keeps the proportions of a phone card.
        .kxReadableWidth()
        .task(id: stories.map(\.photo?.url)) {
            await loadTints(of: stories)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.stories")
    }

    /// Samples the photos of `stories` in order, so the first panel color arrives first.
    private func loadTints(of stories: [HomeStoryItem]) async {
        for photo in stories.compactMap(\.photo) where tints[photo.url] == nil {
            if let tint = await ProductImageTint.shared.panel(for: photo) {
                tints[photo.url] = tint
            }
        }
    }
}

// MARK: - HomeStoryPage

/// One page of the story carousel: the story's tag on the photo of the collection's first
/// product, the next four products as small tiles overlapping the photo, and "Kategorie
/// entdecken" with the short category name.
///
/// The photo and the caption open the collection; each small tile opens its product.
struct HomeStoryPage: View {
    let item: HomeStoryItem
    let onOpen: @MainActor (HomeCategory) -> Void
    let onSelect: @MainActor (ProductSummary) -> Void

    /// The number of small product tiles below the photo.
    private static let thumbnailCount = 4

    private var products: [ProductSummary] {
        item.state.value ?? []
    }

    private var category: HomeCategory {
        item.story.category
    }

    var body: some View {
        VStack(spacing: KXSpacing.m) {
            photo
            thumbnails
            caption
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.story.\(item.id)")
    }

    // MARK: Parts

    private var photo: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
        return Button {
            onOpen(category)
        } label: {
            ZStack {
                if let first = products.first {
                    ProductImage(first.featuredImage, isDecorative: true)
                        .padding(KXSpacing.xl)
                        .kxPhotoTile()
                } else {
                    KXSkeleton(cornerRadius: KXRadius.medium)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(shape)
            .overlay(alignment: .top) {
                tag
                    .alignmentGuide(.top) { dimensions in dimensions[VerticalAlignment.center] }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(category.title.resolved))
        .accessibilityHint(Text("home.story.hint", bundle: .module))
        .accessibilityIdentifier("home.story.open.\(item.id)")
    }

    /// The small white tag centered on the top edge of the photo.
    private var tag: some View {
        Text(item.story.tag.resolved)
            .kxFont(.eyebrow)
            .foregroundStyle(KXColor.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, KXSpacing.s)
            .padding(.vertical, KXSpacing.xxs)
            .background(KXColor.background, in: Capsule(style: .continuous))
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }

    /// Four small product tiles overlapping the lower edge of the photo.
    private var thumbnails: some View {
        HStack(spacing: KXSpacing.xs) {
            ForEach(1...Self.thumbnailCount, id: \.self) { position in
                thumbnail(at: position)
            }
        }
        .padding(.horizontal, KXSpacing.s)
        .padding(.top, -(KXSpacing.m + KXSpacing.l))
    }

    @ViewBuilder
    private func thumbnail(at position: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
        if position < products.count {
            let product = products[position]
            Button {
                onSelect(product)
            } label: {
                ProductImage(product.featuredImage, isDecorative: true)
                    .padding(KXSpacing.xxs)
                    .kxPhotoTile()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(shape)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(product.title))
            .accessibilityIdentifier("product.card.\(product.handle)")
        } else {
            Group {
                if item.state.isLoading {
                    KXSkeleton(cornerRadius: KXRadius.small)
                } else {
                    Color.clear
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
        }
    }

    /// "Kategorie entdecken" and the short name; opens the collection like the photo.
    private var caption: some View {
        VStack(spacing: KXSpacing.xxs) {
            Text("home.story.action", bundle: .module)
                .kxFont(.eyebrow)
                .foregroundStyle(KXColor.textSecondary)
            Text(category.title.resolved)
                .kxFont(.title2)
                .foregroundStyle(KXColor.textPrimary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen(category)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - HomePageDots

/// The page dots of the story carousel: the story in view as a short bar, the others as dots.
/// Decorative; VoiceOver users move through the stories directly.
struct HomePageDots: View {
    let index: Int
    let count: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: KXSpacing.xxs) {
                ForEach(0..<count, id: \.self) { position in
                    Capsule(style: .continuous)
                        .fill(position == index ? KXColor.textPrimary : KXColor.textTertiary)
                        .frame(width: position == index ? KXSpacing.m : KXSpacing.xxs, height: KXSpacing.xxs)
                }
            }
            .kxAnimation(.standard, value: index)
            .accessibilityHidden(true)
        }
    }
}
