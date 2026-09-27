import Foundation

// MARK: - Metafield

/// A custom field of a Shopify resource (Storefront `Metafield`).
///
/// `value` is always a string; its meaning depends on `type` (for example `json`,
/// `date_time`, `rich_text_field` or `list.single_line_text_field`). Use `ProductMetafields`
/// for typed access.
public struct Metafield: Sendable, Hashable, Codable {
    /// The namespace, e.g. `karinex`.
    public let namespace: String
    /// The key, e.g. `faq`.
    public let key: String
    /// The Shopify metafield type, e.g. `json`.
    public let type: String
    /// The raw value.
    public let value: String

    /// Creates a metafield.
    public init(namespace: String, key: String, type: String, value: String) {
        self.namespace = namespace
        self.key = key
        self.type = type
        self.value = value
    }

    /// The identifier of this metafield.
    public var identifier: MetafieldIdentifier {
        MetafieldIdentifier(namespace: namespace, key: key)
    }
}

// MARK: - MetafieldIdentifier

/// A namespace and key pair; encodes as the Storefront `HasMetafieldsIdentifier` input.
public struct MetafieldIdentifier: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The namespace, e.g. `karinex`.
    public let namespace: String
    /// The key, e.g. `faq`.
    public let key: String

    /// Creates an identifier.
    public init(namespace: String, key: String) {
        self.namespace = namespace
        self.key = key
    }

    /// `namespace.key`, e.g. `karinex.faq`.
    public var description: String {
        "\(namespace).\(key)"
    }
}

// MARK: - FAQEntry

/// One question and answer of the `karinex.faq` metafield.
public struct FAQEntry: Sendable, Hashable, Codable, Identifiable {
    /// The question.
    public let question: String
    /// The answer.
    public let answer: String

    /// Creates an entry.
    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }

    /// The question, unique within a parsed FAQ (duplicates are dropped when parsing).
    public var id: String {
        question
    }
}

// MARK: - MetafieldContent

/// The content of a text-like metafield, classified for rendering.
public enum MetafieldContent: Sendable, Hashable {
    /// Plain text.
    case plainText(String)
    /// HTML stored in a text field.
    case html(String)
    /// A Shopify rich text document (`rich_text_field`).
    case richText(RichTextNode)

    /// The content as plain text (tags are not stripped from `.html`).
    public var plainText: String {
        switch self {
        case let .plainText(text), let .html(text):
            text
        case let .richText(node):
            node.plainText
        }
    }
}

// MARK: - RichTextNode

/// A node of a Shopify rich text metafield value:
/// `{"type": "root", "children": [{"type": "paragraph", "children": [{"type": "text", "value": "..."}]}]}`.
///
/// Node types are `root`, `paragraph`, `heading` (with `level`), `list` (with `listType`
/// `ordered` or `unordered`), `list-item`, `link` (with `url` and `title`) and `text` (with
/// `value`, `bold`, `italic`). Unknown types decode too, so newer editor features never break
/// decoding.
public struct RichTextNode: Sendable, Hashable, Codable {
    /// The node type, e.g. `paragraph`.
    public let type: String
    /// The text of a `text` node.
    public let value: String?
    /// The level of a `heading` node (1 to 6).
    public let level: Int?
    /// `ordered` or `unordered` for a `list` node.
    public let listType: String?
    /// The target of a `link` node.
    public let url: String?
    /// The title of a `link` node.
    public let title: String?
    /// Whether a `text` node is bold.
    public let bold: Bool?
    /// Whether a `text` node is italic.
    public let italic: Bool?
    /// The child nodes.
    public let children: [RichTextNode]

    /// Creates a node.
    public init(
        type: String,
        value: String? = nil,
        level: Int? = nil,
        listType: String? = nil,
        url: String? = nil,
        title: String? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        children: [RichTextNode] = []
    ) {
        self.type = type
        self.value = value
        self.level = level
        self.listType = listType
        self.url = url
        self.title = title
        self.bold = bold
        self.italic = italic
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case type, value, level, listType, url, title, bold, italic, children
    }

