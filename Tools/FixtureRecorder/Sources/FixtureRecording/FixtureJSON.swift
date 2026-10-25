import Foundation

// MARK: - JSONValue

/// A JSON document as a value, with a deterministic pretty printer.
///
/// Fixture files must be byte-identical whether they are recorded on macOS or Linux, so the
/// recorder does not use `JSONSerialization`'s formatting (which differs between platforms,
/// for example for empty arrays). Output: two-space indentation, `"key": value`, keys sorted
/// by Unicode scalar values, `[]` and `{}` for empty containers, slashes and non-ASCII
/// characters unescaped, and a trailing newline.
public enum JSONValue: Sendable, Hashable, Codable {
    /// `null`.
    case null
    /// `true` or `false`.
    case bool(Bool)
    /// An integer number.
    case integer(Int64)
    /// A non-integer number.
    case double(Double)
    /// A string.
    case string(String)
    /// An array.
    case array([JSONValue])
    /// An object.
    case object([String: JSONValue])

    /// Why a body could not be read as a fixture.
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// The body is not a JSON object.
        case notAJSONObject

        /// A one-line English message.
        public var description: String {
            "The response body is not a JSON object."
        }
    }

    /// Parses `data`, which must contain a JSON object.
    public static func parseObject(_ data: Data) throws -> [String: JSONValue] {
        guard case let .object(object) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw Failure.notAJSONObject
        }
        return object
    }

    /// Encodes an `Encodable` value into a `JSONValue`.
    public static func encoding(_ value: some Encodable) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
    }

    // MARK: Codable

    /// Decodes any JSON value. Booleans are tried before numbers so `true` never becomes `1`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let integer = try? container.decode(Int64.self) {
            self = .integer(integer)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = try .object(container.decode([String: JSONValue].self))
        }
    }

    /// Encodes the value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    // MARK: Pretty printing

    /// The pretty-printed document with a trailing newline, as UTF-8.
    public func prettyPrintedData() -> Data {
        var output = ""
        write(to: &output, indentation: 0)
        output += "\n"
        return Data(output.utf8)
    }

    private func write(to output: inout String, indentation: Int) {
        switch self {
        case .null:
            output += "null"
        case let .bool(value):
            output += value ? "true" : "false"
        case let .integer(value):
            output += String(value)
        case let .double(value):
            output += value.isFinite ? String(value) : "null"
        case let .string(value):
            Self.writeString(value, to: &output)
        case let .array(values):
            guard !values.isEmpty else {
                output += "[]"
                return
            }
            output += "[\n"
            for (index, value) in values.enumerated() {
                output += String(repeating: "  ", count: indentation + 1)
                value.write(to: &output, indentation: indentation + 1)
                output += index < values.count - 1 ? ",\n" : "\n"
            }
            output += String(repeating: "  ", count: indentation) + "]"
        case let .object(members):
            guard !members.isEmpty else {
                output += "{}"
                return
            }
            output += "{\n"
            let keys = members.keys.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
            for (index, key) in keys.enumerated() {
                output += String(repeating: "  ", count: indentation + 1)
                Self.writeString(key, to: &output)
                output += ": "
                members[key, default: .null].write(to: &output, indentation: indentation + 1)
                output += index < keys.count - 1 ? ",\n" : "\n"
            }
            output += String(repeating: "  ", count: indentation) + "}"
        }
    }

    private static func writeString(_ string: String, to output: inout String) {
        output += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case _ where scalar.value < 0x20:
                output += "\\u" + String(format: "%04x", scalar.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}

// MARK: - FixtureAnonymizer

/// Removes cart tokens and customer data from a response (or from request variables) before
/// it is stored as a fixture, keeping the shape of every value:
/// - GIDs of carts, checkouts, customers and addresses keep their type, but their ID and
///   every query value become `REDACTED`: `gid://shopify/Cart/REDACTED?key=REDACTED`, also
///   inside messages and warning targets,
/// - cart line GIDs keep their line ID (which is not secret on its own) while the cart token
///   in their query becomes `REDACTED`: `gid://shopify/CartLine/<line>?cart=REDACTED`,
/// - `checkoutUrl` values keep scheme, host and path shape, with the cart token and every
///   query value replaced: `https://www.karinex.de/cart/c/REDACTED?key=REDACTED&_cs=REDACTED`,
/// - every other occurrence of a token found this way (8 characters or longer) is replaced
///   too, wherever it appears,
/// - non-empty string values of personal fields (`email`, `firstName`, `address1`, ...)
///   become `REDACTED`.
///
/// Product, variant, collection and image data, cursors and prices are public catalog data and
/// stay untouched.
public enum FixtureAnonymizer {
    /// The replacement text.
    public static let placeholder = "REDACTED"

    /// Field names whose string values are personal data.
    public static let personalFieldNames: Set<String> = [
        "email", "emailAddress", "firstName", "lastName", "displayName", "address1", "address2", "zip",
        "company", "customerAccessToken", "note", "phone",
    ]

    /// GID resource types that carry cart tokens or personal identifiers.
    public static let sensitiveGIDTypes = ["CartLine", "Cart", "Checkout", "CustomerAddress", "Customer", "MailingAddress"]

    /// GID types whose own ID is kept; only their query values are secret.
    public static let typesWithPublicID: Set<String> = ["CartLine"]

    /// Secrets shorter than this are only replaced structurally (inside GIDs and checkout
    /// URLs), never by a global text search, so short values cannot corrupt unrelated text.
    public static let minimumGlobalSecretLength = 8

    /// Returns the anonymized object and the JSON paths (e.g. `data.cartCreate.cart.id`) of
    /// every value that was changed.
    public static func anonymize(_ object: [String: JSONValue]) -> (object: [String: JSONValue], changedPaths: [String]) {
        var secrets = Set<String>()
        collectSecrets(in: .object(object), key: nil, into: &secrets)
        let orderedSecrets = secrets.filter { $0.count >= minimumGlobalSecretLength }.sorted { $0.count > $1.count }

        var changedPaths: [String] = []
        guard case let .object(result) = anonymize(
            value: .object(object),
            key: nil,
            path: "",
            secrets: orderedSecrets,
            changedPaths: &changedPaths
        ) else {
            return (object, changedPaths)
        }
        return (result, changedPaths)
    }

    // MARK: Secrets

    /// Matches sensitive GIDs. Built per use: `NSRegularExpression` is not `Sendable` on every
    /// platform, and the recorder anonymizes only a few dozen bodies.
    private static func makeGIDExpression() -> NSRegularExpression? {
        try? NSRegularExpression(pattern: #"gid://shopify/("# + sensitiveGIDTypes
            .joined(separator: "|") + #")/([^\s"'<>,;)\]}?]+)(\?[^\s"'<>,;)\]}]*)?"#)
    }

    private static func collectSecrets(in value: JSONValue, key: String?, into secrets: inout Set<String>) {
        switch value {
        case let .object(members):
            for (childKey, child) in members {
                collectSecrets(in: child, key: childKey, into: &secrets)
            }
        case let .array(elements):
            for element in elements {
                collectSecrets(in: element, key: key, into: &secrets)
            }
        case let .string(string):
            for match in gidMatches(in: string) {
                if !typesWithPublicID.contains(match.type) {
                    secrets.insert(match.id)
                }
                secrets.formUnion(queryValues(match.query))
            }
            if key == "checkoutUrl", let components = URLComponents(string: string) {
                if let token = checkoutToken(in: components.path) {
                    secrets.insert(token)
                }
                secrets.formUnion((components.percentEncodedQueryItems ?? []).compactMap(\.value))
            }
        case .null, .bool, .integer, .double:
            break
        }
    }

    private struct GIDMatch {
        let range: Range<String.Index>
        let type: String
        let id: String
        let query: String?
    }

    private static func gidMatches(in string: String) -> [GIDMatch] {
        guard string.contains("gid://shopify/"), let expression = makeGIDExpression() else { return [] }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.matches(in: string, range: range).compactMap { match in
            guard let whole = Range(match.range, in: string),
                  let type = Range(match.range(at: 1), in: string),
                  let id = Range(match.range(at: 2), in: string)
            else { return nil }
            let query = Range(match.range(at: 3), in: string).map { String(string[$0].dropFirst()) }
            return GIDMatch(range: whole, type: String(string[type]), id: String(string[id]), query: query)
        }
    }

    /// The values of a query string such as `key=abc&cart=def`.
    private static func queryValues(_ query: String?) -> [String] {
        guard let query else { return [] }
        return query.split(separator: "&").compactMap { pair in
            guard let equals = pair.firstIndex(of: "=") else { return nil }
            let value = pair[pair.index(after: equals)...]
            return value.isEmpty ? nil : String(value)
        }
    }

    /// `name=REDACTED` for every `name=value` pair of a query string.
    private static func redactedQuery(_ query: String) -> String {
        query.split(separator: "&", omittingEmptySubsequences: false).map { pair in
            guard let equals = pair.firstIndex(of: "=") else { return String(pair) }
            return String(pair[..<equals]) + "=" + placeholder
        }.joined(separator: "&")
    }

    /// The cart token of a checkout URL path such as `/cart/c/<token>`.
    private static func checkoutToken(in path: String) -> String? {
        let components = path.split(separator: "/")
        guard let index = components.firstIndex(of: "c"), index > 0, components[index - 1] == "cart",
              index + 1 < components.count
        else { return nil }
        return String(components[index + 1])
    }

    // MARK: Rewriting

    private static func anonymize(
        value: JSONValue,
        key: String?,
        path: String,
        secrets: [String],
        changedPaths: inout [String]
    ) -> JSONValue {
        switch value {
        case let .object(members):
            var result: [String: JSONValue] = [:]
            for (childKey, childValue) in members {
                let childPath = path.isEmpty ? childKey : "\(path).\(childKey)"
                result[childKey] = anonymize(
                    value: childValue,
                    key: childKey,
                    path: childPath,
                    secrets: secrets,
                    changedPaths: &changedPaths
                )
            }
            return .object(result)
        case let .array(elements):
            return .array(elements.enumerated().map { index, element in
                anonymize(value: element, key: key, path: "\(path)[\(index)]", secrets: secrets, changedPaths: &changedPaths)
            })
        case let .string(string):
            let anonymized = anonymize(string: string, key: key, secrets: secrets)
            if anonymized != string {
                changedPaths.append(path)
            }
            return .string(anonymized)
        case .null, .bool, .integer, .double:
            return value
        }
    }

    private static func anonymize(string: String, key: String?, secrets: [String]) -> String {
        if let key, personalFieldNames.contains(key) {
            return string.isEmpty ? string : placeholder
        }
        var result = string
        if key == "checkoutUrl", var components = URLComponents(string: result) {
            if let token = checkoutToken(in: components.path) {
                components.path = components.path.replacingOccurrences(of: "/c/\(token)", with: "/c/\(placeholder)")
            }
            if let items = components.percentEncodedQueryItems {
                components.percentEncodedQueryItems = items.map { URLQueryItem(name: $0.name, value: $0.value == nil ? nil : placeholder) }
            }
            result = components.string ?? result
        }
        for match in gidMatches(in: result).reversed() {
            var replacement = "gid://shopify/\(match.type)/" + (typesWithPublicID.contains(match.type) ? match.id : placeholder)
            if let query = match.query {
                replacement += "?" + redactedQuery(query)
            }
            result.replaceSubrange(match.range, with: replacement)
        }
        for secret in secrets where result.contains(secret) {
            result = result.replacingOccurrences(of: secret, with: placeholder)
        }
        return result
    }
}
