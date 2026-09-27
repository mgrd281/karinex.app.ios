import Core
import Foundation
import ShopifyKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Records the ShopifyKit fixtures from the live Storefront API.
///
/// For every `FixtureSpec` the recorder runs the operation through the real `StorefrontClient`
/// (so the response is also decoded and validated), takes the raw body of the final HTTP
/// response from a `RecordingHTTPClient`, anonymizes it, and writes it pretty-printed with
/// sorted keys. Synthetic fixtures are written from their documented JSON. Finally
/// `manifest.json` lists every file with operation, variables, context, API version and date.
///
/// The recorder only runs read queries plus one `cartCreate` whose merchandise ID does not
/// exist, which creates nothing.
public struct FixtureRecorder: Sendable {
    /// The manifest file name.
    public static let manifestFileName = "manifest.json"

    private let options: CommandLineOptions
    private let httpClient: any HTTPClient
    private let progress: @Sendable (String) -> Void
    private let logSink: any LogSink
    private let now: @Sendable () -> Date

    /// Creates a recorder.
    ///
    /// - Parameters:
    ///   - options: Store, version, token and output directory.
    ///   - httpClient: The transport, a `URLSessionHTTPClient` by default.
    ///   - progress: Receives one line per written file.
    ///   - logSink: Receives the GraphQL client's log lines (operation, status, duration,
    ///     cost), standard error by default.
    ///   - now: The clock for the recording date.
    public init(
        options: CommandLineOptions,
        httpClient: any HTTPClient = URLSessionHTTPClient(configuration: .ephemeral),
        progress: @escaping @Sendable (String) -> Void = { print($0) },
        logSink: any LogSink = StandardErrorLogSink(minimumLevel: .debug),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.options = options
        self.httpClient = httpClient
        self.progress = progress
        self.logSink = logSink
        self.now = now
    }

    /// Records every fixture and writes the manifest.
    ///
    /// - Returns: The written file names, manifest last.
    @discardableResult
    public func run() async throws -> [String] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)

        let recordedAt = now()
        let recordedAtString = Self.iso8601(recordedAt)
        let configuration = options.storefrontConfiguration
        let recording = RecordingHTTPClient(base: httpClient)
        let logger = KXLogger(category: .graphql, sink: logSink)
        let client = StorefrontClient(configuration: configuration, httpClient: recording, logger: logger)
        let tokenlessConfiguration = StorefrontConfiguration(
            endpoint: configuration.endpoint,
            accessToken: nil,
            apiVersion: configuration.apiVersion
        )
        let tokenlessClient = configuration.isTokenless
            ? client
            : StorefrontClient(configuration: tokenlessConfiguration, httpClient: recording, logger: logger)

        var written: [String] = []
        var entries: [JSONValue] = []

        for spec in try FixturePlan.liveFixtures(isTokenless: configuration.isTokenless) {
            recording.takeExchanges()
            let usesTokenlessClient = spec.requiresTokenlessClient || configuration.isTokenless
            try await spec.execute(spec.requiresTokenlessClient ? tokenlessClient : client)
            let exchanges = recording.takeExchanges()
            guard let final = exchanges.last else {
                throw FixtureSpec.UnexpectedOutcome(fileName: spec.fileName, detail: "no HTTP response was recorded")
            }

            let (anonymized, changedPaths) = try FixtureAnonymizer.anonymize(JSONValue.parseObject(final.response.body))
            try JSONValue.object(anonymized).prettyPrintedData().write(to: fileURL(spec.fileName), options: .atomic)
            written.append(spec.fileName)
            progress("Recorded \(spec.fileName) (HTTP \(final.response.statusCode), \(exchanges.count) attempt(s))")

            entries.append(.object([
                "file": .string(spec.fileName),
                "source": .string("live"),
                "summary": .string(spec.summary),
                "operation": .string(spec.operationName),
                "kind": .string(spec.kind.rawValue),
                "variables": spec.variables,
                "context": Self.contextValue(spec.context),
                "expectedOutcome": .string(spec.expectedOutcome.rawValue),
                "tokenless": .bool(usesTokenlessClient),
                "httpStatus": .integer(Int64(final.response.statusCode)),
                "attempts": .integer(Int64(exchanges.count)),
                "anonymizedPaths": .array(changedPaths.sorted().map(JSONValue.string)),
                "apiVersion": .string(configuration.apiVersion),
                "endpoint": .string(configuration.endpoint.absoluteString),
                "recordedAt": .string(recordedAtString),
            ]))
        }

        for synthetic in SyntheticFixture.all {
            let object = try JSONValue.parseObject(Data(synthetic.json.utf8))
            try JSONValue.object(object).prettyPrintedData().write(to: fileURL(synthetic.fileName), options: .atomic)
            written.append(synthetic.fileName)
            progress("Wrote \(synthetic.fileName) (synthetic)")
            entries.append(.object([
                "file": .string(synthetic.fileName),
                "source": .string("synthetic"),
                "summary": .string(synthetic.summary),
                "documentation": .string(synthetic.documentationURL),
                "apiVersion": .string(configuration.apiVersion),
                "recordedAt": .string(recordedAtString),
            ]))
        }

        let manifest = JSONValue.object([
            "generator": .string("Tools/FixtureRecorder (swift run fixture-recorder)"),
            "shopDomain": .string(options.shopDomain),
            "apiVersion": .string(configuration.apiVersion),
            "endpoint": .string(configuration.endpoint.absoluteString),
            "tokenless": .bool(configuration.isTokenless),
            "recordedAt": .string(recordedAtString),
            "fixtures": .array(entries),
        ])
        try manifest.prettyPrintedData().write(to: fileURL(Self.manifestFileName), options: .atomic)
        written.append(Self.manifestFileName)
        progress("Wrote \(Self.manifestFileName) with \(entries.count) fixtures")
        return written
    }

    // MARK: - Helpers

    private func fileURL(_ fileName: String) -> URL {
        options.outputDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The manifest representation of a context, including the rendered directive.
    static func contextValue(_ context: StorefrontContext) -> JSONValue {
        var object: [String: JSONValue] = [
            "country": .string(context.country.rawValue),
            "language": .string(context.language.rawValue),
            "directive": .string(context.directive),
        ]
        if let consent = context.visitorConsent {
            let fields: [(String, Bool?)] = [
                ("analytics", consent.analytics),
                ("preferences", consent.preferences),
                ("marketing", consent.marketing),
                ("saleOfData", consent.saleOfData),
            ]
            var consentObject: [String: JSONValue] = [:]
            for (name, value) in fields {
                if let value {
                    consentObject[name] = .bool(value)
                }
            }
            object["visitorConsent"] = .object(consentObject)
        }
        return .object(object)
    }

    /// `yyyy-MM-ddTHH:mm:ssZ` in UTC.
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