    /// Decodes a node; a missing `children` member decodes as no children.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        level = try? container.decodeIfPresent(Int.self, forKey: .level)
        listType = try? container.decodeIfPresent(String.self, forKey: .listType)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        bold = try? container.decodeIfPresent(Bool.self, forKey: .bold)
        italic = try? container.decodeIfPresent(Bool.self, forKey: .italic)
        children = try container.decodeIfPresent([RichTextNode].self, forKey: .children) ?? []
    }

    /// The text content: inline nodes are concatenated, block nodes (paragraphs, headings,
    /// list items) are separated by line breaks.
    public var plainText: String {
        var lines: [String] = []
        var currentLine = ""
        collectText(into: &lines, currentLine: &currentLine)
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let blockTypes: Set<String> = ["root", "paragraph", "heading", "list", "list-item"]

    private func collectText(into lines: inout [String], currentLine: inout String) {
        if let value {
            currentLine += value
        }
        let isBlock = Self.blockTypes.contains(type)
        if isBlock, !currentLine.isEmpty {
            lines.append(currentLine)
            currentLine = ""
        }
        for child in children {
            child.collectText(into: &lines, currentLine: &currentLine)
        }
        if isBlock, !currentLine.isEmpty {
            lines.append(currentLine)
            currentLine = ""
        }
    }
}

// MARK: - ProductMetafields

/// Typed, failure-tolerant access to the product metafields the app uses.
///
/// Every accessor returns `nil` when the metafield is missing or its value cannot be parsed;
/// nothing here ever crashes on unexpected merchant data. Metafields are only readable with a
/// Storefront access token (tokenless requests get `ACCESS_DENIED`), so in tokenless mode every
/// accessor returns `nil`.
public struct ProductMetafields: Sendable, Hashable {
    // MARK: Identifiers

    /// The metafield identifiers of PROMPT section 5.1 plus the existing store keys.
    public enum Identifier {
        /// `karinex.faq`: JSON `[{question, answer}]` for the FAQ accordion.
        public static let faq = MetafieldIdentifier(namespace: "karinex", key: "faq")
        /// `karinex.lizenztyp`: license type (spec table).
        public static let licenseType = MetafieldIdentifier(namespace: "karinex", key: "lizenztyp")
        /// `karinex.architektur`: architecture, e.g. 64-bit (spec table).
        public static let architecture = MetafieldIdentifier(namespace: "karinex", key: "architektur")
        /// `karinex.geraeteanzahl`: number of devices (spec table).
        public static let deviceCount = MetafieldIdentifier(namespace: "karinex", key: "geraeteanzahl")
        /// `karinex.lieferform`: delivery form, download or USB (spec table).
        public static let deliveryForm = MetafieldIdentifier(namespace: "karinex", key: "lieferform")
        /// `karinex.aktivierungsart`: activation method (spec table).
        public static let activationMethod = MetafieldIdentifier(namespace: "karinex", key: "aktivierungsart")
        /// `karinex.sprachen`: languages (spec table).
        public static let languages = MetafieldIdentifier(namespace: "karinex", key: "sprachen")
        /// `karinex.support_status`: Microsoft support status (spec table).
        public static let supportStatus = MetafieldIdentifier(namespace: "karinex", key: "support_status")
        /// `custom.details_content`: rich text detail section (activation).
        public static let detailsContent = MetafieldIdentifier(namespace: "custom", key: "details_content")
        /// `custom.shipping_content`: rich text shipping section.
        public static let shippingContent = MetafieldIdentifier(namespace: "custom", key: "shipping_content")
        /// `custom.warranty_content`: rich text warranty section.
        public static let warrantyContent = MetafieldIdentifier(namespace: "custom", key: "warranty_content")
        /// `custom.mpn`: manufacturer part number (spec table).
        public static let mpn = MetafieldIdentifier(namespace: "custom", key: "mpn")
        /// `karinex.deal_ends_at`: `date_time` end of a deal, drives the countdown.
        public static let dealEndsAt = MetafieldIdentifier(namespace: "karinex", key: "deal_ends_at")
        /// `custom.angebotsende`: existing store key, `date_time` end of an offer.
        public static let offerEndsAt = MetafieldIdentifier(namespace: "custom", key: "angebotsende")
        /// `mm-google-shopping.mpn`: existing store key, MPN from the Google Shopping app.
        public static let googleShoppingMPN = MetafieldIdentifier(namespace: "mm-google-shopping", key: "mpn")
        /// `karinex.lowest_price_30d`: existing store key, lowest price of the last 30 days.
        public static let lowestPrice30Days = MetafieldIdentifier(namespace: "karinex", key: "lowest_price_30d")
    }

