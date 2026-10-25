@testable import Core
import Foundation
import Testing

@Suite("RetryPolicy")
struct RetryPolicyTests {
    private let policy = RetryPolicy(maxAttempts: 5, baseDelay: .milliseconds(400), maxDelay: .seconds(6))

    @Test("Presets")
    func presets() {
        #expect(RetryPolicy.default.maxAttempts == 3)
        #expect(RetryPolicy.default.baseDelay == .milliseconds(400))
        #expect(RetryPolicy.default.maxDelay == .seconds(6))
        #expect(RetryPolicy.none.maxAttempts == 1)
    }

    @Test("Clamps invalid values")
    func clamping() {
        let clamped = RetryPolicy(maxAttempts: 0, baseDelay: .seconds(-1), maxDelay: .seconds(-2))
        #expect(clamped.maxAttempts == 1)
        #expect(clamped.baseDelay == .zero)
        #expect(clamped.maxDelay == .zero)
        #expect(RetryPolicy(maxAttempts: 2, baseDelay: .seconds(2), maxDelay: .seconds(1)).maxDelay == .seconds(2))
    }

    @Test(
        "Upper bound doubles per retry",
        arguments: [(1, Duration.milliseconds(400)), (2, .milliseconds(800)), (3, .milliseconds(1600)), (4, .milliseconds(3200))]
    )
    func exponentialUpperBound(retry: Int, expected: Duration) {
        #expect(policy.delay(beforeRetry: retry, retryAfter: nil, randomUnit: 1) == expected)
    }

    @Test("Upper bound is capped at maxDelay, also for huge retry numbers")
    func cap() {
        #expect(policy.delay(beforeRetry: 5, retryAfter: nil, randomUnit: 1) == .seconds(6))
        #expect(policy.delay(beforeRetry: 64, retryAfter: nil, randomUnit: 1) == .seconds(6))
        #expect(policy.delay(beforeRetry: Int.max, retryAfter: nil, randomUnit: 1) == .seconds(6))
    }

    @Test("Full jitter stays within 0 and the upper bound", arguments: [0.0, 0.25, 0.5, 0.999])
    func jitterBounds(unit: Double) {
        for retry in 1...6 {
            let delay = policy.delay(beforeRetry: retry, retryAfter: nil, randomUnit: unit)
            let bound = policy.delay(beforeRetry: retry, retryAfter: nil, randomUnit: 1)
            #expect(delay >= .zero)
            #expect(delay <= bound)
        }
        #expect(policy.delay(beforeRetry: 1, retryAfter: nil, randomUnit: 0) == .zero)
    }

    @Test("Jitter is proportional to the random unit")
    func jitterProportional() {
        let half = policy.delay(beforeRetry: 2, retryAfter: nil, randomUnit: 0.5)
        #expect(abs((half - .milliseconds(400)) / .milliseconds(1)) < 0.001)
    }

    @Test("Out-of-range random values and retry numbers are clamped")
    func clampsInputs() {
        #expect(policy.delay(beforeRetry: 0, retryAfter: nil, randomUnit: 1) == .milliseconds(400))
        #expect(policy.delay(beforeRetry: -3, retryAfter: nil, randomUnit: 7) == .milliseconds(400))
        #expect(policy.delay(beforeRetry: 1, retryAfter: nil, randomUnit: -1) == .zero)
        #expect(policy.delay(beforeRetry: 1, retryAfter: nil, randomUnit: .nan) == .zero)
    }

    @Test("Retry-After is a lower bound")
    func retryAfterLowerBound() {
        #expect(policy.delay(beforeRetry: 1, retryAfter: .seconds(2), randomUnit: 0) == .seconds(2))
        #expect(policy.delay(beforeRetry: 1, retryAfter: .milliseconds(100), randomUnit: 1) == .milliseconds(400))
        #expect(policy.delay(beforeRetry: 1, retryAfter: .seconds(-5), randomUnit: 0) == .zero)
    }

    @Test("Retry-After is capped at twice the maximum delay")
    func retryAfterCap() {
        #expect(policy.maxRetryAfter == .seconds(12))
        #expect(RetryPolicy.default.maxRetryAfter == .seconds(12))
        #expect(policy.delay(beforeRetry: 1, retryAfter: .seconds(10), randomUnit: 0) == .seconds(10))
        #expect(policy.delay(beforeRetry: 1, retryAfter: .seconds(120), randomUnit: 0) == .seconds(12))
    }
}

@Suite("RetryExecutor")
struct RetryExecutorTests {
    private func executor(maxAttempts: Int = 3, sleeper: RecordingSleeper) -> RetryExecutor {
        RetryExecutor(
            policy: RetryPolicy(maxAttempts: maxAttempts, baseDelay: .milliseconds(400), maxDelay: .seconds(6)),
            sleeper: sleeper,
            random: { 1 }
        )
    }

    @Test("Returns immediately on success")
    func successFirstTry() async throws {
        let sleeper = RecordingSleeper()
        let attempts = Locked(0)
        let value = try await executor(sleeper: sleeper).run({
            attempts.withLock { $0 += 1 }
            return 42
        }, decide: { _ in .retry(after: nil) })
        #expect(value == 42)
        #expect(attempts.value == 1)
        #expect(sleeper.durations.isEmpty)
    }

