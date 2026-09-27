import Foundation

// MARK: - RetryPolicy

/// How often and how patiently a failed operation is retried.
///
/// Delays use exponential backoff with full jitter (see `delay(beforeRetry:retryAfter:randomUnit:)`),
/// which spreads retries of many clients evenly instead of letting them hit the server in waves.
public struct RetryPolicy: Sendable, Equatable {
    /// Total number of attempts including the first one. Always at least 1.
    public let maxAttempts: Int
    /// Upper bound of the delay before the first retry; doubled for every further retry.
    public let baseDelay: Duration
    /// Upper bound of any backoff delay.
    public let maxDelay: Duration

    /// Creates a policy. Values are clamped: at least one attempt, no negative delays, and
    /// `maxDelay` never below `baseDelay`.
    public init(maxAttempts: Int, baseDelay: Duration, maxDelay: Duration) {
        let baseDelay = max(baseDelay, .zero)
        self.maxAttempts = max(maxAttempts, 1)
        self.baseDelay = baseDelay
        self.maxDelay = max(maxDelay, baseDelay)
    }

    /// Three attempts, 0.4 s base delay, 6 s maximum delay.
    public static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(400), maxDelay: .seconds(6))

    /// A single attempt, never retried.
    public static let none = RetryPolicy(maxAttempts: 1, baseDelay: .zero, maxDelay: .zero)

    /// The delay before retry number `retry` (1 for the first retry, that is the second attempt).
    ///
    /// Full jitter: a uniformly random delay in `0 ... min(maxDelay, baseDelay * 2^(retry - 1))`,
    /// where `randomUnit` (clamped to `0...1`) picks the point in that range. A server-provided
    /// `retryAfter` is a lower bound, and the result never exceeds `maxDelay * 2`, so a
    /// misconfigured server cannot park the app for minutes.
    ///
    /// - Parameters:
    ///   - retry: The 1-based retry number. Values below 1 are treated as 1.
    ///   - retryAfter: The delay requested by the server, e.g. from `Retry-After`.
    ///   - randomUnit: A random number in `0..<1`.
    public func delay(beforeRetry retry: Int, retryAfter: Duration?, randomUnit: Double) -> Duration {
        let exponent = min(max(retry, 1) - 1, 30)
        let multiplier = 1 << exponent
        let ceiling: Duration = baseDelay > maxDelay / multiplier ? maxDelay : min(baseDelay * multiplier, maxDelay)

        let unit = randomUnit.isFinite ? min(max(randomUnit, 0), 1) : 0
        var delay = ceiling * unit

        if let retryAfter {
            delay = max(delay, max(retryAfter, .zero))
        }
        return min(delay, maxDelay * 2)
    }
}

// MARK: - Sleeper

/// Suspends the current task. Injected so tests can run retries without real waiting.
public protocol Sleeper: Sendable {
    /// Suspends for `duration`.
    ///
    /// - Throws: `CancellationError` when the task is cancelled while sleeping.
    func sleep(for duration: Duration) async throws
}

/// A `Sleeper` backed by `Task.sleep(for:)`.
public struct TaskSleeper: Sleeper {
    /// Creates a sleeper.
    public init() {}

    /// Suspends the current task for `duration` using the continuous clock.
    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

// MARK: - RetryDecision

/// Whether a failed attempt should be retried.
public enum RetryDecision: Sendable, Equatable {
    /// Retry, waiting at least `after` (for example the server's `Retry-After`) if given.
    case retry(after: Duration?)
    /// Give up and rethrow the error.
    case doNotRetry
}

// MARK: - RetryExecutor

/// Runs an async operation and retries it according to a `RetryPolicy`.
///
/// The executor is policy-agnostic about *which* errors are retryable: the caller decides per
/// error through the `decide` closure (for example "retry queries on 503, never retry
/// mutations").
public struct RetryExecutor: Sendable {
    /// The policy that bounds attempts and delays.
    public let policy: RetryPolicy
    private let sleeper: any Sleeper
    private let random: @Sendable () -> Double

    /// Creates an executor.
    ///
    /// - Parameters:
    ///   - policy: Attempt and delay bounds, `.default` by default.
    ///   - sleeper: Performs the waiting between attempts, `TaskSleeper()` by default.
    ///   - random: Returns a random number in `0..<1` for the jitter.
    public init(
        policy: RetryPolicy = .default,
        sleeper: any Sleeper = TaskSleeper(),
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.policy = policy
        self.sleeper = sleeper
        self.random = random
    }

    /// Runs `operation` until it succeeds, `decide` returns `.doNotRetry`, or
    /// `policy.maxAttempts` attempts have failed.
    ///
    /// - A `CancellationError` thrown by `operation` is never retried.
    /// - Between attempts the executor checks for task cancellation (before and after the
    ///   backoff delay) and throws `CancellationError` if the task was cancelled.
    /// - When the operation finally fails, the error of the last attempt is rethrown unchanged.
    public func run<T: Sendable>(
        _ operation: @Sendable () async throws -> T,
        decide: @Sendable (any Error) -> RetryDecision
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                if error is CancellationError || attempt >= policy.maxAttempts {
                    throw error
                }
                guard case let .retry(retryAfter) = decide(error) else {
                    throw error
                }
                try Task.checkCancellation()
                let delay = policy.delay(beforeRetry: attempt, retryAfter: retryAfter, randomUnit: random())
                if delay > .zero {
                    try await sleeper.sleep(for: delay)
                }
                try Task.checkCancellation()
                attempt += 1
            }
        }
    }
}
