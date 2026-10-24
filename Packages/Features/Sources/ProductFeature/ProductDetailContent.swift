import Foundation
import ShopifyKit

// MARK: - ProductDetailContent

/// Everything the product screen renders for one product, prepared once when the product loads:
/// the parsed description, the key facts, the activation text and the FAQ.
///
/// All of it is store content from Shopify. Sections whose source is missing (every metafield
/// in tokenless mode) are empty and the screen hides them; nothing is filled in by the app.
struct ProductDetailContent: Sendable, Hashable {
    /// The product from Shopify.
    let product: Product
    /// The gallery images: the product images, or the featured image when the product lists none.
    let images: [ShopifyImage]
    /// The parsed `descriptionHtml`. Phone links and other non-web schemes are already plain
    /// text (``HTMLDocument``).
    let description: HTMLDocument
    /// The key facts from the `karinex.*` metafields, in the order of PROMPT.md section 6.3.
    let facts: [ProductFact]
    /// The activation instructions from `custom.details_content`, or `nil` when there are none.
    let activation: HTMLDocument?
    /// The questions and answers of `karinex.faq`, empty when there are none.
    let faq: [ProductFAQItem]

    /// Prepares the content of `product`. Parses HTML, so call it off the main actor for long
    /// descriptions (``make(_:)``).
    init(product: Product) {
        self.product = product
        if !product.images.isEmpty {
            images = product.images
        } else if let featured = product.featuredImage {
            images = [featured]
        } else {
            images = []
        }
        description = HTMLDocument(html: product.descriptionHtml, baseURL: product.onlineStoreUrl)
        let metafields = product.productMetafields
        facts = ProductFact.facts(from: metafields)
        activation = metafields.detailsContent.flatMap { ProductRichText.document(for: $0, baseURL: product.onlineStoreUrl) }
        faq = (metafields.faq ?? []).compactMap { entry in
            let answer = HTMLDocument(html: entry.answer, baseURL: product.onlineStoreUrl)
            guard !answer.isEmpty else { return nil }
            return ProductFAQItem(question: entry.question, answer: answer)
        }
    }

    /// Prepares the content on a background task, so parsing never blocks scrolling.
    static func make(_ product: Product) async -> ProductDetailContent {
        await Task.detached(priority: .userInitiated) { ProductDetailContent(product: product) }.value
    }

    /// The index of `image` in ``images`` (compared by URL), if the gallery shows it.
    func imageIndex(of image: ShopifyImage?) -> Int? {
        guard let image else { return nil }
        return images.firstIndex { $0.url == image.url }
    }
}

// MARK: - ProductFAQItem

/// One question of the product FAQ with its parsed answer.
struct ProductFAQItem: Sendable, Hashable, Identifiable {
    /// The question, as written in the store.
    let question: String
    /// The answer, parsed from text or HTML.
    let answer: HTMLDocument

    /// The question; unique within one product (``ProductMetafields/faq`` drops repeats).
    var id: String {
        question
    }
}

// MARK: - ProductFact

/// One row of the key facts table: a localized label and the store's value.
struct ProductFact: Sendable, Hashable, Identifiable {
    /// The kinds of facts, in display order (PROMPT.md section 6.3).
    enum Kind: String, CaseIterable, Sendable {
        /// `karinex.lizenztyp`.
        case licenseType
        /// `karinex.architektur`.
        case architecture
        /// `karinex.geraeteanzahl`.
        case deviceCount
        /// `karinex.lieferform`.
        case deliveryForm
        /// `karinex.aktivierungsart`.
        case activationMethod
        /// `karinex.sprachen`.
        case languages
        /// `karinex.support_status`.
        case supportStatus
        /// `custom.mpn`, or `mm-google-shopping.mpn`.
        case mpn

        /// The label in the user's language.
        var label: String {
            label(in: ProductFeatureResources.bundle)
        }

        /// The label resolved against `bundle`: the module bundle or one of its `.lproj` folders.
        func label(in bundle: Bundle) -> String {
            String(localized: labelKey, bundle: bundle)
        }

        private var labelKey: String.LocalizationValue {
            switch self {
            case .licenseType: "product.facts.license_type"
            case .architecture: "product.facts.architecture"
            case .deviceCount: "product.facts.device_count"
            case .deliveryForm: "product.facts.delivery_form"
            case .activationMethod: "product.facts.activation_method"
            case .languages: "product.facts.languages"
            case .supportStatus: "product.facts.support_status"
            case .mpn: "product.facts.mpn"
            }
        }

