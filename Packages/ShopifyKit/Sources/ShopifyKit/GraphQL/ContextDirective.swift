import Core
import Foundation

// MARK: - StorefrontContext

/// The buyer context of a Storefront API call, rendered as the `@inContext` directive.
///
/// Country and language select the market (currency, prices, availability) and the content
/// translation. The visitor consent tells Shopify which tracking the buyer allowed; Shopify
/// encodes it into the cart's `checkoutUrl` so checkout applies the same rules.
public struct StorefrontContext: Sendable, Hashable, Codable {
    /// The buyer's country, which selects the market.
    public var country: CountryCode
    /// The content language.
    public var language: LanguageCode
    /// The buyer's tracking consent, or `nil` to leave it unspecified.
    public var visitorConsent: VisitorConsent?

    /// Creates a context.
    ///
    /// - Parameters:
    ///   - country: The buyer's country.
    ///   - language: The content language.
    ///   - visitorConsent: The buyer's tracking consent, `nil` by default.
    public init(country: CountryCode, language: LanguageCode, visitorConsent: VisitorConsent? = nil) {
        self.country = country
        self.language = language
        self.visitorConsent = visitorConsent
    }

    /// The home market: Germany in German, without a consent statement.
    public static let germany = StorefrontContext(country: .de, language: .de)

    /// The directive to inject into an operation, for example:
    ///
    ///     @inContext(country: DE, language: PT_PT,
    ///                visitorConsent: {analytics: false, preferences: true, marketing: false, saleOfData: false})
    ///
    /// (rendered on one line).
    ///
    /// Codes that are not valid GraphQL enum values (see `CountryCode.isValidGraphQLEnumValue`)
    /// are left out rather than written into the document, so Shopify falls back to its default
    /// for that argument. `visitorConsent` is left out when it is `nil` or states nothing.
    /// The result is `@inContext` without arguments only if every part was left out.
    public var directive: String {
        var arguments: [String] = []
        if country.isValidGraphQLEnumValue {
            arguments.append("country: \(country.rawValue)")
        }
        if language.isValidGraphQLEnumValue {
            arguments.append("language: \(language.rawValue)")
        }
        if let consent = visitorConsent?.graphQLInputObject {
            arguments.append("visitorConsent: \(consent)")
        }
        guard !arguments.isEmpty else { return "@inContext" }
        return "@inContext(\(arguments.joined(separator: ", ")))"
    }

    /// A copy with `visitorConsent` replaced.
    public func with(visitorConsent: VisitorConsent?) -> StorefrontContext {
        var copy = self
        copy.visitorConsent = visitorConsent
        return copy
    }
}

// MARK: - VisitorConsent

/// The `VisitorConsent` input of the Storefront `@inContext` directive (API 2025-10 and later).
///
/// `nil` fields are not sent, which leaves the decision to Shopify's defaults for the market.
public struct VisitorConsent: Sendable, Hashable, Codable {
    /// Consent to analytics.
    public var analytics: Bool?
    /// Consent to preference cookies (remembering language and market).
    public var preferences: Bool?
    /// Consent to marketing.
    public var marketing: Bool?
    /// Consent to the sale or sharing of personal data.
    public var saleOfData: Bool?

    /// Creates a consent statement. Every field defaults to `nil` (not stated).
    public init(analytics: Bool? = nil, preferences: Bool? = nil, marketing: Bool? = nil, saleOfData: Bool? = nil) {
        self.analytics = analytics
        self.preferences = preferences
        self.marketing = marketing
        self.saleOfData = saleOfData
    }

    /// Maps the app's privacy choices to Shopify's consent categories.
    ///
    /// - `analytics` follows the user's analytics choice (off until they opt in).
    /// - `preferences` is always `true`: remembering the chosen language and market is needed
    ///   for the store to work and is not tracking.
    /// - `marketing` and `saleOfData` are always `false`: the app has no advertising and never
    ///   sells or shares data.
    public init(privacyConsent: PrivacyConsent) {
        self.init(analytics: privacyConsent.analytics, preferences: true, marketing: false, saleOfData: false)
    }

