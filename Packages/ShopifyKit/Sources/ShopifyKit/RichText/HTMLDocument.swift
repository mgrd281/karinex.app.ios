import Foundation

// MARK: - HTMLDocument

/// Store HTML (`descriptionHtml`, `contentHtml`) as a list of native blocks.
///
/// The parser is small, pure Swift and safe for untrusted input:
/// - it never crashes or fails, whatever the input (truncated, malformed or deeply nested),
/// - scripts, styles, iframes, forms, embedded media, comments and every attribute except
///   `href`, `src` and `alt` are dropped, so no store markup can execute or style anything.
///   Inline `style` attributes are only read as layout hints: a grid of label and value pairs
///   becomes ``HTMLBlock/facts(layout:items:)``, a grid of titled boxes ``HTMLBlock/cards(_:)``,
///   rows numbered "01", "02" ``HTMLBlock/steps(_:)``, a box with a leading border
///   ``HTMLBlock/callout(_:)``, and uppercase, large or small paragraphs become
///   ``HTMLBlock/eyebrow(_:)``, ``HTMLBlock/lead(_:)`` and ``HTMLBlock/note(_:)``. No style is
///   ever applied; the app draws these blocks with its own design tokens,
/// - only `http` and `https` links are kept (relative ones are resolved against `baseURL`).
///   Links with any other scheme, such as `mailto:`, `sms:` or `javascript:`, become plain
///   text, so store content never triggers an action on the device,
/// - character references are decoded (named and numeric) and white space is collapsed like a
///   browser does, except in `pre`.
///
/// ```swift
/// let document = HTMLDocument(html: product.descriptionHtml, baseURL: product.onlineStoreUrl)
/// for block in document.blocks { ... }
/// ```
public struct HTMLDocument: Sendable, Hashable {
    /// The blocks in document order.
    public let blocks: [HTMLBlock]

    /// Parses `html` without a base URL: relative links stay relative and relative images are
    /// dropped.
    public init(html: String) {
        self.init(html: html, baseURL: nil)
    }

    /// Parses `html`, resolving relative links and image sources against `baseURL` (for
    /// example the product's `onlineStoreUrl`).
    public init(html: String, baseURL: URL?) {
        let root = HTMLTreeBuilder.build(html)
        blocks = HTMLBlockBuilder(baseURL: baseURL).blocks(from: root.children)
    }

    /// Wraps already built blocks, e.g. for previews.
    public init(blocks: [HTMLBlock]) {
        self.blocks = blocks
    }

    /// Whether the document has no visible content.
    public var isEmpty: Bool {
        blocks.isEmpty
    }
}

// MARK: - HTMLBlock

/// A block of an `HTMLDocument`.
public indirect enum HTMLBlock: Sendable, Hashable {
    /// A heading of level 1 to 6.
    case heading(level: Int, inlines: [HTMLInline])
    /// A paragraph (also used for text directly inside containers such as `div`).
    case paragraph([HTMLInline])
    /// A bulleted (`ordered == false`) or numbered list; each item is a list of blocks.
    case list(ordered: Bool, items: [[HTMLBlock]])
    /// A table as rows of cells. Rows without cells are dropped; rows may differ in length.
    case table(rows: [[HTMLTableCell]])
    /// A block quote.
    case quote([HTMLBlock])
    /// An image with an `http(s)` URL and its alternative text, if any.
    case image(url: URL, alt: String?)
    /// A horizontal rule.
    case rule
    /// A short line above a title, uppercase in the store ("eyebrow").
    case eyebrow([HTMLInline])
    /// An introductory paragraph, set larger than body text in the store.
    case lead([HTMLInline])
    /// A quiet side note, set small or italic in the store.
    case note([HTMLInline])
    /// Label and value pairs: short ones as tiles (a grid in the store), long ones as rows.
    case facts(layout: HTMLFactLayout, items: [HTMLFact])
    /// Boxes with a title and a short text (a grid of headed boxes in the store).
    case cards([HTMLCard])
    /// Numbered rows ("01", "02", ...), each with its content.
    case steps([HTMLStep])
    /// A highlighted box (a box with a border on its leading edge in the store).
    case callout([HTMLBlock])
}

