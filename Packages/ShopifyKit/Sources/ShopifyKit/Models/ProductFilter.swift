import Foundation

// MARK: - ProductFilter

/// A product filter the store offers for a collection or search (Storefront `Filter`), as
/// configured in Shopify's Search & Discovery app, e.g. "Verfügbarkeit" or "Preis".
///
/// The UI builds its filter sheet from these values and sends the chosen values' `input` back
/// unchanged, so it never needs to know how a filter works.
public struct ProductFilter: Sendable, Hashable, Codable, Identifiable {
    /// The filter ID, e.g. `filter.v.availability`.
    public let id: String
    /// The localized label, e.g. `Verfügbarkeit`.
    public let label: String
    /// The filter type: `LIST`, `PRICE_RANGE` or `BOOLEAN`. Kept as a string so new types
    /// never break decoding.
    public let type: String
    /// The values a customer can choose.
    public let values: [ProductFilterValue]

    /// Creates a filter.
    public init(id: String, label: String, type: String, values: [ProductFilterValue]) {
        self.id = id
        self.label = label
        self.type = type
        self.values = values
    }

    /// The Storefront `FilterType` value of a price range filter.
    public static let priceRangeType = "PRICE_RANGE"

    /// Whether this is a price range filter, whose single value carries the store's price
    /// bounds and is applied with `ProductFilterInput.price(minimum:maximum:)`.
    public var isPriceRange: Bool {
        type == Self.priceRangeType
    }
}

// MARK: - ProductFilterValue

/// One choosable value of a `ProductFilter` (Storefront `FilterValue`).
public struct ProductFilterValue: Sendable, Hashable, Codable, Identifiable {
    /// The value ID, e.g. `filter.v.availability.1`.
    public let id: String
    /// The localized label, e.g. `Auf Lager`.
    public let label: String
    /// How many products match the value in the current result.
    public let count: Int
    /// The filter input to send back to apply this value.
    public let input: ProductFilterInput

    /// Creates a filter value.
    public init(id: String, label: String, count: Int, input: ProductFilterInput) {
        self.id = id
        self.label = label
        self.count = count
        self.input = input
    }
}

// MARK: - ProductFilterInput

/// A Storefront `ProductFilter` input value, kept as the JSON text Shopify supplies in
/// `FilterValue.input`, e.g. `{"available":true}`.
///
/// Encoding (as GraphQL variables) writes the JSON **object**, not a string, so the input goes
/// back to Shopify exactly as it was received. Decoding accepts both the JSON text (as the API
/// returns it) and an object (as this type encodes itself). Two inputs are equal when their
/// JSON is equal, regardless of key order or formatting.
public struct ProductFilterInput: Sendable, Hashable, Codable {
    /// The JSON text of the input object, as received from Shopify.
    public let rawJSON: String
    /// The parsed JSON, or `nil` when `rawJSON` is not a JSON object.
    private let value: GraphQLJSONValue?

    /// Wraps Shopify's JSON text. Text that is not a JSON object is kept, but encoding it
    /// throws `EncodingError.invalidValue`.
    public init(rawJSON: String) {
        self.rawJSON = rawJSON
        let parsed = GraphQLJSONValue(jsonText: rawJSON)
        if case .object? = parsed {
            value = parsed
        } else {
            value = nil
        }
    }

    /// The input that keeps only products that are available (`true`) or sold out (`false`).
    public static func available(_ isAvailable: Bool) -> ProductFilterInput {
        ProductFilterInput(value: .object(["available": .bool(isAvailable)]))
    }

    /// The input that keeps only products whose price lies in the range. `nil` bounds are
    /// left out (open range).
    public static func price(minimum: Decimal?, maximum: Decimal?) -> ProductFilterInput {
        var bounds: [String: GraphQLJSONValue] = [:]
        if let minimum {
            bounds["min"] = .number(minimum)
        }
        if let maximum {
            bounds["max"] = .number(maximum)
        }
        return ProductFilterInput(value: .object(["price": .object(bounds)]))
    }

    /// The lower and upper bound of a price input such as `{"price":{"min":0,"max":239.9}}`,
    /// or `nil` when this is not a price input. Price range filters report the store's price
    /// bounds this way.
    public var priceBounds: (minimum: Decimal?, maximum: Decimal?)? {
        guard case let .object(members)? = value, case let .object(price)? = members["price"] else { return nil }
        return (price["min"]?.decimalValue, price["max"]?.decimalValue)
    }

    private init(value: GraphQLJSONValue) {
        self.value = value
        rawJSON = value.canonicalText
    }

    /// The canonical JSON text (sorted keys, no spaces) used for equality and hashing.
    private var canonicalText: String {
        value?.canonicalText ?? rawJSON
    }

    // MARK: Equatable and Hashable

    /// Equal when the JSON is equal (key order and formatting do not matter).
    public static func == (lhs: ProductFilterInput, rhs: ProductFilterInput) -> Bool {
        lhs.canonicalText == rhs.canonicalText
    }

    /// Hashes the canonical JSON.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(canonicalText)
    }

    // MARK: Codable

    /// Decodes JSON text (the `JSON` scalar of `FilterValue.input`) or a JSON object.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self.init(rawJSON: text)
        } else {
            let object = try container.decode(GraphQLJSONValue.self)
            guard case .object = object else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "A product filter input must be a JSON object.")
            }
            self.init(value: object)
        }
    }

    /// Encodes the JSON object.
    ///
    /// - Throws: `EncodingError.invalidValue` when `rawJSON` is not a JSON object.
    public func encode(to encoder: any Encoder) throws {
        guard let value else {
            throw EncodingError.invalidValue(
                rawJSON,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "The product filter input is not a JSON object.")
            )
        }
        try value.encode(to: encoder)
    }
}

// MARK: - GraphQLJSONValue

/// A JSON value for GraphQL `JSON` scalars that must be sent back as structured input.
///
/// Numbers are kept as `Decimal`, so amounts such as `239.9` survive a round trip without
/// binary floating point artifacts.
enum GraphQLJSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([GraphQLJSONValue])
    case object([String: GraphQLJSONValue])

    /// Parses JSON text; `nil` when it is not valid JSON.
    init?(jsonText: String) {
        guard let value = try? JSONDecoder().decode(GraphQLJSONValue.self, from: Data(jsonText.utf8)) else { return nil }
        self = value
    }

    /// Decodes any JSON value. Booleans are tried before numbers.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Decimal.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([GraphQLJSONValue].self) {
            self = .array(array)
        } else {
            self = try .object(container.decode([String: GraphQLJSONValue].self))
        }
    }

    /// Encodes the value as JSON.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// The number as a `Decimal`, or `nil` for other values.
    var decimalValue: Decimal? {
        if case let .number(number) = self {
            return number
        }
        return nil
    }

    /// Compact JSON with keys sorted by their Unicode scalars, used as an identity.
    var canonicalText: String {
        switch self {
        case .null:
            return "null"
        case let .bool(value):
            return value ? "true" : "false"
        case let .number(value):
            return value.description
        case let .string(value):
            return Self.quoted(value)
        case let .array(values):
            return "[" + values.map(\.canonicalText).joined(separator: ",") + "]"
        case let .object(members):
            let keys = members.keys.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
            return "{" + keys.map { Self.quoted($0) + ":" + (members[$0] ?? .null).canonicalText }.joined(separator: ",") + "}"
        }
    }

    private static func quoted(_ string: String) -> String {
        var output = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                output += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}