    /// The GraphQL input object literal, e.g. `{analytics: false, preferences: true}`, or `nil`
    /// when no field is set.
    public var graphQLInputObject: String? {
        let fields: [(String, Bool?)] = [
            ("analytics", analytics),
            ("preferences", preferences),
            ("marketing", marketing),
            ("saleOfData", saleOfData),
        ]
        let rendered = fields.compactMap { name, value in value.map { "\(name): \($0)" } }
        guard !rendered.isEmpty else { return nil }
        return "{\(rendered.joined(separator: ", "))}"
    }
}

// MARK: - ContextInjectionError

/// Why `ContextInjector.inject(_:into:)` could not place a directive.
///
/// Every case indicates a programming error in an operation document; all shipped documents
/// are covered by unit tests.
public enum ContextInjectionError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The document contains no query or mutation (only fragments, a subscription, or nothing).
    case noOperation
    /// The operation already carries an `@inContext` directive.
    case alreadyHasInContext
    /// The document defines more than one operation, so the target is ambiguous.
    case multipleOperations
    /// The document is not syntactically valid GraphQL (for example an unterminated string or
    /// unbalanced brackets).
    case malformedDocument

    /// A short English description for logs.
    public var description: String {
        switch self {
        case .noOperation: "The document contains no query or mutation."
        case .alreadyHasInContext: "The operation already has an @inContext directive."
        case .multipleOperations: "The document contains more than one operation."
        case .malformedDocument: "The document is not valid GraphQL."
        }
    }
}

// MARK: - ContextInjector

/// Inserts a directive such as `@inContext(...)` into the single operation of a GraphQL document.
///
/// The injector tokenizes the document (so `#` comments, string and block string literals
/// never confuse it), skips fragment definitions, finds the one `query` or `mutation`, skips its
/// optional name, variable definitions (including default values containing `(`, `{` or `#`)
/// and existing directives, and inserts the directive right before the selection set:
///
/// ```swift
/// try ContextInjector.inject("@inContext(country: DE)", into: "query Shop { shop { name } }")
/// // "query Shop @inContext(country: DE) { shop { name } }"
/// ```
///
/// An anonymous shorthand query (`{ shop { name } }`) becomes `query @inContext(...) { ... }`.
public enum ContextInjector {
    /// Returns `document` with `directive` inserted before the selection set of its operation.
    ///
    /// - Parameters:
    ///   - directive: The directive text, e.g. `StorefrontContext.directive`. A blank directive
    ///     returns `document` unchanged.
    ///   - document: A GraphQL document with exactly one query or mutation.
    /// - Throws: `ContextInjectionError`.
    public static func inject(_ directive: String, into document: String) throws -> String {
        let directive = directive.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directive.isEmpty else { return document }

        var bytes = Array(document.utf8)
        var locator = OperationLocator(bytes: bytes)
        let target = try locator.locate()

        let insertion: String
        switch target.style {
        case .shorthand:
            insertion = "query \(directive) "
        case .keyword:
            let previous = target.selectionSetStart > 0 ? bytes[target.selectionSetStart - 1] : UInt8(ascii: " ")
            let separator = GraphQLLexer.isWhitespace(previous) ? "" : " "
            insertion = "\(separator)\(directive) "
        }
        bytes.insert(contentsOf: Array(insertion.utf8), at: target.selectionSetStart)
        return String(decoding: bytes, as: UTF8.self)
    }
}

// MARK: - Operation locator

/// Finds the selection set of the single operation of a document.
private struct OperationLocator {
    enum Style {
        /// `{ ... }` without a keyword.
        case shorthand
        /// `query ...` or `mutation ...`.
        case keyword
    }

    struct Target {
        let style: Style
        let selectionSetStart: Int
    }

    private struct Operation {
        let keyword: String
        let style: Style
        let selectionSetStart: Int
        let hasInContext: Bool
    }

    private var lexer: GraphQLLexer

    init(bytes: [UInt8]) {
        lexer = GraphQLLexer(bytes: bytes)
    }