// MARK: - Structured blocks

/// How ``HTMLBlock/facts(layout:items:)`` is laid out.
public enum HTMLFactLayout: Sendable, Hashable {
    /// Short facts as tiles side by side.
    case tiles
    /// Facts with longer values as rows, label above value.
    case rows
}

/// One label and value pair of ``HTMLBlock/facts(layout:items:)``.
public struct HTMLFact: Sendable, Hashable {
    /// The label, e.g. "Lizenztyp".
    public let label: [HTMLInline]
    /// The value, e.g. "Dauerlizenz (LTSC)".
    public let value: [HTMLBlock]

    /// Creates a fact.
    public init(label: [HTMLInline], value: [HTMLBlock]) {
        self.label = label
        self.value = value
    }
}

/// One box of ``HTMLBlock/cards(_:)``.
public struct HTMLCard: Sendable, Hashable {
    /// The title of the box.
    public let title: [HTMLInline]
    /// The content below the title.
    public let body: [HTMLBlock]

    /// Creates a card.
    public init(title: [HTMLInline], body: [HTMLBlock]) {
        self.title = title
        self.body = body
    }
}

/// One row of ``HTMLBlock/steps(_:)``.
public struct HTMLStep: Sendable, Hashable {
    /// The number as written in the store, e.g. "01".
    public let number: String
    /// The content of the row.
    public let body: [HTMLBlock]

    /// Creates a step.
    public init(number: String, body: [HTMLBlock]) {
        self.number = number
        self.body = body
    }
}

// MARK: - HTMLTableCell

/// A table cell: a header cell (`th`) or a data cell (`td`) with inline content. Block
/// content inside a cell is flattened into lines.
public struct HTMLTableCell: Sendable, Hashable {
    /// Whether the cell is a header cell (`th`).
    public let isHeader: Bool
    /// The cell content.
    public let inlines: [HTMLInline]

    /// Creates a cell.
    public init(isHeader: Bool, inlines: [HTMLInline]) {
        self.isHeader = isHeader
        self.inlines = inlines
    }
}

// MARK: - HTMLInline

/// Inline content of a block.
public indirect enum HTMLInline: Sendable, Hashable {
    /// Plain text with collapsed white space.
    case text(String)
    /// Strong emphasis (`strong`, `b`).
    case strong([HTMLInline])
    /// Emphasis (`em`, `i`, `cite`).
    case emphasis([HTMLInline])
    /// Inline code (`code`, `kbd`, `samp`).
    case code(String)
    /// A link to an `http(s)` URL, or to a relative URL when the document has no base URL.
    case link(url: URL, [HTMLInline])
    /// A line break (`br`, or the boundary of a block flattened into inline content).
    case lineBreak
}

// MARK: - HTMLBlockBuilder

/// Converts the element tree into blocks.
struct HTMLBlockBuilder {
    /// Resolves relative URLs.
    let baseURL: URL?

    /// Elements whose subtree is never rendered.
    static let droppedElements: Set<String> = [
        "applet", "audio", "base", "button", "canvas", "datalist", "dialog", "embed", "form", "frame", "frameset", "head",
        "iframe", "input", "link", "map", "math", "meta", "noembed", "noframes", "noscript", "object", "option", "param",
        "script", "select", "source", "style", "svg", "template", "textarea", "title", "track", "video", "xmp",
    ]