    @Test("Succeeds after N failures, backing off exponentially")
    func successAfterFailures() async throws {
        let sleeper = RecordingSleeper()
        let attempts = Locked(0)
        let value = try await executor(maxAttempts: 4, sleeper: sleeper).run({
            let attempt = attempts.withLock { count -> Int in
                count += 1
                return count
            }
            if attempt < 4 { throw TestFailure.retryable(attempt) }
            return "ok"
        }, decide: { _ in .retry(after: nil) })
        #expect(value == "ok")
        #expect(attempts.value == 4)
        #expect(sleeper.durations == [.milliseconds(400), .milliseconds(800), .milliseconds(1600)])
    }

    @Test("Honors the Retry-After from the decision")
    func honorsRetryAfter() async throws {
        let sleeper = RecordingSleeper()
        let attempts = Locked(0)
        _ = try await executor(sleeper: sleeper).run({
            let attempt = attempts.withLock { count -> Int in
                count += 1
                return count
            }
            if attempt == 1 { throw TestFailure.retryable(attempt) }
            return true
        }, decide: { _ in .retry(after: .seconds(3)) })
        #expect(sleeper.durations == [.seconds(3)])
    }

    @Test("Waits a Retry-After of exactly maxRetryAfter")
    func honorsRetryAfterAtCap() async throws {
        let sleeper = RecordingSleeper()
        let attempts = Locked(0)
        _ = try await executor(sleeper: sleeper).run({
            let attempt = attempts.withLock { count -> Int in
                count += 1
                return count
            }
            if attempt == 1 { throw TestFailure.retryable(attempt) }
            return true
        }, decide: { _ in .retry(after: .seconds(12)) })
        #expect(attempts.value == 2)
        #expect(sleeper.durations == [.seconds(12)])
    }

    @Test("Does not retry earlier than a Retry-After beyond maxRetryAfter; gives up instead")
    func retryAfterBeyondCapIsNotRetried() async {
        let sleeper = RecordingSleeper()
        let attempts = Locked(0)
        await #expect(throws: TestFailure.retryable(1)) {
            try await executor(maxAttempts: 5, sleeper: sleeper).run({ () -> Int in
                attempts.withLock { $0 += 1 }
                throw TestFailure.retryable(1)
            }, decide: { _ in .retry(after: .seconds(13)) })
        }
        #expect(attempts.value == 1)
        #expect(sleeper.durations.isEmpty)
    }

    @Test("Stops at doNotRetry and rethrows the error")
    func doNotRetry() async {
        let sleeper = RecordingSleeper()
        let attempts = Locked(0)
        await #expect(throws: TestFailure.fatal) {
            try await executor(sleeper: sleeper).run({ () -> Int in
                attempts.withLock { $0 += 1 }
                throw TestFailure.fatal
            }, decide: { error in
                (error as? TestFailure) == .fatal ? .doNotRetry : .retry(after: nil)
            })
        }
        #expect(attempts.value == 1)
        #expect(sleeper.durations.isEmpty)
    }

    @Test("Exhausts the attempts and rethrows the last error")
    func exhaustsAttempts() async {
        let sleeper = RecordingSleeper()
        let attempts = Locked(0)
        await #expect(throws: TestFailure.retryable(3)) {
            try await executor(maxAttempts: 3, sleeper: sleeper).run({ () -> Int in
                let attempt = attempts.withLock { count -> Int in
                    count += 1
                    return count
                }
                throw TestFailure.retryable(attempt)
            }, decide: { _ in .retry(after: nil) })
        }
        #expect(attempts.value == 3)
        #expect(sleeper.durations.count == 2)
    }

    @Test("A policy of .none runs exactly once")
    func noneRunsOnce() async {
        let attempts = Locked(0)
        await #expect(throws: TestFailure.retryable(1)) {
            try await RetryExecutor(policy: .none, sleeper: RecordingSleeper()).run({ () -> Int in
                attempts.withLock { $0 += 1 }
                throw TestFailure.retryable(1)
            }, decide: { _ in .retry(after: nil) })
        }
        #expect(attempts.value == 1)
    }

    @Test("Stops retrying when the task is cancelled between attempts")
    func cancellationBetweenAttempts() async {
        let sleeper = RecordingSleeper()
        let attempts = Locked(0)
        let executor = executor(maxAttempts: 5, sleeper: sleeper)
        let task = Task {
            try await executor.run({ () -> Int in
                attempts.withLock { $0 += 1 }
                withUnsafeCurrentTask { $0?.cancel() }
                throw TestFailure.retryable(0)
            }, decide: { _ in .retry(after: nil) })
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(attempts.value == 1)
        #expect(sleeper.durations.isEmpty)
    }

    @Test("Never retries a CancellationError thrown by the operation")
    func cancellationErrorNotRetried() async {
        let attempts = Locked(0)
        await #expect(throws: CancellationError.self) {
            try await executor(sleeper: RecordingSleeper()).run({ () -> Int in
                attempts.withLock { $0 += 1 }
                throw CancellationError()
            }, decide: { _ in .retry(after: nil) })
        }
        #expect(attempts.value == 1)
    }

    @Test("TaskSleeper sleeps and observes cancellation")
    func taskSleeper() async {
        let sleeper = TaskSleeper()
        await #expect(throws: Never.self) {
            try await sleeper.sleep(for: .milliseconds(1))
        }
        let task = Task {
            try await sleeper.sleep(for: .seconds(60))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
