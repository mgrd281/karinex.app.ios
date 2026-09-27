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

/// Removes customer-related data from a response before it is stored as a fixture.
///
/// None of the fixtures of Phase 0 contain customer data (the cart fixture has no cart), but
/// the recorder never relies on that:
/// - GIDs of carts, cart lines, checkouts, customers and addresses (which carry cart tokens or
///   personal identifiers) become `gid://shopify/<Type>/anonymized`, also inside messages,
/// - `checkoutUrl` values keep only scheme and host: `https://<host>/cart/c/anonymized`,
/// - string values of personal fields (`email`, `firstName`, `address1`, ...) become `anonymized`.
///
/// Product, variant, collection and image data, cursors and prices are public catalog data and
/// stay untouched.
public enum FixtureAnonymizer {
    /// The replacement text.
    public static let placeholder = "anonymized"

    /// Field names whose string values are personal data.
    public static let personalFieldNames: Set<String> = [
        "email", "emailAddress", "firstName", "lastName", "displayName", "address1", "address2", "zip",
        "company", "customerAccessToken", "note",
    ]

    /// GID resource types that carry cart tokens or personal identifiers.
    public static let sensitiveGIDTypes = ["CartLine", "Cart", "Checkout", "CustomerAddress", "Customer", "MailingAddress"]

    /// Returns the anonymized object and the JSON paths (e.g. `data.cartCreate.cart.id`) of
    /// every value that was changed.
    public static func anonymize(_ object: [String: JSONValue]) -> (object: [String: JSONValue], changedPaths: [String]) {
        var changedPaths: [String] = []
        guard case let .object(result) = anonymize(value: .object(object), key: nil, path: "", changedPaths: &changedPaths) else {
            return (object, changedPaths)
        }
        return (result, changedPaths)
    }

    // MARK: Private

    /// Matches sensitive GIDs. Built per use: `NSRegularExpression` is not `Sendable` on every
    /// platform, and the recorder anonymizes only a handful of responses.
    private static func makeGIDExpression() -> NSRegularExpression? {
        try? NSRegularExpression(pattern: #"gid://shopify/("# + sensitiveGIDTypes.joined(separator: "|") + #")/[^\s"'<>,;)\]}]+"#)
    }

    private static func anonymize(value: JSONValue, key: String?, path: String, changedPaths: inout [String]) -> JSONValue {
        switch value {
        case let .object(members):
            var result: [String: JSONValue] = [:]
            for (childKey, childValue) in members {
                let childPath = path.isEmpty ? childKey : "\(path).\(childKey)"
                result[childKey] = anonymize(value: childValue, key: childKey, path: childPath, changedPaths: &changedPaths)
            }
            return .object(result)
        case let .array(elements):
            return .array(elements.enumerated().map { index, element in
                anonymize(value: element, key: key, path: "\(path)[\(index)]", changedPaths: &changedPaths)
            })
        case let .string(string):
            let anonymized = anonymize(string: string, key: key)
            if anonymized != string {
                changedPaths.append(path)
            }
            return .string(anonymized)
        case .null, .bool, .integer, .double:
            return value
        }
    }

    private static func anonymize(string: String, key: String?) -> String {
        if let key, personalFieldNames.contains(key) {
            return placeholder
        }
        if key == "checkoutUrl", let url = URL(string: string), let scheme = url.scheme, let host = url.host {
            return "\(scheme)://\(host)/cart/c/\(placeholder)"
        }
        guard string.contains("gid://shopify/"), let gidExpression = makeGIDExpression() else { return string }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return gidExpression.stringByReplacingMatches(
            in: string,
            options: [],
            range: range,
            withTemplate: "gid://shopify/$1/\(placeholder)"
        )
    }
}
