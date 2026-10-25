#if canImport(Network)
import Dispatch
import Network

/// `NetworkMonitoring` backed by `NWPathMonitor`.
///
/// The monitor starts on creation and stops when the instance is deallocated. Path updates are
/// delivered on a private serial queue and fanned out to any number of `statusUpdates()`
/// subscribers. Create one instance per app (the app container does) and share it.
public final class NWPathNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    // `@unchecked Sendable` is sound: all stored properties are immutable after `init`.
    // `NWPathMonitor` may be started and cancelled from any thread and calls its handler on
    // `queue` only; mutable state lives in `NetworkStatusBroadcaster`, which guards it with a
    // lock. The annotation is needed because not every SDK marks `NWPathMonitor` `Sendable`.

    // MARK: - State

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "de.karinex.network-monitor", qos: .utility)
    private let broadcaster = NetworkStatusBroadcaster(initialStatus: nil)

    // MARK: - Init

    /// Creates and starts a monitor for all interfaces.
    public convenience init() {
        self.init(monitor: NWPathMonitor())
    }

    /// Creates and starts a monitor restricted to one interface type, e.g. `.wifi`.
    public convenience init(requiredInterfaceType: NWInterface.InterfaceType) {
        self.init(monitor: NWPathMonitor(requiredInterfaceType: requiredInterfaceType))
    }

    private init(monitor: NWPathMonitor) {
        self.monitor = monitor
        let broadcaster = broadcaster
        monitor.pathUpdateHandler = { path in
            broadcaster.publish(NWPathNetworkMonitor.status(of: path))
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
        broadcaster.finishAll()
    }

    // MARK: - NetworkMonitoring

    /// The latest path status. Right after creation this waits for the monitor's first path
    /// update, which `NWPathMonitor` delivers immediately after starting.
    public var currentStatus: NetworkStatus {
        get async { await broadcaster.currentStatus() }
    }

    /// See `NetworkMonitoring.statusUpdates()`.
    public func statusUpdates() -> AsyncStream<NetworkStatus> {
        broadcaster.makeStream()
    }

    // MARK: - Mapping

    /// Maps a path to a status. `requiresConnection` counts as online: the system brings the
    /// path up on demand (for example an on-demand VPN), so requests can still succeed.
    private static func status(of path: NWPath) -> NetworkStatus {
        if path.status == .satisfied || path.status == .requiresConnection {
            return .online(isExpensive: path.isExpensive, isConstrained: path.isConstrained)
        }
        return .offline
    }
}
#endif
