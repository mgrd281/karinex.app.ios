import CommerceUI
import Foundation
import Observation
import ShopifyKit

// MARK: - HomeViewModel

/// Loads the live modules of the Start screen described by a ``HomeLayout``.
///
/// Every row loads concurrently and independently: each has its own ``LoadState``, so a slow or
/// failing row shows its own skeleton or error while the others are already visible. A reload
/// (pull to refresh) keeps the content that is on screen when a row fails again.
@MainActor
@Observable
final class HomeViewModel {
    /// The layout the screen renders.
    let layout: HomeLayout

    /// The state of every collection row, keyed by ``HomeSection/id``.
    private(set) var productRows: [String: LoadState<[ProductSummary]>] = [:]
    /// The state of every blog row, keyed by ``HomeSection/id``.
    private(set) var articleRows: [String: LoadState<[ArticleSummary]>] = [:]

    @ObservationIgnored private let catalog: any CatalogRepository
    @ObservationIgnored private let content: any ContentRepository
    @ObservationIgnored private var hasLoaded = false

    /// Creates the model; nothing is requested before ``loadIfNeeded()``.
    init(catalog: any CatalogRepository, content: any ContentRepository, layout: HomeLayout) {
        self.catalog = catalog
        self.content = content
        self.layout = layout
    }

    // MARK: State access

    /// The state of the collection row `section`, `.idle` before the first load.
    func productState(for section: HomeSection) -> LoadState<[ProductSummary]> {
        productRows[section.id] ?? .idle
    }

    /// The state of the blog row `section`, `.idle` before the first load.
    func articleState(for section: HomeSection) -> LoadState<[ArticleSummary]> {
        articleRows[section.id] ?? .idle
    }

    // MARK: Loading

    /// Loads every row once; later calls do nothing (use ``reload()``).
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    /// Loads every row concurrently and applies each result as soon as it arrives.
    func reload() async {
        hasLoaded = true
        for section in layout.sections {
            markLoading(section)
        }
        let catalog = catalog
        let content = content
        await withTaskGroup(of: (String, RowOutcome).self) { group in
            for section in layout.sections {
                group.addTask {
                    await (section.id, Self.fetch(section, catalog: catalog, content: content))
                }
            }
            for await (id, outcome) in group {
                apply(outcome, to: id)
            }
        }
    }

    /// Reloads the single row `section`, e.g. after "Erneut versuchen".
    func reload(_ section: HomeSection) async {
        markLoading(section)
        let outcome = await Self.fetch(section, catalog: catalog, content: content)
        apply(outcome, to: section.id)
    }

    // MARK: Private

    /// The result of one row request.
    private enum RowOutcome: Sendable {
        case products([ProductSummary])
        case articles([ArticleSummary])
        case failed(UserFacingError)
        case cancelled
    }

    /// Shows a skeleton for rows without content; rows with content keep it while reloading.
    private func markLoading(_ section: HomeSection) {
        switch section.content {
        case .collection:
            if productRows[section.id]?.value == nil {
                productRows[section.id] = .loading
            }
        case .blog:
            if articleRows[section.id]?.value == nil {
                articleRows[section.id] = .loading
            }
        }
    }

    private func apply(_ outcome: RowOutcome, to id: String) {
        switch outcome {
        case let .products(products):
            productRows[id] = LoadState(collection: products)
        case let .articles(articles):
            articleRows[id] = LoadState(collection: articles)
        case let .failed(error):
            if productRows[id] != nil, productRows[id]?.value == nil {
                productRows[id] = .failed(error)
            }
            if articleRows[id] != nil, articleRows[id]?.value == nil {
                articleRows[id] = .failed(error)
            }
        case .cancelled:
            if productRows[id]?.isLoading == true {
                productRows[id] = .idle
            }
            if articleRows[id]?.isLoading == true {
                articleRows[id] = .idle
            }
        }
    }

    private nonisolated static func fetch(
        _ section: HomeSection,
        catalog: any CatalogRepository,
        content: any ContentRepository
    ) async -> RowOutcome {
        do {
            switch section.content {
            case let .collection(handle, limit, _):
                let page = try await catalog.collection(
                    handle: handle,
                    first: limit,
                    after: nil,
                    sortKey: .collectionDefault,
                    reverse: false,
                    filters: []
                )
                return .products(page?.products ?? [])
            case let .blog(handle, limit):
                return try await .articles(content.articles(blogHandle: handle, first: limit))
            }
        } catch {
            guard let failure = UserFacingError(error) else { return .cancelled }
            return .failed(failure)
        }
    }
}
