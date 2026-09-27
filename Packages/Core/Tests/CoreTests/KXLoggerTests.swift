@testable import Core
import Foundation
import Testing

@Suite("KXLogger")
struct KXLoggerTests {
    @Test("Redacts every message before it reaches the sink")
    func redactsMessages() {
        let sink = RecordingLogSink()
        let logger = KXLogger(category: .cart, sink: sink)
        logger.info("Cart gid://shopify/Cart/c1-abc?key=f00 created for anna@example.com")
        #expect(sink.messages == ["Cart gid://shopify/Cart/<redacted>?key=<redacted> created for <redacted>"])
        #expect(sink.entries.first?.category == .cart)
        #expect(sink.entries.first?.level == .info)
    }

    @Test("Each level method emits its level")
    func levels() {
        let sink = RecordingLogSink()
        let logger = KXLogger(category: .networking, sink: sink)
        logger.debug("d")
        logger.info("i")
        logger.notice("n")
        logger.error("e")
        logger.fault("f")
        #expect(sink.entries.map(\.level) == [.debug, .info, .notice, .error, .fault])
        #expect(sink.lines == [
            "[debug] [networking] d", "[info] [networking] i", "[notice] [networking] n",
            "[error] [networking] e", "[fault] [networking] f",
        ])
    }

    @Test("Does not build messages for disabled levels")
    func lazyEvaluation() {
        let sink = RecordingLogSink(minimumLevel: .error)
        let logger = KXLogger(category: .ui, sink: sink)
        let evaluations = Locked(0)
        func expensive() -> String {
            evaluations.withLock { $0 += 1 }
            return "expensive"
        }
        logger.debug(expensive())
        logger.info(expensive())
        logger.error(expensive())
        #expect(evaluations.value == 1)
        #expect(sink.messages == ["expensive"])
    }

    @Test("Recording sink can be cleared")
    func removeAll() {
        let sink = RecordingLogSink()
        KXLogger(category: .app, sink: sink).notice("hello")
        sink.removeAll()
        #expect(sink.entries.isEmpty)
    }

    @Test("Log levels are ordered by severity")
    func ordering() {
        #expect(LogLevel.debug < .info)
        #expect(LogLevel.info < .notice)
        #expect(LogLevel.notice < .error)
        #expect(LogLevel.error < .fault)
        #expect(LogLevel.allCases.sorted() == LogLevel.allCases)
    }

    @Test("Categories cover every functional area")
    func categories() {
        #expect(LogCategory.allCases.map(\.rawValue) == [
            "app", "networking", "graphql", "storefront", "customerAccount", "cart", "checkout", "auth",
            "keychain", "persistence", "consent", "ui",
        ])
    }

    @Test("The default logger is usable on every platform")
    func defaultSink() {
        let logger = KXLogger(category: .app)
        logger.debug("KXLoggerTests default sink smoke test")
        #expect(logger.category == .app)
        #expect(KXLogger.subsystem == "de.karinex.app")
    }

    @Test("Standard error sink honors its minimum level")
    func standardErrorSink() {
        let sink = StandardErrorLogSink(minimumLevel: .notice)
        #expect(!sink.isEnabled(.info))
        #expect(sink.isEnabled(.notice))
        #expect(sink.isEnabled(.fault))
    }
}
