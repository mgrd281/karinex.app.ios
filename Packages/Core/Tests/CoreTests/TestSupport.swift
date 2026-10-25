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

/// Polls `condition` until it holds or `timeout` has passed.
///
/// The bound is wall-clock time, not a number of polls: on a loaded CI machine the task that
/// makes the condition true can be descheduled for a long time, and a fixed number of fast
/// polls would give up too early. Polls yield first and then sleep briefly, so waiting does not
/// spin a core.
func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    var polls = 0
    while clock.now < deadline {
        if await condition() { return true }
        polls += 1
        if polls < 1000 {
            await Task.yield()
        } else {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
    return await condition()
}
