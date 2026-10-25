import Foundation

// MARK: - LogEntry

/// One log message after redaction.
public struct LogEntry: Sendable, Equatable {
    /// Severity of the message.
    public let level: LogLevel
    /// Category of the logger that emitted the message.
    public let category: LogCategory
    /// The already redacted message text.
    public let message: String

    /// Creates an entry. `message` must already be redacted; `KXLogger` takes care of that.
    public init(level: LogLevel, category: LogCategory, message: String) {
        self.level = level
        self.category = category
        self.message = message
    }

    /// A single-line rendering such as `[debug] [graphql] ProductByHandle status=200`.
    public var formattedLine: String {
        "[\(level.rawValue)] [\(category.rawValue)] \(message)"
    }
}

// MARK: - LogSink

/// A destination for log entries. Entries arrive already redacted.
///
/// Sinks are called synchronously from whatever thread logs, so implementations must be
/// thread-safe and fast.
public protocol LogSink: Sendable {
    /// Whether messages of `level` are recorded. `KXLogger` skips building messages for
    /// disabled levels. The default implementation accepts every level.
    func isEnabled(_ level: LogLevel) -> Bool

    /// Records `entry`.
    func write(_ entry: LogEntry)
}

extension LogSink {
    /// Accepts every level.
    public func isEnabled(_ level: LogLevel) -> Bool {
        true
    }
}

// MARK: - StandardErrorLogSink

/// Writes entries as single lines to standard error. Used on platforms without the unified
/// logging system (Linux CI, command line tools).
public struct StandardErrorLogSink: LogSink {
    /// Entries below this level are dropped.
    public let minimumLevel: LogLevel

    /// Creates a sink that drops entries below `minimumLevel`.
    public init(minimumLevel: LogLevel = .debug) {
        self.minimumLevel = minimumLevel
    }

    /// Whether `level` is at or above `minimumLevel`.
    public func isEnabled(_ level: LogLevel) -> Bool {
        level >= minimumLevel
    }

    /// Writes `entry` as one line prefixed with the subsystem.
    public func write(_ entry: LogEntry) {
        guard isEnabled(entry.level) else { return }
        let line = "\(KXLogger.subsystem) \(entry.formattedLine)\n"
        // Logging must never crash or throw; a failed write to stderr is dropped.
        try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
    }
}

// MARK: - RecordingLogSink

/// Keeps every entry in memory. Use it in tests to assert what was logged, and in particular
/// that nothing sensitive was.
///
/// ```swift
/// let sink = RecordingLogSink()
/// let logger = KXLogger(category: .cart, sink: sink)
/// logger.info("Cart gid://shopify/Cart/c1-abc created")
/// #expect(sink.messages == ["Cart gid://shopify/Cart/<redacted> created"])
/// ```
public final class RecordingLogSink: LogSink {
    /// Entries below this level are dropped.
    public let minimumLevel: LogLevel
    private let storage = Locked<[LogEntry]>([])

    /// Creates an empty sink that records entries at or above `minimumLevel`.
    public init(minimumLevel: LogLevel = .debug) {
        self.minimumLevel = minimumLevel
    }

    /// Whether `level` is at or above `minimumLevel`.
    public func isEnabled(_ level: LogLevel) -> Bool {
        level >= minimumLevel
    }

    /// Appends `entry`.
    public func write(_ entry: LogEntry) {
        guard isEnabled(entry.level) else { return }
        storage.withLock { $0.append(entry) }
    }

    /// All recorded entries in the order they were written.
    public var entries: [LogEntry] {
        storage.value
    }

    /// The recorded (redacted) message texts.
    public var messages: [String] {
        entries.map(\.message)
    }

    /// The recorded entries rendered as `[level] [category] message` lines.
    public var lines: [String] {
        entries.map(\.formattedLine)
    }

    /// Forgets all recorded entries.
    public func removeAll() {
        storage.withLock { $0.removeAll() }
    }
}