    mutating func locate() throws -> Target {
        var operations: [Operation] = []

        while let token = try lexer.next() {
            switch token.kind {
            case .punctuator(UInt8(ascii: "{")):
                operations.append(
                    Operation(keyword: "query", style: .shorthand, selectionSetStart: token.start, hasInContext: false)
                )
                try skipBalanced(open: UInt8(ascii: "{"), close: UInt8(ascii: "}"))
            case .name:
                let keyword = lexer.text(of: token)
                switch keyword {
                case "query", "mutation", "subscription":
                    try operations.append(parseOperation(keyword: keyword))
                case "fragment":
                    try skipFragment()
                default:
                    throw ContextInjectionError.malformedDocument
                }
            default:
                throw ContextInjectionError.malformedDocument
            }
        }

        guard !operations.isEmpty else { throw ContextInjectionError.noOperation }
        guard operations.count == 1, let operation = operations.first else {
            throw ContextInjectionError.multipleOperations
        }
        guard operation.keyword != "subscription" else { throw ContextInjectionError.noOperation }
        guard !operation.hasInContext else { throw ContextInjectionError.alreadyHasInContext }
        return Target(style: operation.style, selectionSetStart: operation.selectionSetStart)
    }

    /// Parses `Name? VariableDefinitions? Directives? SelectionSet` after the keyword.
    private mutating func parseOperation(keyword: String) throws -> Operation {
        var token = try requireToken()
        if token.kind == .name {
            token = try requireToken()
        }
        if token.kind == .punctuator(UInt8(ascii: "(")) {
            try skipBalanced(open: UInt8(ascii: "("), close: UInt8(ascii: ")"))
            token = try requireToken()
        }
        var hasInContext = false
        while token.kind == .punctuator(UInt8(ascii: "@")) {
            let name = try requireToken()
            guard name.kind == .name else { throw ContextInjectionError.malformedDocument }
            if lexer.text(of: name) == "inContext" {
                hasInContext = true
            }
            token = try requireToken()
            if token.kind == .punctuator(UInt8(ascii: "(")) {
                try skipBalanced(open: UInt8(ascii: "("), close: UInt8(ascii: ")"))
                token = try requireToken()
            }
        }
        guard token.kind == .punctuator(UInt8(ascii: "{")) else { throw ContextInjectionError.malformedDocument }
        let start = token.start
        try skipBalanced(open: UInt8(ascii: "{"), close: UInt8(ascii: "}"))
        return Operation(keyword: keyword, style: .keyword, selectionSetStart: start, hasInContext: hasInContext)
    }

    /// Skips `Name on Type Directives? SelectionSet` after the `fragment` keyword.
    private mutating func skipFragment() throws {
        let name = try requireToken()
        let on = try requireToken()
        let type = try requireToken()
        guard name.kind == .name, on.kind == .name, lexer.text(of: on) == "on", type.kind == .name else {
            throw ContextInjectionError.malformedDocument
        }
        var token = try requireToken()
        while token.kind == .punctuator(UInt8(ascii: "@")) {
            guard try requireToken().kind == .name else { throw ContextInjectionError.malformedDocument }
            token = try requireToken()
            if token.kind == .punctuator(UInt8(ascii: "(")) {
                try skipBalanced(open: UInt8(ascii: "("), close: UInt8(ascii: ")"))
                token = try requireToken()
            }
        }
        guard token.kind == .punctuator(UInt8(ascii: "{")) else { throw ContextInjectionError.malformedDocument }
        try skipBalanced(open: UInt8(ascii: "{"), close: UInt8(ascii: "}"))
    }

    /// Consumes tokens until the bracket opened just before the call is closed.
    private mutating func skipBalanced(open: UInt8, close: UInt8) throws {
        var depth = 1
        while depth > 0 {
            let token = try requireToken()
            if token.kind == .punctuator(open) {
                depth += 1
            } else if token.kind == .punctuator(close) {
                depth -= 1
            }
        }
    }

    private mutating func requireToken() throws -> GraphQLLexer.Token {
        guard let token = try lexer.next() else { throw ContextInjectionError.malformedDocument }
        return token
    }
}

// MARK: - Lexer