    /// Every identifier the product query requests when a token is configured.
    public static let allIdentifiers: [MetafieldIdentifier] = [
        Identifier.faq,
        Identifier.licenseType,
        Identifier.architecture,
        Identifier.deviceCount,
        Identifier.deliveryForm,
        Identifier.activationMethod,
        Identifier.languages,
        Identifier.supportStatus,
        Identifier.detailsContent,
        Identifier.shippingContent,
        Identifier.warrantyContent,
        Identifier.mpn,
        Identifier.dealEndsAt,
        Identifier.offerEndsAt,
        Identifier.googleShoppingMPN,
        Identifier.lowestPrice30Days,
    ]

    // MARK: Storage

    /// The metafields by identifier. When an identifier occurs twice, the first one wins.
    public let metafields: [MetafieldIdentifier: Metafield]

    /// Indexes `metafields` by identifier.
    public init(_ metafields: [Metafield]) {
        var index: [MetafieldIdentifier: Metafield] = [:]
        for metafield in metafields where index[metafield.identifier] == nil {
            index[metafield.identifier] = metafield
        }
        self.metafields = index
    }

    /// Whether no metafield is available.
    public var isEmpty: Bool {
        metafields.isEmpty
    }

    // MARK: Typed accessors

    /// The FAQ entries of `karinex.faq`; `nil` when missing or not a JSON array of
    /// `{question, answer}` objects. Entries with an empty question or answer and repeated
    /// questions are dropped.
    public var faq: [FAQEntry]? {
        guard let metafield = metafield(Identifier.faq),
              let array = Self.jsonArray(metafield.value)
        else { return nil }
        var seenQuestions: Set<String> = []
        var entries: [FAQEntry] = []
        for element in array {
            guard let object = element as? [String: Any],
                  let question = (object["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let answer = (object["answer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !question.isEmpty, !answer.isEmpty,
                  seenQuestions.insert(question).inserted
            else { continue }
            entries.append(FAQEntry(question: question, answer: answer))
        }
        return entries
    }

    /// `karinex.lizenztyp`.
    public var licenseType: String? {
        string(Identifier.licenseType)
    }

    /// `karinex.architektur`.
    public var architecture: String? {
        string(Identifier.architecture)
    }

    /// `karinex.geraeteanzahl` as text (integer metafields are rendered as digits).
    public var deviceCount: String? {
        string(Identifier.deviceCount)
    }

    /// `karinex.lieferform`.
    public var deliveryForm: String? {
        string(Identifier.deliveryForm)
    }

    /// `karinex.aktivierungsart`.
    public var activationMethod: String? {
        string(Identifier.activationMethod)
    }

    /// `karinex.sprachen` as a list (a single text value yields one element).
    public var languages: [String]? {
        strings(Identifier.languages)
    }

    /// `karinex.support_status`.
    public var supportStatus: String? {
        string(Identifier.supportStatus)
    }

    /// `custom.details_content`.
    public var detailsContent: MetafieldContent? {
        content(Identifier.detailsContent)
    }

    /// `custom.shipping_content`.
    public var shippingContent: MetafieldContent? {
        content(Identifier.shippingContent)
    }

    /// `custom.warranty_content`.
    public var warrantyContent: MetafieldContent? {
        content(Identifier.warrantyContent)
    }

    /// `custom.mpn`, falling back to the existing `mm-google-shopping.mpn`.
    public var mpn: String? {
        string(Identifier.mpn) ?? string(Identifier.googleShoppingMPN)
    }

    /// `karinex.deal_ends_at`, falling back to the existing `custom.angebotsende`.
    public var dealEndsAt: Date? {
        date(Identifier.dealEndsAt) ?? date(Identifier.offerEndsAt)
    }

    /// `karinex.lowest_price_30d`: a `money` metafield keeps its own currency; a plain number
    /// is interpreted in `currency` (pass the currency of the current market's prices).
    public func lowestPrice30Days(currency: CurrencyCode) -> MoneyV2? {
        money(Identifier.lowestPrice30Days, defaultCurrency: currency)
    }

    // MARK: Generic accessors

    /// The raw metafield for `identifier`, if present.
    public func metafield(_ identifier: MetafieldIdentifier) -> Metafield? {
        metafields[identifier]
    }

    /// A display string: trimmed text, list values joined with ", ", rich text as plain text,
    /// or `nil` when missing or blank.
    public func string(_ identifier: MetafieldIdentifier) -> String? {
        guard let metafield = metafield(identifier) else { return nil }
        let text: String? = if metafield.type.hasPrefix("list.") {
            strings(identifier)?.joined(separator: ", ")
        } else if metafield.type == "rich_text_field" {
            Self.richText(metafield.value)?.plainText
        } else {
            metafield.value
        }
        return Self.nonBlank(text)
    }

    /// The values of a `list.*` metafield (strings or numbers), or a single-element list for
    /// other types; `nil` when missing, blank or not parseable.
    public func strings(_ identifier: MetafieldIdentifier) -> [String]? {
        guard let metafield = metafield(identifier) else { return nil }
        guard metafield.type.hasPrefix("list.") else {
            return Self.nonBlank(metafield.value).map { [$0] }
        }
        guard let array = Self.jsonArray(metafield.value) else { return nil }
        let values = array.compactMap { element -> String? in
            switch element {
            case let string as String:
                Self.nonBlank(string)
            case let number as NSNumber:
                number.stringValue
            default:
                nil
            }
        }
        return values.isEmpty ? nil : values
    }

    /// An integer value, or `nil` when missing or not an integer.
    public func integer(_ identifier: MetafieldIdentifier) -> Int? {
        guard let text = metafield(identifier).flatMap({ Self.nonBlank($0.value) }) else { return nil }
        return Int(text)
    }

    /// A `date_time` value (ISO 8601 with offset, with or without fractional seconds), or a
    /// `date` value (`yyyy-MM-dd`, read as the start of that day in Europe/Berlin, the store's
    /// time zone). `nil` when missing or invalid.
    public func date(_ identifier: MetafieldIdentifier) -> Date? {
        guard let text = metafield(identifier).flatMap({ Self.nonBlank($0.value) }) else { return nil }
        return Self.parseDate(text)
    }

    /// A rich text document, or `nil` when missing or not a rich text value.
    public func richText(_ identifier: MetafieldIdentifier) -> RichTextNode? {
        guard let metafield = metafield(identifier) else { return nil }
        return Self.richText(metafield.value)
    }

    /// The content of a text-like metafield: rich text is parsed, text containing HTML tags
    /// is classified as HTML, anything else is plain text. `nil` when missing, blank or an
    /// invalid rich text value.
    public func content(_ identifier: MetafieldIdentifier) -> MetafieldContent? {
        guard let metafield = metafield(identifier) else { return nil }
        if metafield.type == "rich_text_field" {
            return Self.richText(metafield.value).map(MetafieldContent.richText)
        }
        guard let text = Self.nonBlank(metafield.value) else { return nil }
        return Self.containsHTMLTag(text) ? .html(text) : .plainText(text)
    }

    /// A money value: `money` metafields (`{"amount": "29.90", "currency_code": "EUR"}`) keep
    /// their currency, plain decimal values use `defaultCurrency`. `nil` when missing or invalid.
    public func money(_ identifier: MetafieldIdentifier, defaultCurrency: CurrencyCode) -> MoneyV2? {
        guard let metafield = metafield(identifier) else { return nil }
        if metafield.type == "money" {
            guard let data = metafield.value.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let amount = object["amount"] as? String,
                  let currency = (object["currency_code"] ?? object["currencyCode"]) as? String
            else { return nil }
            return MoneyV2(amount: amount, currencyCode: CurrencyCode(rawValue: currency))
        }
        guard let text = Self.nonBlank(metafield.value) else { return nil }
        return MoneyV2(amount: text, currencyCode: defaultCurrency)
    }

    // MARK: Parsing helpers

    private static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func jsonArray(_ value: String) -> [Any]? {
        guard let data = value.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [Any]
    }

    private static func richText(_ value: String) -> RichTextNode? {
        guard let data = value.data(using: .utf8),
              let node = try? JSONDecoder().decode(RichTextNode.self, from: data),
              node.type == "root"
        else { return nil }
        return node
    }

    private static func containsHTMLTag(_ text: String) -> Bool {
        text.range(of: #"</?[A-Za-z][A-Za-z0-9]*(\s[^<>]*)?/?>"#, options: .regularExpression) != nil
    }

    static func parseDate(_ text: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: text) {
            return date
        }
        let internetDateTime = ISO8601DateFormatter()
        internetDateTime.formatOptions = [.withInternetDateTime]
        if let date = internetDateTime.date(from: text) {
            return date
        }
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        dateOnly.timeZone = TimeZone(identifier: "Europe/Berlin") ?? TimeZone(secondsFromGMT: 0) ?? .current
        guard text.count == 10 else { return nil }
        return dateOnly.date(from: text)
    }
}
