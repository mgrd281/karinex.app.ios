import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - HomeArticleSection

/// The Ratgeber module of the Start screen: a section header and a row of tall guide tiles from
/// the store's blog, a little more than two in view, like the inspiration stories of fashion
/// retail apps.
///
/// Like ``ProductCarouselSection`` it renders its own skeleton while loading, a compact error
/// with "Erneut versuchen" when the request failed, and nothing at all when the blog is empty.
struct HomeArticleSection: View {
    let title: String
    let eyebrow: String?
    let state: LoadState<[ArticleSummary]>
    let retry: @MainActor () async -> Void
    let onSelect: @MainActor (ArticleSummary) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The share of the row's width one tile takes: a little less than half, so the third tile
    /// peeks in; most of the width at the largest text sizes.
    private var tileShare: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 0.8 : 0.44
    }

    var body: some View {
        if case .empty = state {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                KXSectionHeader(title, eyebrow: eyebrow)
                    .padding(.horizontal, KXSpacing.gutter)
                rowContent
            }
        }
    }

    @ViewBuilder private var rowContent: some View {
        let share = tileShare
        switch state {
        case .idle, .loading:
            scrollingRow {
                ForEach(0..<3, id: \.self) { _ in
                    skeletonTile
                        .containerRelativeFrame(.horizontal) { length, _ in length * share }
                }
            }
            .scrollDisabled(true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("home.loading", bundle: .module))
        case let .loaded(articles):
            scrollingRow {
                ForEach(articles) { article in
                    Button {
                        onSelect(article)
                    } label: {
                        HomeArticleCard(article: article)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal) { length, _ in length * share }
                    .accessibilityHint(Text("home.article.hint", bundle: .module))
                    .accessibilityIdentifier("article.card.\(article.handle)")
                }
            }
        case let .failed(error):
            KXBanner(
                .error,
                message: error.message,
                action: error.isRetryable ? { Task { await retry() } } : nil
            )
            .padding(.horizontal, KXSpacing.gutter)
        case .empty:
            EmptyView()
        }
    }

    /// A horizontal row of tiles that snaps to the tiles, aligned with the page margins.
    private func scrollingRow(@ViewBuilder tiles: () -> some View) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: KXSpacing.s) {
                tiles()
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, KXSpacing.gutter, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }

    private var skeletonTile: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            KXSkeleton(cornerRadius: KXRadius.medium)
                .aspectRatio(HomeArticleCard.imageAspectRatio, contentMode: .fit)
            KXSkeleton()
                .frame(height: KXSpacing.m)
            KXSkeleton()
                .frame(height: KXSpacing.m)
                .padding(.trailing, KXSpacing.xl)
        }
    }
}

// MARK: - HomeArticleCard

/// One guide tile: the article image in a tall rounded frame (a book symbol on the light grey
/// panel when the article has none), the publication date as small label, the bold title and
/// the start of the excerpt. VoiceOver reads it as one element.
struct HomeArticleCard: View {
    let article: ArticleSummary

    /// Width to height of the image: a portrait frame, like a story.
    static let imageAspectRatio: CGFloat = 3 / 4

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            Color.clear
                .aspectRatio(Self.imageAspectRatio, contentMode: .fit)
                .overlay {
                    if article.image != nil {
                        ProductImage(article.image, contentMode: .fill, isDecorative: true)
                    } else {
                        Image(systemName: "book.pages")
                            .kxFont(.title1)
                            .foregroundStyle(KXColor.iconSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .background(KXColor.surfaceElevated)
                .clipShape(shape)
                .contentShape(shape)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(article.publishedAt, format: .dateTime.day().month(.wide).year())
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.textSecondary)
                Text(article.title)
                    .fontWeight(.semibold)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let excerpt = article.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !excerpt.isEmpty {
                    Text(excerpt)
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
