import CommerceUI
import Core
import Foundation
import Observation
import ShopifyKit

// MARK: - SearchViewModel

/// The state of the search screen: predictive results while typing and the recent searches.
///
/// Typing schedules a predictive request after ``debounce`` (250 ms); every keystroke cancels
/// the previous request, and an answer for an outdated text is dropped, so the results always
/// belong to the text in the field. Results stay visible while the next ones load.
@MainActor
@Observable
final class SearchViewModel {
    /// The number of results per type requested while typing.
    static let predictiveLimit = 6
    /// The standard pause after the last keystroke before a request starts.
    static let standardDebounce = Duration.milliseconds(250)

    /// The predictive results for ``activeQuery``. `.idle` while the field is empty.
    private(set) var predictive: LoadState<PredictiveSearchResult> = .idle
    /// The trimmed text the results belong to (or are loading for).
    private(set) var activeQuery = ""
    /// The recent searches, newest first.
    private(set) var recentSearches: [String]

    @ObservationIgnored private let search: any SearchRepository
    @ObservationIgnored private let recents: RecentSearches
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var predictiveTask: Task<Void, Never>?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - search: The search repository.
    ///   - preferences: Where the recent searches are stored.
    ///   - debounce: The pause after the last keystroke, 250 ms by default.
    init(search: any SearchRepository, preferences: any KeyValueStore, debounce: Duration = standardDebounce) {
        self.search = search
        recents = RecentSearches(store: preferences)
        self.debounce = debounce
        recentSearches = recents.load()
    }

    // MARK: Typing

    /// Reacts to a change of the search text: cancels the running request and, unless the text
    /// is blank, schedules a new one after the debounce interval.
    func queryChanged(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != activeQuery || predictive.error != nil else { return }
        predictiveTask?.cancel()
        activeQuery = trimmed
        guard !trimmed.isEmpty else {
            predictiveTask = nil
            predictive = .idle
            return
        }
        if predictive.value == nil {
            predictive = .loading
        }
        let delay = debounce
        predictiveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.loadPredictive(for: trimmed)
        }
    }

    /// Repeats the request for the current text, e.g. after "Erneut versuchen".
    func retry() async {
        guard !activeQuery.isEmpty else { return }
        predictiveTask?.cancel()
        predictive = .loading
        let query = activeQuery
        let task = Task { [weak self] in
            guard let self else { return }
            await loadPredictive(for: query)
        }
        predictiveTask = task
        await task.value
    }

    /// Waits for the scheduled or running predictive request, if any.
    func waitForPredictive() async {
        await predictiveTask?.value
    }

    private func loadPredictive(for query: String) async {
        do {
            let result = try await search.predictive(query: query, limit: Self.predictiveLimit)
            guard !Task.isCancelled, query == activeQuery else { return }
            predictive = .loaded(result)
        } catch {
            guard !Task.isCancelled, query == activeQuery, let failure = UserFacingError(error) else { return }
            predictive = .failed(failure)
        }
    }

    // MARK: Submitting

    /// Records a submitted search and returns the trimmed query to open the results for, or
    /// `nil` for a blank text.
    @discardableResult
    func submit(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        recentSearches = recents.add(trimmed)
        return trimmed
    }

    // MARK: Recent searches

    /// Removes one recent search.
    func removeRecent(_ query: String) {
        recentSearches = recents.remove(query)
    }

    /// Removes every recent search.
    func clearRecent() {
        recents.clear()
        recentSearches = []
    }
}
