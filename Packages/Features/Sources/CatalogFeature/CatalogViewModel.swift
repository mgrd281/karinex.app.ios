import CommerceUI
import Foundation
import Observation
import ShopifyKit

// MARK: - CatalogViewModel

/// Loads the collections of the Shop tab and arranges them with ``CatalogDirectory``.
@MainActor
@Observable
final class CatalogViewModel {
    /// The load state of the collections.
    private(set) var state: LoadState<CatalogSections> = .idle

    @ObservationIgnored private let catalog: any CatalogRepository

    /// Creates the model; nothing is requested before ``load()``.
    init(catalog: any CatalogRepository) {
        self.catalog = catalog
    }

    /// Loads the collections; keeps the shown list when a reload fails.
    func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            let collections = try await catalog.collections(first: CatalogDirectory.requestLimit)
            state = LoadState(CatalogDirectory.arrange(collections), isEmpty: \.isEmpty)
        } catch {
            guard let failure = UserFacingError(error) else {
                if state.isLoading {
                    state = .idle
                }
                return
            }
            if state.value == nil {
                state = .failed(failure)
            }
        }
    }
}
