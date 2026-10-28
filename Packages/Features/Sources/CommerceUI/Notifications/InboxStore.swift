import BackendKit
import Core
import Foundation
import Observation

// MARK: - InboxStore

/// "Neuigkeiten" behind the bell (owner request 2026-10-28, as at About You): the messages of
/// the KARINEX backend (`GET /v1/app/notifications`), which of them are new, and the variants
/// the customer asked to hear about when they are available again.
///
/// - Read state lives on the device only: a message is new when it is newer than the moment the
///   customer last opened "Neuigkeiten". Nothing about reading is sent to the backend.
/// - Restock watches are kept locally too, so the product screen shows "Wir benachrichtigen Sie"
///   at once; the backend gets the same request and sends the message.
/// - Messages of a kind this app version does not know are left out.
@MainActor
@Observable
public final class InboxStore {
    /// Preferences key of the last time "Neuigkeiten" was opened.
    static let seenKey = "inbox.seen.v1"
    /// Preferences key of the watched variant IDs.
    static let watchesKey = "inbox.restock.v1"

    /// The loaded messages, newest first.
    public private(set) var state: LoadState<[InboxMessage]> = .idle
    /// When the customer last opened "Neuigkeiten".
    public private(set) var lastSeen: Date
    /// The variants the customer asked to hear about.
    public private(set) var watchedVariantIDs: Set<String>

    @ObservationIgnored private let backend: any BackendClient
    @ObservationIgnored private let store: any KeyValueStore
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Creates the store.
    ///
    /// - Parameters:
    ///   - backend: Loads the messages and receives restock requests.
    ///   - store: Keeps the read state and the watches on the device.
    ///   - now: The clock, replaceable in tests.
    public init(backend: any BackendClient, store: any KeyValueStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.backend = backend
        self.store = store
        self.now = now
        lastSeen = store.string(forKey: Self.seenKey).flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        let data = store.data(forKey: Self.watchesKey)
        watchedVariantIDs = Set(data.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
    }

    // MARK: Messages

    /// The messages the app can show.
    public var messages: [InboxMessage] {
        if case let .loaded(messages) = state {
            return messages
        }
        return []
    }

    /// How many messages arrived since "Neuigkeiten" was last opened.
    public var unreadCount: Int {
        messages.filter { $0.createdAt > lastSeen }.count
    }

    /// Whether `message` arrived since "Neuigkeiten" was last opened.
    public func isUnread(_ message: InboxMessage) -> Bool {
        message.createdAt > lastSeen
    }

    /// Loads the messages; a failure keeps messages shown before.
    public func refresh() async {
        if case .loaded = state {} else {
            state = .loading
        }
        do {
            let messages = try await backend.notifications().filter { $0.kind != .unknown }
            state = LoadState(messages) { $0.isEmpty }
        } catch {
            guard let failure = UserFacingError(error) else { return }
            if case .loaded = state { return }
            state = .failed(failure)
        }
    }

    /// Marks every message as read, e.g. when the customer leaves "Neuigkeiten".
    public func markAllSeen() {
        let newest = messages.map(\.createdAt).max() ?? now()
        let seen = max(newest, lastSeen)
        lastSeen = seen
        store.set(String(seen.timeIntervalSince1970), forKey: Self.seenKey)
    }

    // MARK: Restock

    /// Whether the customer asked to hear about `variantID`.
    public func isWatching(variantID: String) -> Bool {
        watchedVariantIDs.contains(variantID)
    }

    /// Asks for a message when the variant is available again, or cancels that request.
    ///
    /// - Returns: Whether the backend accepted the change; on failure nothing changes.
    @discardableResult
    public func setWatching(_ watching: Bool, productHandle: String, variantID: String, productTitle: String) async -> Bool {
        do {
            if watching {
                try await backend.watchRestock(RestockWatch(productHandle: productHandle, variantID: variantID, productTitle: productTitle))
                watchedVariantIDs.insert(variantID)
            } else {
                try await backend.unwatchRestock(variantID: variantID)
                watchedVariantIDs.remove(variantID)
            }
            store.set(try? JSONEncoder().encode(watchedVariantIDs.sorted()), forKey: Self.watchesKey)
            return true
        } catch {
            return false
        }
    }
}
