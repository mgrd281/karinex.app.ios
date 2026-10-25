import Foundation

/// Coalesces concurrent identical requests into one in-flight operation.
///
/// Callers that ask for the same key while an operation for it is running share that
/// operation's result (or error) instead of starting their own. The entry is removed as soon
/// as the operation finishes, successfully or not, so the next call starts fresh: this type
/// de-duplicates, it does not cache.
///
/// ```swift
/// let deduplicator = RequestDeduplicator<HTTPRequest, HTTPResponse>()
/// let response = try await deduplicator.value(for: request) {
///     try await httpClient.send(request)
/// }
/// ```
///
/// The key must capture everything that changes the result. For HTTP that is the whole
/// request (URL, headers including credentials, body), not just the body: two callers with
/// different access tokens must never share a response.
///
/// ## Cancellation
///
/// The shared operation runs in its own unstructured task, so cancelling one caller does not
/// cancel it for the others:
///
/// - While at least one caller is still waiting, a cancelled caller keeps waiting for the
///   shared result and receives it (or its error) like everyone else. Check
///   `Task.isCancelled` afterwards if the result is no longer needed.
/// - When the last waiting caller is cancelled, the shared operation is cancelled too, and
///   all its callers receive the error the operation throws in response (for
///   `URLSessionHTTPClient` that is `NetworkError.cancelled`).
/// - A call arriving after the shared operation was cancelled does not join it; it starts a
///   new operation.
public actor RequestDeduplicator<Key: Hashable & Sendable, Value: Sendable> {
    // MARK: - Types

    /// Bookkeeping for one in-flight operation.
    private final class Entry: Sendable {
        struct Waiters: Sendable {
            var active = 1
            var isCancelled = false
        }

        let id: UInt64
        let task: Task<Value, any Error>
        private let waiters = Locked(Waiters())

        init(id: UInt64, task: Task<Value, any Error>) {
            self.id = id
            self.task = task
        }

        /// Registers another waiting caller. Returns `false` if the operation was already
        /// cancelled because every earlier caller went away.
        func join() -> Bool {
            waiters.withLock { waiters in
                guard !waiters.isCancelled else { return false }
                waiters.active += 1
                return true
            }
        }

        /// Unregisters a cancelled caller and cancels the operation when none is left.
        /// Called synchronously from a task cancellation handler, hence the lock.
        func leave() {
            let shouldCancel = waiters.withLock { waiters -> Bool in
                waiters.active -= 1
                guard waiters.active <= 0, !waiters.isCancelled else { return false }
                waiters.isCancelled = true
                return true
            }
            if shouldCancel {
                task.cancel()
            }
        }

        var activeWaiters: Int {
            waiters.value.active
        }
    }

    // MARK: - State

    private var entries: [Key: Entry] = [:]
    private var nextID: UInt64 = 0

    // MARK: - Init

    /// Creates an empty deduplicator.
    public init() {}

    // MARK: - API

    /// Returns the result of `operation`, sharing a single execution among all concurrent
    /// callers that pass the same `key`.
    ///
    /// - Parameters:
    ///   - key: Identifies equivalent requests, e.g. the encoded request body.
    ///   - operation: Performs the request. Only called when no operation for `key` is in flight.
    /// - Throws: Whatever the shared operation throws.
    public func value(
        for key: Key,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let entry = joinOrStart(key: key, operation: operation)
        return try await withTaskCancellationHandler {
            try await entry.task.value
        } onCancel: {
            entry.leave()
        }
    }

    /// The number of operations currently in flight.
    public var inFlightCount: Int {
        entries.count
    }

    /// The number of non-cancelled callers waiting for the operation for `key` (0 when none
    /// is in flight). Intended for diagnostics and tests.
    public func waiterCount(for key: Key) -> Int {
        entries[key]?.activeWaiters ?? 0
    }

    // MARK: - Private

    private func joinOrStart(key: Key, operation: @escaping @Sendable () async throws -> Value) -> Entry {
        if let existing = entries[key], existing.join() {
            return existing
        }

        nextID &+= 1
        let id = nextID
        // The task inherits this actor's isolation because it captures `self`, so the entry is
        // removed on the actor right when the operation finishes, before any waiter resumes.
        let task = Task<Value, any Error> {
            defer { self.removeEntry(for: key, id: id) }
            return try await operation()
        }
        let entry = Entry(id: id, task: task)
        entries[key] = entry
        return entry
    }

    private func removeEntry(for key: Key, id: UInt64) {
        // A cancelled entry may already have been replaced by a newer operation for the key.
        if entries[key]?.id == id {
            entries[key] = nil
        }
    }
}