        /// The store value of this fact, or `nil` when the metafield is missing or blank.
        func value(in metafields: ProductMetafields) -> String? {
            switch self {
            case .licenseType: metafields.licenseType
            case .architecture: metafields.architecture
            case .deviceCount: metafields.deviceCount
            case .deliveryForm: metafields.deliveryForm
            case .activationMethod: metafields.activationMethod
            case .languages: metafields.languages?.joined(separator: ", ")
            case .supportStatus: metafields.supportStatus
            case .mpn: metafields.mpn
            }
        }
    }

    /// What the row describes.
    let kind: Kind
    /// The value from Shopify, shown as it is.
    let value: String

    /// The kind; a product has at most one fact of each kind.
    var id: Kind {
        kind
    }

    /// The facts present in `metafields`, in display order. Empty in tokenless mode, where
    /// Shopify returns no metafields; the table is then hidden.
    static func facts(from metafields: ProductMetafields) -> [ProductFact] {
        Kind.allCases.compactMap { kind in
            kind.value(in: metafields).map { ProductFact(kind: kind, value: $0) }
        }
    }
}

// MARK: - ProductFulfillment

/// How the selected variant reaches the customer, which decides the "So läuft es ab" timeline
/// and whether the digital-content notice is shown.
enum ProductFulfillment: String, CaseIterable, Sendable {
    /// A license key delivered by e-mail (`requiresShipping == false`).
    case digital
    /// A physical item that is shipped (`requiresShipping == true`).
    case physical

    /// The fulfillment of `variant`: physical when it requires shipping, otherwise digital (the
    /// license key case, also used while no variant is known).
    init(variant: ProductVariant?) {
        self = variant?.requiresShipping == true ? .physical : .digital
    }

    /// The steps of the "So läuft es ab" timeline.
    var steps: [ProductProcessStep] {
        switch self {
        case .digital: [.order, .pay, .emailDelivery]
        case .physical: [.order, .pay, .shipping]
        }
    }

    /// Whether the right of withdrawal notice for digital content applies (§ 356 Abs. 5 BGB).
    var showsDigitalContentNotice: Bool {
        self == .digital
    }

    /// The short delivery note next to the availability, in the user's language.
    var deliveryNote: String {
        deliveryNote(in: ProductFeatureResources.bundle)
    }

    /// The delivery note resolved against `bundle`.
    func deliveryNote(in bundle: Bundle) -> String {
        String(localized: deliveryNoteKey, bundle: bundle)
    }

    private var deliveryNoteKey: String.LocalizationValue {
        switch self {
        case .digital: "product.delivery.digital"
        case .physical: "product.delivery.physical"
        }
    }

    /// The SF Symbol of the delivery note.
    var systemImage: String {
        switch self {
        case .digital: "envelope"
        case .physical: "shippingbox"
        }
    }
}

// MARK: - ProductProcessStep

/// One step of the "So läuft es ab" timeline. Fixed business process (PROMPT.md section 6.3),
/// no product data.
enum ProductProcessStep: String, CaseIterable, Sendable {
    /// "Bestellen".
    case order
    /// "Bezahlen" with the store's payment methods.
    case pay
    /// "Schlüssel per E-Mail", within minutes (digital variants).
    case emailDelivery
    /// "Versand" (physical variants).
    case shipping

    /// The title in the user's language.
    var title: String {
        title(in: ProductFeatureResources.bundle)
    }

    /// The detail line in the user's language.
    var detail: String {
        detail(in: ProductFeatureResources.bundle)
    }

    /// The title resolved against `bundle`.
    func title(in bundle: Bundle) -> String {
        String(localized: titleKey, bundle: bundle)
    }

    /// The detail line resolved against `bundle`.
    func detail(in bundle: Bundle) -> String {
        String(localized: detailKey, bundle: bundle)
    }

    private var titleKey: String.LocalizationValue {
        switch self {
        case .order: "product.process.order.title"
        case .pay: "product.process.pay.title"
        case .emailDelivery: "product.process.email.title"
        case .shipping: "product.process.shipping.title"
        }
    }

    private var detailKey: String.LocalizationValue {
        switch self {
        case .order: "product.process.order.detail"
        case .pay: "product.process.pay.detail"
        case .emailDelivery: "product.process.email.detail"
        case .shipping: "product.process.shipping.detail"
        }
    }
}

// MARK: - ProductRefundClause

/// The conditions of the "100 Tage Geld-zurück" promise, with the same meaning as on the Start
/// tab (PROMPT.md section 2): only activated license keys and physical goods; delivered but not
/// activated keys are not refunded voluntarily; statutory warranty rights remain untouched.
enum ProductRefundClause: String, CaseIterable, Identifiable, Sendable {
    /// The promise applies only to activated license keys and to physical goods.
    case scope
    /// Delivered but not activated keys are not refunded voluntarily.
    case unactivatedKeys
    /// Statutory warranty rights remain untouched.
    case statutoryRights

