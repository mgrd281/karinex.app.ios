import DesignSystem
import Foundation
import Observation
import ShopifyKit
import SwiftUI

// MARK: - ArticleViewModel

/// Loads one blog article and parses its HTML once.
@MainActor
@Observable
final class ArticleViewModel {
    /// A loaded article with its parsed content.
    struct LoadedArticle: Sendable, Hashable {
        /// The article from Shopify.
        let article: Article
        /// The parsed `contentHtml`.
        let document: HTMLDocument
    }

    /// The load state.
    private(set) var state: LoadState<LoadedArticle> = .idle

    @ObservationIgnored private let blogHandle: String
    @ObservationIgnored private let articleHandle: String
    @ObservationIgnored private let repository: any ContentRepository

    init(blogHandle: String, articleHandle: String, repository: any ContentRepository) {
        self.blogHandle = blogHandle
        self.articleHandle = articleHandle
        self.repository = repository
    }

    /// Loads the article; keeps shown content while reloading.
    func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            guard let article = try await repository.article(blogHandle: blogHandle, handle: articleHandle) else {
                state = .empty
                return
            }
            let html = article.contentHtml
            let document = await Task.detached(priority: .userInitiated) { HTMLDocument(html: html) }.value
            state = .loaded(LoadedArticle(article: article, document: document))
        } catch {
            if let failure = UserFacingError(error) {
                if state.value == nil {
                    state = .failed(failure)
                }
            }
        }
    }
}

// MARK: - ArticleScreen

/// A blog article (Ratgeber, News): image, serif title, publication date and author, and the
/// content rendered natively by ``RichTextView``. Shares the store link of the article.
///
/// Push it from a ``CommerceRoute/article(blogHandle:articleHandle:)`` route.
public struct ArticleScreen: View {
    @State private var model: ArticleViewModel

    @Environment(\.locale) private var locale

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - blogHandle: The blog, e.g. `guides`.
    ///   - articleHandle: The article handle.
    ///   - repository: The content repository.
    public init(blogHandle: String, articleHandle: String, repository: any ContentRepository) {
        _model = State(initialValue: ArticleViewModel(blogHandle: blogHandle, articleHandle: articleHandle, repository: repository))
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            empty: AsyncContentEmptyState(
                systemImage: "doc.text.magnifyingglass",
                title: String(localized: "commerce.article.empty.title", bundle: .module),
                message: String(localized: "commerce.article.empty.message", bundle: .module)
            ),
            retry: { await model.load() },
            content: { loaded in
                ScrollView {
                    articleContent(loaded)
                }
                .refreshable { await model.load() }
            },
            placeholder: {
                AsyncContentSkeleton()
            }
        )
        .kxScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = model.state.value?.article.onlineStoreUrl {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Label {
                            Text("commerce.article.share", bundle: .module)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .accessibilityIdentifier("article.share")
                }
            }
        }
        .accessibilityIdentifier("screen.article")
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
    }

    private func articleContent(_ loaded: ArticleViewModel.LoadedArticle) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            if let image = loaded.article.image {
                ProductImage(image, contentMode: .fill)
                    .aspectRatio(image.aspectRatio.map { CGFloat($0) } ?? 16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
            }
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                Text(loaded.article.title)
                    .kxFont(.title1)
                    .foregroundStyle(KXColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(byline(for: loaded.article))
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            KXDivider(.accent)
            RichTextView(document: loaded.document)
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.vertical, KXSpacing.m)
    }

    private func byline(for article: Article) -> String {
        let date = article.publishedAt.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))
        guard let author = article.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty else {
            return date
        }
        return String(localized: "commerce.article.byline \(date) \(author)", bundle: .module)
    }
}

// MARK: - Previews

/// Serves one sample article to the previews.
private struct PreviewContentRepository: ContentRepository {
    func articles(blogHandle: String, first: Int) async throws -> [ArticleSummary] {
        []
    }

    func article(blogHandle: String, handle: String) async throws -> Article? {
        Article(
            id: ShopifyID("gid://shopify/Article/1"),
            handle: handle,
            blogHandle: blogHandle,
            title: "Office 2024 installieren",
            publishedAt: Date(timeIntervalSince1970: 1_790_000_000),
            authorName: "KARINEX",
            image: nil,
            contentHtml: "<p>Laden Sie das Installationsprogramm herunter.</p>",
            onlineStoreUrl: URL(string: "https://www.karinex.de/blogs/guides")
        )
    }
}

#Preview("ArticleScreen") {
    NavigationStack {
        ArticleScreen(blogHandle: "guides", articleHandle: "office-2024-installieren", repository: PreviewContentRepository())
    }
}