/// A minimal GraphQL lexer over UTF-8 bytes (GraphQL spec, section 2.1).
///
/// It produces names, punctuators, strings and numbers and drops ignored tokens (white space,
/// line terminators, commas, the byte order mark and comments). Non-ASCII bytes are only
/// allowed inside strings and comments, where the lexer never interprets them.
struct GraphQLLexer {
    enum Kind: Equatable {
        case name
        case punctuator(UInt8)
        case spread
        case string
        case number
    }

    struct Token {
        let kind: Kind
        let start: Int
        let end: Int
    }

    private let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
    }

    func text(of token: Token) -> String {
        String(decoding: bytes[token.start..<token.end], as: UTF8.self)
    }

    /// Returns the next significant token, or `nil` at the end of the document.
    mutating func next() throws -> Token? {
        skipIgnored()
        guard index < bytes.count else { return nil }
        let start = index
        let byte = bytes[index]

        switch byte {
        case UInt8(ascii: "\""):
            try scanString()
            return Token(kind: .string, start: start, end: index)
        case UInt8(ascii: "."):
            guard index + 2 < bytes.count, bytes[index + 1] == byte, bytes[index + 2] == byte else {
                throw ContextInjectionError.malformedDocument
            }
            index += 3
            return Token(kind: .spread, start: start, end: index)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            index += 1
            while index < bytes.count, Self.isNumberContinuation(bytes[index]) {
                index += 1
            }
            return Token(kind: .number, start: start, end: index)
        case _ where Self.isNameStart(byte):
            index += 1
            while index < bytes.count, Self.isNameContinuation(bytes[index]) {
                index += 1
            }
            return Token(kind: .name, start: start, end: index)
        case _ where Self.punctuators.contains(byte):
            index += 1
            return Token(kind: .punctuator(byte), start: start, end: index)
        default:
            throw ContextInjectionError.malformedDocument
        }
    }

    // MARK: Private

    private static let punctuators: Set<UInt8> = Set("!$&():=@[]{|}".utf8)

    private static func isNameStart(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || byte == UInt8(ascii: "_")
    }

    private static func isNameContinuation(_ byte: UInt8) -> Bool {
        isNameStart(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private static func isNumberContinuation(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            || byte == UInt8(ascii: ".")
            || byte == UInt8(ascii: "e")
            || byte == UInt8(ascii: "E")
            || byte == UInt8(ascii: "+")
            || byte == UInt8(ascii: "-")
    }

    /// Skips white space, line terminators, commas, byte order marks and comments.
    private mutating func skipIgnored() {
        while index < bytes.count {
            let byte = bytes[index]
            if Self.isWhitespace(byte) || byte == UInt8(ascii: ",") {
                index += 1
            } else if byte == 0xEF, index + 2 < bytes.count, bytes[index + 1] == 0xBB, bytes[index + 2] == 0xBF {
                index += 3
            } else if byte == UInt8(ascii: "#") {
                while index < bytes.count, bytes[index] != UInt8(ascii: "\n"), bytes[index] != UInt8(ascii: "\r") {
                    index += 1
                }
            } else {
                return
            }
        }
    }

    /// Scans a string or block string starting at the opening quote.
    private mutating func scanString() throws {
        let quote = UInt8(ascii: "\"")
        let backslash = UInt8(ascii: "\\")
        if index + 2 < bytes.count, bytes[index + 1] == quote, bytes[index + 2] == quote {
            // Block string: ends at the next `"""` that is not escaped as `\"""`.
            index += 3
            while index < bytes.count {
                if bytes[index] == backslash, index + 3 < bytes.count,
                   bytes[index + 1] == quote, bytes[index + 2] == quote, bytes[index + 3] == quote
                {
                    index += 4
                } else if bytes[index] == quote, index + 2 < bytes.count,
                          bytes[index + 1] == quote, bytes[index + 2] == quote
                {
                    index += 3
                    return
                } else {
                    index += 1
                }
            }
            throw ContextInjectionError.malformedDocument
        }

        index += 1
        while index < bytes.count {
            switch bytes[index] {
            case backslash:
                index += 2
            case quote:
                index += 1
                return
            case UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                throw ContextInjectionError.malformedDocument
            default:
                index += 1
            }
        }
        throw ContextInjectionError.malformedDocument
    }
}
