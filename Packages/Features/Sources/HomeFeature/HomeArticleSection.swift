import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - HomeArticleSection

/// The Ratgeber module of the Start screen: a section header and a horizontal row of guide
/// articles from the store's blog.
///
/// Like ``ProductCarouselSection`` it renders its own skeleton while loading, a compact error
/// with "Erneut versuchen" when the request failed, and nothing at all when the blog is empty.
struct HomeArticleSection: View {
    let title: String
    let eyebrow: String?
    let state: LoadState<[ArticleSummary]>
    let retry: @MainActor () async -> Void
    let onSelect: @MainActor (ArticleSummary) -> Void

    @ScaledMetric(relativeTo: .body) private var scaledCardWidth: CGFloat = 260

    private var cardWidth: CGFloat {
        min(scaledCardWidth, 340)
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
        switch state {
        case .idle, .loading:
            skeletonRow
        case let .loaded(articles):
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: KXSpacing.m) {
                    ForEach(articles) { article in
                        Button {
                            onSelect(article)
                        } label: {
                            HomeArticleCard(article: article)
                                .frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("home.article.hint", bundle: .module))
                        .accessibilityIdentifier("article.card.\(article.handle)")
                    }
                }
                .padding(.horizontal, KXSpacing.gutter)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
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

    private var skeletonRow: some View {
        HStack(alignment: .top, spacing: KXSpacing.m) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXSkeleton(cornerRadius: KXRadius.card)
                        .aspectRatio(16 / 10, contentMode: .fit)
                    KXSkeleton()
                        .frame(height: KXSpacing.m)
                    KXSkeleton()
                        .frame(width: cardWidth * 0.6, height: KXSpacing.m)
                }
                .frame(width: cardWidth)
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("home.loading", bundle: .module))
    }
}

// MARK: - HomeArticleCard

/// One guide article: the article image on a cream panel, the publication date as eyebrow, the
/// serif title and the excerpt. VoiceOver reads it as one element.
struct HomeArticleCard: View {
    let article: ArticleSummary

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                KXColor.surfaceElevated
                if article.image != nil {
                    ProductImage(article.image, contentMode: .fill, isDecorative: true)
                } else {
                    Image(systemName: "book.pages")
                        .kxFont(.title1)
                        .foregroundStyle(KXColor.accent)
                        .accessibilityHidden(true)
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .clipped()
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text(article.publishedAt, format: .dateTime.day().month(.wide).year())
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.accentText)
                Text(article.title)
                    .kxFont(.title3)
                    .foregroundStyle(KXColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let excerpt = article.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !excerpt.isEmpty {
                    Text(excerpt)
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(KXSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(KXColor.surface)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(KXColor.hairline, lineWidth: 1 / max(displayScale, 1))
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}
