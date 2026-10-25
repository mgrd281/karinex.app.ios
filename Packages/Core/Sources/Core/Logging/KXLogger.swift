import Foundation

// MARK: - LogCategory

/// Functional areas used to group log output (the `category` of `os.Logger`).
public enum LogCategory: String, Sendable, CaseIterable {
    /// App lifecycle and composition root.
    case app
    /// HTTP transport.
    case networking
    /// GraphQL client (operation names, status, cost).
    case graphql
    /// Storefront API repositories.
    case storefront
    /// Customer Account API.
    case customerAccount
    /// Cart state and mutations.
    case cart
    /// Checkout presentation and events.
    case checkout
    /// Login, tokens and sessions.
    case auth
    /// Keychain access.
    case keychain
    /// Local persistence (preferences, caches).
    case persistence
    /// Privacy consent decisions.
    case consent
    /// User interface.
    case ui
}

// MARK: - LogLevel

/// Severity of a log message, mirroring the levels of `os.Logger`.
public enum LogLevel: String, Sendable, CaseIterable, Comparable {
    /// Verbose diagnostics for development. Not persisted by the unified logging system.
    case debug
    /// Helpful but non-essential information.
    case info
    /// Normal but significant events (the default level of `os.Logger`).
    case notice
    /// Errors the app recovers from.
    case error
    /// Bugs and unrecoverable conditions.
    case fault

    private var severity: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .notice: 2
        case .error: 3
        case .fault: 4
        }
    }

    /// Orders levels by severity, `debug` being the lowest.
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.severity < rhs.severity
    }
}

// MARK: - KXLogger

/// The app's logger. Every message is passed through `Redactor.redact(_:)` before it is
/// handed to a `LogSink`, so emails, tokens, license keys, cart tokens and similar values
/// never reach the log store.
///
/// On Apple platforms the default sink writes to the unified logging system
/// (`os.Logger(subsystem: "de.karinex.app", category:)`); elsewhere it writes to standard
/// error. Inject a `RecordingLogSink` in tests to assert on the emitted lines.
///
/// ```swift
/// let logger = KXLogger(category: .graphql)
/// logger.debug("ProductByHandle status=200 duration=84ms")
/// ```
///
/// - Important: Redaction is a safety net, not a license to log sensitive data. Log
///   operation names, status codes and durations, never request or response bodies.
public struct KXLogger: Sendable {
    /// The unified logging subsystem of the app.
    public static let subsystem = "de.karinex.app"

    /// The sink used by `init(category:)`: `os.Logger` on Apple platforms, standard error
    /// elsewhere. Debug messages are dropped in release builds.
    public static let defaultSink: any LogSink = {
        #if DEBUG
        let minimumLevel = LogLevel.debug
        #else
        let minimumLevel = LogLevel.info
        #endif
        #if canImport(os)
        return OSLogSink(subsystem: subsystem, minimumLevel: minimumLevel)
        #else
        return StandardErrorLogSink(minimumLevel: minimumLevel)
        #endif
    }()

    /// The category every message of this logger is filed under.
    public let category: LogCategory
    private let sink: any LogSink

    /// Creates a logger for `category` that writes to `KXLogger.defaultSink`.
    public init(category: LogCategory) {
        self.init(category: category, sink: Self.defaultSink)
    }

    /// Creates a logger for `category` that writes to `sink`, e.g. a `RecordingLogSink` in tests.
    public init(category: LogCategory, sink: any LogSink) {
        self.category = category
        self.sink = sink
    }

    // MARK: - Logging

    /// Logs `message` at `level`. The message is only built when the sink accepts the level.
    public func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        guard sink.isEnabled(level) else { return }
        sink.write(LogEntry(level: level, category: category, message: Redactor.redact(message())))
    }

    /// Logs a verbose diagnostic message.
    public func debug(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    /// Logs an informational message.
    public func info(_ message: @autoclosure () -> String) {
        log(.info, message())
    }

    /// Logs a normal but significant event.
    public func notice(_ message: @autoclosure () -> String) {
        log(.notice, message())
    }

    /// Logs an error the app recovers from.
    public func error(_ message: @autoclosure () -> String) {
        log(.error, message())
    }

    /// Logs a bug or an unrecoverable condition.
    public func fault(_ message: @autoclosure () -> String) {
        log(.fault, message())
    }
}
