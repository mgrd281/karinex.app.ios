import Foundation

// MARK: - NetworkStatus

/// Reachability of the network as seen by the device.
public enum NetworkStatus: Sendable, Equatable {
    /// A usable path exists. `isExpensive` is true on cellular or a personal hotspot,
    /// `isConstrained` when Low Data Mode is on.
    case online(isExpensive: Bool, isConstrained: Bool)
    /// No usable path exists.
    case offline

    /// Whether a usable path exists.
    public var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    /// Whether the app should save data (expensive or constrained path): e.g. request smaller
    /// images and skip prefetching.
    public var prefersReducedDataUsage: Bool {
        switch self {
        case let .online(isExpensive, isConstrained):
            isExpensive || isConstrained
        case .offline:
            false
        }
    }
}

// MARK: - NetworkMonitoring

/// Observes network reachability. Drives the offline banner and fail-fast decisions.
public protocol NetworkMonitoring: Sendable {
    /// The latest known status. Waits for the first measurement if none is available yet.
    var currentStatus: NetworkStatus { get async }

    /// A stream that first yields the current status (as soon as it is known) and then every
    /// change. Consecutive duplicates are not repeated. Each call returns an independent
    /// stream; it ends when the consuming task is cancelled or the monitor is deallocated.
    func statusUpdates() -> AsyncStream<NetworkStatus>
}

// MARK: - StaticNetworkMonitor

/// A monitor with a fixed status, for previews and tests.
public struct StaticNetworkMonitor: NetworkMonitoring {
    /// The status this monitor always reports.
    public let status: NetworkStatus

    /// Creates a monitor that always reports `status` (online, unmetered by default).
    public init(status: NetworkStatus = .online(isExpensive: false, isConstrained: false)) {
        self.status = status
    }

    /// Returns `status`.
    public var currentStatus: NetworkStatus {
        get async { status }
    }

    /// A stream that yields `status` once and then finishes, since it never changes.
    public func statusUpdates() -> AsyncStream<NetworkStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: NetworkStatus.self)
        continuation.yield(status)
        continuation.finish()
        return stream
    }
}

// MARK: - ManualNetworkMonitor

/// A monitor whose status is set explicitly, for tests and UI tests that simulate going
/// offline and back online.
public final class ManualNetworkMonitor: NetworkMonitoring {
    private let broadcaster: NetworkStatusBroadcaster

    /// Creates a monitor reporting `initialStatus` (online, unmetered by default).
    public init(initialStatus: NetworkStatus = .online(isExpensive: false, isConstrained: false)) {
        broadcaster = NetworkStatusBroadcaster(initialStatus: initialStatus)
    }

    deinit {
        broadcaster.finishAll()
    }

    /// The status last passed to `update(to:)` or the initial status.
    public var currentStatus: NetworkStatus {
        get async { await broadcaster.currentStatus() }
    }

    /// See `NetworkMonitoring.statusUpdates()`.
    public func statusUpdates() -> AsyncStream<NetworkStatus> {
        broadcaster.makeStream()
    }

    /// Changes the status and notifies all subscribers (unless it did not change).
    public func update(to status: NetworkStatus) {
        broadcaster.publish(status)
    }
}

// MARK: - NetworkStatusBroadcaster

/// Thread-safe fan-out of network status values to any number of `AsyncStream` subscribers.
final class NetworkStatusBroadcaster: Sendable {
    private struct State: Sendable {
        var status: NetworkStatus?
        var subscribers: [UInt64: AsyncStream<NetworkStatus>.Continuation] = [:]
        var pendingReaders: [CheckedContinuation<NetworkStatus, Never>] = []
        var nextSubscriberID: UInt64 = 0
    }

    private let state: Locked<State>

    /// Creates a broadcaster. With a `nil` status, readers wait for the first `publish(_:)`.
    init(initialStatus: NetworkStatus?) {
        state = Locked(State(status: initialStatus))
    }

    /// The latest status, waiting for the first one if necessary.
    func currentStatus() async -> NetworkStatus {
        if let status = state.withLock({ $0.status }) {
            return status
        }
        return await withCheckedContinuation { continuation in
            let known = state.withLock { state -> NetworkStatus? in
                if let status = state.status { return status }
                state.pendingReaders.append(continuation)
                return nil
            }
            if let known {
                continuation.resume(returning: known)
            }
        }
    }

    /// Stores `status` and delivers it to every subscriber and waiting reader, unless it
    /// equals the current status.
    func publish(_ status: NetworkStatus) {
        let readers = state.withLock { state -> [CheckedContinuation<NetworkStatus, Never>] in
            guard state.status != status else { return [] }
            state.status = status
            // Yield while holding the lock so that every subscriber sees the values in order,
            // even when a subscription races with an update. `yield` never calls back into
            // this type, so it cannot deadlock.
            for continuation in state.subscribers.values {
                continuation.yield(status)
            }
            let readers = state.pendingReaders
            state.pendingReaders.removeAll()
            return readers
        }
        for reader in readers {
            reader.resume(returning: status)
        }
    }

    /// Returns a new stream that starts with the current status (if known).
    func makeStream() -> AsyncStream<NetworkStatus> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: NetworkStatus.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = state.withLock { state -> UInt64 in
            state.nextSubscriberID &+= 1
            let id = state.nextSubscriberID
            state.subscribers[id] = continuation
            if let status = state.status {
                continuation.yield(status)
            }
            return id
        }
        continuation.onTermination = { [weak self] _ in
            self?.removeSubscriber(id)
        }
        return stream
    }

    /// The number of live subscriptions. Intended for diagnostics and tests.
    var subscriberCount: Int {
        state.withLock { $0.subscribers.count }
    }

    /// Finishes every stream. Called when the owning monitor goes away.
    func finishAll() {
        let subscribers = state.withLock { state -> [AsyncStream<NetworkStatus>.Continuation] in
            let subscribers = Array(state.subscribers.values)
            state.subscribers.removeAll()
            return subscribers
        }
        // Outside the lock: `finish()` runs `onTermination`, which takes the lock.
        for continuation in subscribers {
            continuation.finish()
        }
    }

    private func removeSubscriber(_ id: UInt64) {
        state.withLock { state in
            _ = state.subscribers.removeValue(forKey: id)
        }
    }
}