    /// Elements rendered as blocks; every other element is inline (or transparent).
    static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "caption", "center", "col", "colgroup", "dd", "details",
        "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6",
        "header", "hgroup", "hr", "html", "legend", "li", "main", "menu", "nav", "ol", "p", "pre", "section", "summary",
        "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul",
    ]

    private static let headingLevels: [String: Int] = ["h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6]

    // MARK: Blocks

    /// Converts `nodes` into blocks: inline runs become paragraphs, block elements their blocks.
    func blocks(from nodes: [HTMLNode]) -> [HTMLBlock] {
        var result: [HTMLBlock] = []
        var pending: [InlinePiece] = []
        var hoistedImages: [HTMLBlock] = []

        func flush() {
            let inlines = InlineNormalizer.normalize(pending)
            if !inlines.isEmpty {
                result.append(.paragraph(inlines))
            }
            result.append(contentsOf: hoistedImages)
            pending = []
            hoistedImages = []
        }

        for node in nodes {
            switch node {
            case let .text(text):
                pending.append(.text(text))
            case let .element(element):
                if Self.droppedElements.contains(element.name) {
                    continue
                }
                if element.name == "img" {
                    flush()
                    if let image = image(element) {
                        result.append(image)
                    }
                } else if Self.blockElements.contains(element.name) {
                    flush()
                    result.append(contentsOf: blocks(for: element))
                } else {
                    pending.append(contentsOf: pieces(for: element, hoistedImages: &hoistedImages))
                }
            }
        }
        flush()
        return result
    }

    /// The blocks of one block element.
    private func blocks(for element: HTMLElementNode) -> [HTMLBlock] {
        switch element.name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            var images: [HTMLBlock] = []
            let inlines = InlineNormalizer.normalize(childPieces(of: element, hoistedImages: &images))
            let heading: [HTMLBlock] = inlines.isEmpty ? [] : [.heading(level: Self.headingLevels[element.name] ?? 2, inlines: inlines)]
            return heading + images
        case "ul", "ol", "menu", "dir":
            let items = listItems(of: element)
            return items.isEmpty ? [] : [.list(ordered: element.name == "ol", items: items)]
        case "table":
            return table(element)
        case "blockquote":
            let inner = blocks(from: element.children)
            return inner.isEmpty ? [] : [.quote(inner)]
        case "pre":
            let text = Self.preformattedText(of: element)
            return text.isEmpty ? [] : [.paragraph([.code(text)])]
        case "hr":
            return [.rule]
        case "col", "colgroup":
            return []
        case "p":
            return styledParagraph(element)
        default:
            return structuredBlocks(element) ?? blocks(from: element.children)
        }
    }

    /// The items of a list: one per `li`. Other content directly inside the list (invalid,
    /// but common) joins the previous item or starts one.
    private func listItems(of list: HTMLElementNode) -> [[HTMLBlock]] {
        var items: [[HTMLBlock]] = []
        for child in list.children {
            if case let .element(element) = child, element.name == "li" {
                let item = blocks(from: element.children)
                if !item.isEmpty {
                    items.append(item)
                }
                continue
            }
            let stray = blocks(from: [child])
            guard !stray.isEmpty else { continue }
            if items.isEmpty {
                items.append(stray)
            } else {
                items[items.count - 1].append(contentsOf: stray)
            }
        }
        return items
    }

    /// A table: its caption as a paragraph, then the rows of `thead`, `tbody`, `tfoot` and the
    /// table itself in document order.
    private func table(_ table: HTMLElementNode) -> [HTMLBlock] {
        var caption: [HTMLBlock] = []
        var rows: [[HTMLTableCell]] = []

        func collectRows(in element: HTMLElementNode) {
            for case let .element(child) in element.children {
                switch child.name {
                case "tr":
                    let cells = row(child)
                    if !cells.isEmpty {
                        rows.append(cells)
                    }
                case "thead", "tbody", "tfoot":
                    collectRows(in: child)
                case "caption":
                    caption.append(contentsOf: blocks(from: child.children))
                default:
                    continue
                }
            }
        }

        collectRows(in: table)
        guard !rows.isEmpty else { return caption }
        return caption + [.table(rows: rows)]
    }

    /// The cells of a row; cells that are empty still count, to keep columns aligned.
    private func row(_ row: HTMLElementNode) -> [HTMLTableCell] {
        var cells: [HTMLTableCell] = []
        for case let .element(cell) in row.children where cell.name == "td" || cell.name == "th" {
            var images: [HTMLBlock] = []
            let inlines = InlineNormalizer.normalize(childPieces(of: cell, hoistedImages: &images))
            cells.append(HTMLTableCell(isHeader: cell.name == "th", inlines: inlines))
        }
        return cells.contains { !$0.inlines.isEmpty } ? cells : []
    }

    // MARK: Inlines

    /// The inline pieces of all children of `element`.
    func childPieces(of element: HTMLElementNode, hoistedImages: inout [HTMLBlock]) -> [InlinePiece] {
        var pieces: [InlinePiece] = []
        for child in element.children {
            switch child {
            case let .text(text):
                pieces.append(.text(text))
            case let .element(childElement):
                pieces.append(contentsOf: self.pieces(for: childElement, hoistedImages: &hoistedImages))
            }
        }
        return pieces
    }

    /// The inline pieces of one element. Images are hoisted out of inline content; block
    /// elements inside inline content are flattened with soft line breaks around them.
    private func pieces(for element: HTMLElementNode, hoistedImages: inout [HTMLBlock]) -> [InlinePiece] {
        if Self.droppedElements.contains(element.name) {
            return []
        }
        switch element.name {
        case "br":
            return [.hardBreak]
        case "img":
            if let image = image(element) {
                hoistedImages.append(image)
            }
            return []
        case "strong", "b":
            return [.strong(childPieces(of: element, hoistedImages: &hoistedImages))]
        case "em", "i", "cite", "dfn", "var":
            return [.emphasis(childPieces(of: element, hoistedImages: &hoistedImages))]
        case "code", "kbd", "samp", "tt":
            return [.code(Self.collapsedText(of: element))]
        case "a":
            let children = childPieces(of: element, hoistedImages: &hoistedImages)
            guard let url = linkURL(element.attributes["href"]) else { return children }
            return [.link(url, children)]
        case "td", "th":
            return [.space] + childPieces(of: element, hoistedImages: &hoistedImages) + [.space]
        default:
            let children = childPieces(of: element, hoistedImages: &hoistedImages)
            return Self.blockElements.contains(element.name) ? [.softBreak] + children + [.softBreak] : children
        }
    }

    // MARK: URLs

    /// The image block of an `img` with an `http(s)` source, else `nil`.
    private func image(_ element: HTMLElementNode) -> HTMLBlock? {
        guard let url = resolvedURL(element.attributes["src"], allowRelativeWithoutBase: false) else { return nil }
        let alt = element.attributes["alt"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .image(url: url, alt: alt?.isEmpty == false ? alt : nil)
    }

    /// The target of a link, or `nil` when the link must become plain text.
    private func linkURL(_ href: String?) -> URL? {
        resolvedURL(href, allowRelativeWithoutBase: true)
    }

    /// Resolves `reference` to an `http(s)` URL.
    ///
    /// Tabs and line breaks are removed first (browsers ignore them in URLs, so they must not
    /// hide a scheme). Fragment-only references and every scheme other than `http` and `https`
    /// yield `nil`. Protocol-relative references (`//host/path`) use `https`. Relative
    /// references are resolved against `baseURL`; without a base they are kept relative when
    /// `allowRelativeWithoutBase` is true.
    private func resolvedURL(_ reference: String?, allowRelativeWithoutBase: Bool) -> URL? {
        guard let reference else { return nil }
        let cleaned = String(String.UnicodeScalarView(reference.unicodeScalars.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" }))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !cleaned.isEmpty, !cleaned.hasPrefix("#") else { return nil }

        if let scheme = Self.scheme(of: cleaned) {
            guard scheme == "http" || scheme == "https", let url = URL(string: cleaned), url.host != nil else { return nil }
            return url
        }
        if cleaned.hasPrefix("//") {
            guard let url = URL(string: "https:" + cleaned), url.host != nil else { return nil }
            return url
        }
        if let baseURL {
            guard let url = URL(string: cleaned, relativeTo: baseURL)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
            else { return nil }
            return url
        }
        return allowRelativeWithoutBase ? URL(string: cleaned) : nil
    }

    /// The lower-case scheme of `reference` (`[A-Za-z][A-Za-z0-9+.-]*` before the first `:`
    /// that precedes any `/`, `?` or `#`), or `nil` for a relative reference.
    private static func scheme(of reference: String) -> String? {
        var scheme = ""
        for scalar in reference.unicodeScalars {
            if scalar == ":" {
                return scheme.isEmpty ? nil : scheme.lowercased()
            }
            let isLetter = HTMLTokenizer.isASCIILetter(scalar)
            let isAllowed = isLetter ||
                (!scheme.isEmpty && (HTMLEntities.isASCIIAlphanumeric(scalar) || "+.-".unicodeScalars.contains(scalar)))
            guard isAllowed else { return nil }
            scheme.unicodeScalars.append(scalar)
        }
        return nil
    }

    // MARK: Text helpers

    /// The text of an element's subtree with white space collapsed, for inline code.
    static func collapsedText(of element: HTMLElementNode) -> String {
        var text = ""
        appendText(of: element, to: &text, lineBreak: " ")
        return text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\u{0C}" })
            .joined(separator: " ")
    }

    /// The text of a `pre` element with white space kept: one leading line break and
    /// trailing white space are removed.
    private static func preformattedText(of element: HTMLElementNode) -> String {
        var text = ""
        appendText(of: element, to: &text, lineBreak: "\n")
        if text.hasPrefix("\r\n") {
            text.removeFirst(2)
        } else if text.hasPrefix("\n") {
            text.removeFirst()
        }
        while let last = text.unicodeScalars.last, HTMLTokenizer.isWhitespace(last) {
            text.unicodeScalars.removeLast()
        }
        return text
    }

    private static func appendText(of element: HTMLElementNode, to text: inout String, lineBreak: String) {
        for child in element.children {
            switch child {
            case let .text(value):
                text += value
            case let .element(childElement):
                if childElement.name == "br" {
                    text += lineBreak
                } else if !droppedElements.contains(childElement.name) {
                    appendText(of: childElement, to: &text, lineBreak: lineBreak)
                }
            }
        }
    }
}

// MARK: - InlinePiece

/// Inline content before white space normalization.
indirect enum InlinePiece {
    case text(String)
    case strong([InlinePiece])
    case emphasis([InlinePiece])
    case code(String)
    case link(URL, [InlinePiece])
    /// An explicit `br`: kept, at most two in a row.
    case hardBreak
    /// The boundary of a flattened block: one line break unless one is already there.
    case softBreak
    /// Collapsible white space, e.g. between flattened table cells.
    case space
}

// MARK: - InlineNormalizer

/// Collapses white space like a browser: runs of white space become one space, white space at
/// the start and end of a block and around line breaks disappears, leading and trailing line
/// breaks are removed, at most two line breaks follow each other, adjacent texts merge and
/// empty containers are dropped. A space between a text and a styled run is kept outside the
/// run. U+00A0 (no-break space) is content and stays.
enum InlineNormalizer {
    private struct State {
        /// White space was seen since the last emitted content.
        var pendingSpace = false
        /// Content was emitted in this block.
        var hasContent = false
        /// Line breaks emitted since the last content.
        var breaks = 0
        /// The last emitted character is a space.
        var lastWasSpace = false

        /// Whether a pending space must be written before the next content.
        var needsSpace: Bool {
            pendingSpace && hasContent && breaks == 0 && !lastWasSpace
        }
    }

    /// Normalizes `pieces` into inlines.
    static func normalize(_ pieces: [InlinePiece]) -> [HTMLInline] {
        var state = State()
        return trimTrailing(process(pieces, state: &state))
    }

    private static func process(_ pieces: [InlinePiece], state: inout State) -> [HTMLInline] {
        var output: [HTMLInline] = []
        for piece in pieces {
            switch piece {
            case let .text(text):
                var buffer = String.UnicodeScalarView()
                for scalar in text.unicodeScalars {
                    if HTMLTokenizer.isWhitespace(scalar) {
                        state.pendingSpace = true
                    } else {
                        writeContent(scalar, to: &buffer, state: &state)
                    }
                }
                append(.text(String(buffer)), to: &output)
            case .space:
                state.pendingSpace = true
            case let .code(code):
                guard !code.isEmpty else { continue }
                writePendingSpace(to: &output, state: &state)
                output.append(.code(code))
                state.hasContent = true
                state.breaks = 0
                state.lastWasSpace = false
            case .hardBreak:
                if state.hasContent, state.breaks < 2 {
                    appendBreak(to: &output, state: &state)
                }
                state.pendingSpace = false
            case .softBreak:
                if state.hasContent, state.breaks == 0 {
                    appendBreak(to: &output, state: &state)
                }
                state.pendingSpace = false
            case let .strong(children):
                writePendingSpace(to: &output, state: &state)
                let inner = process(children, state: &state)
                if !inner.isEmpty {
                    output.append(.strong(inner))
                }
            case let .emphasis(children):
                writePendingSpace(to: &output, state: &state)
                let inner = process(children, state: &state)
                if !inner.isEmpty {
                    output.append(.emphasis(inner))
                }
            case let .link(url, children):
                writePendingSpace(to: &output, state: &state)
                let inner = process(children, state: &state)
                if !inner.isEmpty {
                    output.append(.link(url: url, inner))
                }
            }
        }
        return output
    }

    /// Writes one non-space scalar, preceded by a pending space when needed.
    private static func writeContent(_ scalar: Unicode.Scalar, to buffer: inout String.UnicodeScalarView, state: inout State) {
        if state.needsSpace {
            buffer.append(" ")
        }
        buffer.append(scalar)
        state.pendingSpace = false
        state.hasContent = true
        state.breaks = 0
        state.lastWasSpace = false
    }

    /// Writes a pending space at the current level, e.g. before a styled run.
    private static func writePendingSpace(to output: inout [HTMLInline], state: inout State) {
        if state.needsSpace {
            append(.text(" "), to: &output)
            state.lastWasSpace = true
        }
        state.pendingSpace = false
    }

    /// Appends a line break, removing a space directly before it.
    private static func appendBreak(to output: inout [HTMLInline], state: inout State) {
        if case let .text(previous)? = output.last, previous.hasSuffix(" ") {
            let trimmed = String(previous.dropLast())
            if trimmed.isEmpty {
                output.removeLast()
            } else {
                output[output.count - 1] = .text(trimmed)
            }
        }
        output.append(.lineBreak)
        state.breaks += 1
        state.lastWasSpace = false
    }

    /// Appends text, merging it with directly preceding text; empty text is skipped.
    private static func append(_ inline: HTMLInline, to output: inout [HTMLInline]) {
        guard case let .text(text) = inline else {
            output.append(inline)
            return
        }
        guard !text.isEmpty else { return }
        if case let .text(previous)? = output.last {
            output[output.count - 1] = .text(previous + text)
        } else {
            output.append(inline)
        }
    }

    /// Removes line breaks and spaces at the end, also inside a trailing container, and
    /// containers that become empty.
    private static func trimTrailing(_ inlines: [HTMLInline]) -> [HTMLInline] {
        var result = inlines
        while let last = result.last {
            switch last {
            case .lineBreak:
                result.removeLast()
            case let .text(text):
                guard text.hasSuffix(" ") else { return result }
                result.removeLast()
                let trimmed = String(text.dropLast())
                if !trimmed.isEmpty {
                    result.append(.text(trimmed))
                }
            case let .strong(children):
                let trimmed = trimTrailing(children)
                if trimmed == children { return result }
                result.removeLast()
                if !trimmed.isEmpty { result.append(.strong(trimmed)) }
            case let .emphasis(children):
                let trimmed = trimTrailing(children)
                if trimmed == children { return result }
                result.removeLast()
                if !trimmed.isEmpty { result.append(.emphasis(trimmed)) }
            case let .link(url, children):
                let trimmed = trimTrailing(children)
                if trimmed == children { return result }
                result.removeLast()
                if !trimmed.isEmpty { result.append(.link(url: url, trimmed)) }
            case .code:
                return result
            }
        }
        return result
    }
}
