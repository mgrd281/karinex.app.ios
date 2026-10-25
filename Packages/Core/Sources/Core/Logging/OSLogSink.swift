#if canImport(os)
import os

/// Writes entries to the unified logging system through `os.Logger`, one logger per
/// `LogCategory` under a common subsystem.
///
/// Messages are interpolated with `privacy: .public`. That is deliberate and safe: `KXLogger`
/// has already passed them through `Redactor`, and marking them private would make every
/// line read `<private>` in Console and in sysdiagnose logs, which defeats their purpose.
public final class OSLogSink: LogSink, @unchecked Sendable {
    // `@unchecked Sendable` is sound: all stored properties are immutable after `init`, and
    // `os.Logger` is documented as safe to use from any thread. The annotation is only needed
    // because not every SDK version marks `os.Logger` as `Sendable`.

    // MARK: - State

    /// The unified logging subsystem.
    public let subsystem: String
    /// Entries below this level are dropped.
    public let minimumLevel: LogLevel
    private let loggers: [LogCategory: Logger]

    // MARK: - Init

    /// Creates a sink writing to `subsystem`, dropping entries below `minimumLevel`.
    public init(subsystem: String = KXLogger.subsystem, minimumLevel: LogLevel = .debug) {
        self.subsystem = subsystem
        self.minimumLevel = minimumLevel
        var loggers: [LogCategory: Logger] = [:]
        for category in LogCategory.allCases {
            loggers[category] = Logger(subsystem: subsystem, category: category.rawValue)
        }
        self.loggers = loggers
    }

    // MARK: - LogSink

    /// Whether `level` is at or above `minimumLevel`.
    public func isEnabled(_ level: LogLevel) -> Bool {
        level >= minimumLevel
    }

    /// Emits `entry` at the matching `os.Logger` level.
    public func write(_ entry: LogEntry) {
        guard isEnabled(entry.level) else { return }
        let logger = loggers[entry.category] ?? Logger(subsystem: subsystem, category: entry.category.rawValue)
        let message = entry.message
        switch entry.level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .notice:
            logger.notice("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .fault:
            logger.fault("\(message, privacy: .public)")
        }
    }
}
#endif
