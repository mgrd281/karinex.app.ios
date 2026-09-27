import Foundation

/// A value protected by an `NSLock`.
///
/// `Synchronization.Mutex` would be the modern choice but requires iOS 18, while the app
/// supports iOS 17. `Locked` offers the same programming model: every read and write of the
/// wrapped value happens inside `withLock(_:)`.
///
/// ```swift
/// let counter = Locked(0)
/// counter.withLock { $0 += 1 }
/// print(counter.value) // 1
/// ```
///
/// - Important: Keep the closures passed to `withLock(_:)` short and never call back into
///   code that could take the same lock again. `NSLock` is not recursive, so re-entrant use
///   deadlocks.
public final class Locked<Value: Sendable>: @unchecked Sendable {
    // `@unchecked Sendable` is sound because:
    // 1. `storage` is only ever read or written while `lock` is held (see `withLock`).
    // 2. `Value` is constrained to `Sendable`, so values that are copied in or out of the
    //    lock can be shared across concurrency domains without further synchronization.

    // MARK: - State

    private let lock = NSLock()
    private var storage: Value

    // MARK: - Init

    /// Creates a lock-protected container holding `value`.
    public init(_ value: Value) {
        storage = value
    }

    // MARK: - Access

    /// Runs `body` with exclusive, mutable access to the protected value and returns its result.
    ///
    /// The lock is held for the whole duration of `body`, including when `body` throws.
    @discardableResult
    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&storage)
    }

    /// A snapshot of the protected value, read under the lock.
    public var value: Value {
        withLock { $0 }
    }

    /// Replaces the protected value and returns the previous one.
    @discardableResult
    public func replace(with newValue: Value) -> Value {
        withLock { current in
            let previous = current
            current = newValue
            return previous
        }
    }
}