    /// Stable identity.
    var id: String {
        rawValue
    }

    /// The SF Symbol before the clause.
    var systemImage: String {
        switch self {
        case .scope: "checkmark.seal"
        case .unactivatedKeys: "key"
        case .statutoryRights: "scalemass"
        }
    }

    /// The clause in the user's language.
    var text: String {
        text(in: ProductFeatureResources.bundle)
    }

    /// The clause resolved against `bundle`.
    func text(in bundle: Bundle) -> String {
        String(localized: textKey, bundle: bundle)
    }

    private var textKey: String.LocalizationValue {
        switch self {
        case .scope: "product.refund.scope"
        case .unactivatedKeys: "product.refund.unactivated"
        case .statutoryRights: "product.refund.statutory"
        }
    }
}

// MARK: - ProductRichText

/// Converts metafield content into an ``HTMLDocument`` for ``RichTextView``.
///
/// Shopify rich text (`rich_text_field`) becomes headings, paragraphs and lists with bold and
/// italic text. Links stay tappable only for `http` and `https`; any other scheme (for example
/// a phone link) keeps its text and loses the link, exactly like the HTML parser does.
enum ProductRichText {
    /// The document for `content`, or `nil` when it has no visible content.
    static func document(for content: MetafieldContent, baseURL: URL?) -> HTMLDocument? {
        let document = switch content {
        case let .plainText(text):
            HTMLDocument(blocks: paragraphs(in: text))
        case let .html(html):
            HTMLDocument(html: html, baseURL: baseURL)
        case let .richText(root):
            HTMLDocument(blocks: blocks(root.children))
        }
        return document.isEmpty ? nil : document
    }

    /// One paragraph per non-blank line of `text`.
    static func paragraphs(in text: String) -> [HTMLBlock] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { HTMLBlock.paragraph([.text($0)]) }
    }

    /// The blocks of rich text nodes. Inline nodes between blocks are collected into paragraphs.
    static func blocks(_ nodes: [RichTextNode]) -> [HTMLBlock] {
        var result: [HTMLBlock] = []
        var pendingInlines: [HTMLInline] = []

        func flush() {
            if let paragraph = paragraph(pendingInlines) {
                result.append(paragraph)
            }
            pendingInlines = []
        }

        for node in nodes {
            switch node.type {
            case "heading":
                flush()
                let inlines = inlines(node.children)
                if !isBlank(inlines) {
                    result.append(.heading(level: min(max(node.level ?? 2, 1), 6), inlines: inlines))
                }
            case "paragraph":
                flush()
                if let paragraph = paragraph(inlines(node.children)) {
                    result.append(paragraph)
                }
            case "list":
                flush()
                let items = node.children
                    .map { item in item.type == "list-item" ? blocks(item.children) : blocks([item]) }
                    .filter { !$0.isEmpty }
                if !items.isEmpty {
                    result.append(.list(ordered: node.listType == "ordered", items: items))
                }
            case "root", "list-item":
                flush()
                result.append(contentsOf: blocks(node.children))
            default:
                pendingInlines.append(contentsOf: inlines([node]))
            }
        }
        flush()
        return result
    }

    /// The inline content of rich text nodes.
    static func inlines(_ nodes: [RichTextNode]) -> [HTMLInline] {
        nodes.flatMap { node -> [HTMLInline] in
            switch node.type {
            case "text":
                guard let value = node.value, !value.isEmpty else { return [] }
                var inline = HTMLInline.text(value)
                if node.italic == true {
                    inline = .emphasis([inline])
                }
                if node.bold == true {
                    inline = .strong([inline])
                }
                return [inline]
            case "link":
                let content = inlines(node.children)
                guard let url = webURL(node.url) else { return content }
                return [.link(url: url, content)]
            default:
                return inlines(node.children)
            }
        }
    }

    /// `text` as an `http(s)` URL, or `nil` for every other scheme.
    static func webURL(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    private static func paragraph(_ inlines: [HTMLInline]) -> HTMLBlock? {
        isBlank(inlines) ? nil : .paragraph(inlines)
    }

    private static func isBlank(_ inlines: [HTMLInline]) -> Bool {
        inlines.allSatisfy { inline in
            switch inline {
            case let .text(text), let .code(text):
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case let .strong(children), let .emphasis(children), let .link(_, children):
                isBlank(children)
            case .lineBreak:
                true
            }
        }
    }
}
