@testable import Core
import Foundation

/// A `Sleeper` that records requested durations and returns immediately.
final class RecordingSleeper: Sleeper {
    private let recorded = Locked<[Duration]>([])

    /// Every duration passed to `sleep(for:)`, in order.
    var durations: [Duration] {
        recorded.value
    }

    func sleep(for duration: Duration) async throws {
        recorded.withLock { $0.append(duration) }
        try Task.checkCancellation()
    }
}

/// A one-shot latch: tasks wait until it is opened.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends until `open()` has been called.
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases all current and future waiters.
    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

/// An error used to drive retry and deduplication tests.
enum TestFailure: Error, Equatable {
    case retryable(Int)
    case fatal
}

/// Polls `condition` until it holds or `limit` yields have passed.
func eventually(limit: Int = 100_000, _ condition: () async -> Bool) async -> Bool {
    for _ in 0..<limit {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}
