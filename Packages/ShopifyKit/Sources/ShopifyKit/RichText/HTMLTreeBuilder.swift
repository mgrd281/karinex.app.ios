import Foundation

// MARK: - HTMLNode

/// A node of the lightweight tree `HTMLTreeBuilder` builds. Internal to the parser and only
/// used inside one `HTMLDocument` initializer, so it needs no `Sendable` conformance.
enum HTMLNode {
    /// Text with character references already decoded and whitespace not yet normalized.
    case text(String)
    /// An element.
    case element(HTMLElementNode)
}

/// An element with lower-case name, attributes and children.
final class HTMLElementNode {
    /// The lower-case tag name, e.g. `p`.
    let name: String
    /// The attributes with lower-case names; the first occurrence of a name wins.
    let attributes: [String: String]
    /// The children in document order.
    var children: [HTMLNode] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    /// Appends text, merging it with a directly preceding text node.
    func appendText(_ text: String) {
        if case let .text(previous)? = children.last {
            children[children.count - 1] = .text(previous + text)
        } else {
            children.append(.text(text))
        }
    }
}

// MARK: - HTMLToken

/// A token of `HTMLTokenizer`.
enum HTMLToken: Equatable {
    /// Text with character references decoded.
    case text(String)
    /// A start tag with lower-case name and attributes.
    case startTag(name: String, attributes: [String: String])
    /// An end tag with lower-case name.
    case endTag(name: String)
}

// MARK: - HTMLTokenizer

/// A forgiving HTML tokenizer for store content.
///
/// It never fails: comments, doctypes and processing instructions are skipped, a `<` that does
/// not start a tag is text, an unterminated tag at the end of the input is dropped, and the
/// content of raw text elements (`script`, `style`, `iframe`, ...) is skipped up to their end
/// tag. Character references are decoded in text and attribute values.
enum HTMLTokenizer {
    /// Elements whose content is raw text that is never rendered.
    static let rawTextElements: Set<String> = [
        "script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes", "noscript",
    ]

    /// Splits `html` into tokens.
    static func tokens(_ html: String) -> [HTMLToken] {
        let scalars = Array(html.unicodeScalars)
        var tokens: [HTMLToken] = []
        var text = String.UnicodeScalarView()
        var index = 0

        func flushText() {
            guard !text.isEmpty else { return }
            tokens.append(.text(String(text)))
            text = String.UnicodeScalarView()
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "&" {
                if let (decoded, length) = HTMLEntities.decode(scalars, at: index) {
                    text.append(decoded)
                    index += length
                } else {
                    text.append(scalar)
                    index += 1
                }
                continue
            }
            guard scalar == "<", index + 1 < scalars.count else {
                text.append(scalar)
                index += 1
                continue
            }

            let next = scalars[index + 1]
            if next == "!" || next == "?" {
                index = skipMarkupDeclaration(scalars, from: index)
            } else if next == "/" {
                if index + 2 < scalars.count, isASCIILetter(scalars[index + 2]) {
                    let (name, nameEnd) = readName(scalars, from: index + 2)
                    guard let close = firstIndex(of: ">", in: scalars, from: nameEnd) else {
                        // A truncated end tag at the end of the input is dropped.
                        index = scalars.count
                        continue
                    }
                    flushText()
                    tokens.append(.endTag(name: name))
                    index = close + 1
                } else {
                    // `</>` or `</ ...>`: a bogus comment.
                    index = (firstIndex(of: ">", in: scalars, from: index + 2) ?? scalars.count - 1) + 1
                }
            } else if isASCIILetter(next) {
                guard let tag = readStartTag(scalars, from: index + 1) else {
                    // A truncated start tag at the end of the input is dropped.
                    index = scalars.count
                    continue
                }
                flushText()
                tokens.append(.startTag(name: tag.name, attributes: tag.attributes))
                index = tag.end
                if rawTextElements.contains(tag.name) {
                    index = rawTextEnd(scalars, from: index, name: tag.name)
                }
            } else {
                text.append(scalar)
                index += 1
            }
        }
        flushText()
        return tokens
    }

    // MARK: Pieces

    /// Skips `<!-- ... -->`, `<!DOCTYPE ...>`, `<![CDATA[ ... ]]>` and `<? ... >` starting at
    /// `start` and returns the index after it (the end of the input when unterminated).
    private static func skipMarkupDeclaration(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
        if matches("<!--", in: scalars, at: start) {
            var cursor = start + 4
            while cursor + 2 < scalars.count {
                if scalars[cursor] == "-", scalars[cursor + 1] == "-", scalars[cursor + 2] == ">" {
                    return cursor + 3
                }
                cursor += 1
            }
            return scalars.count
        }
        return (firstIndex(of: ">", in: scalars, from: start + 2) ?? scalars.count - 1) + 1
    }

    /// Reads a start tag whose name starts at `start`. Returns `nil` when the input ends
    /// before the tag is closed.
    private static func readStartTag(
        _ scalars: [Unicode.Scalar],
        from start: Int
    ) -> (name: String, attributes: [String: String], end: Int)? {
        let (name, nameEnd) = readName(scalars, from: start)
        var attributes: [String: String] = [:]
        var cursor = nameEnd
        while cursor < scalars.count {
            let scalar = scalars[cursor]
            if scalar == ">" {
                return (name, attributes, cursor + 1)
            }
            if isWhitespace(scalar) || scalar == "/" {
                cursor += 1
                continue
            }
            // Attribute name: up to white space, `/`, `>` or `=` (a leading `=` belongs to it).
            var attributeName = String.UnicodeScalarView()
            attributeName.append(scalar)
            cursor += 1
            while cursor < scalars.count, !isWhitespace(scalars[cursor]), scalars[cursor] != "/", scalars[cursor] != ">",
                  scalars[cursor] != "="
            {
                attributeName.append(scalars[cursor])
                cursor += 1
            }
            cursor = skipWhitespace(scalars, from: cursor)
            var value = ""
            if cursor < scalars.count, scalars[cursor] == "=" {
                cursor = skipWhitespace(scalars, from: cursor + 1)
                guard cursor < scalars.count else { return nil }
                let quote = scalars[cursor]
                if quote == "\"" || quote == "'" {
                    guard let close = firstIndex(of: quote, in: scalars, from: cursor + 1) else { return nil }
                    value = decodeReferences(scalars[(cursor + 1)..<close])
                    cursor = close + 1
                } else {
                    let valueStart = cursor
                    while cursor < scalars.count, !isWhitespace(scalars[cursor]), scalars[cursor] != ">" {
                        cursor += 1
                    }
                    value = decodeReferences(scalars[valueStart..<cursor])
                }
            }
            let key = String(attributeName).lowercased()
            if attributes[key] == nil {
                attributes[key] = value
            }
        }
        return nil
    }

    /// Reads a tag name (`[A-Za-z][^\s/>]*`), lower-cased, and returns the index after it.
    private static func readName(_ scalars: [Unicode.Scalar], from start: Int) -> (String, Int) {
        var name = String.UnicodeScalarView()
        var cursor = start
        while cursor < scalars.count, !isWhitespace(scalars[cursor]), scalars[cursor] != "/", scalars[cursor] != ">" {
            name.append(scalars[cursor])
            cursor += 1
        }
        return (String(name).lowercased(), cursor)
    }

    /// The index of the `<` of the end tag `</name` after raw text, or the end of the input.
    private static func rawTextEnd(_ scalars: [Unicode.Scalar], from start: Int, name: String) -> Int {
        let pattern = Array(("</" + name).unicodeScalars)
        var cursor = start
        while cursor + pattern.count <= scalars.count {
            if scalars[cursor] == "<", scalars[cursor + 1] == "/" {
                var matched = true
                for offset in 2..<pattern.count where lowercased(scalars[cursor + offset]) != pattern[offset] {
                    matched = false
                    break
                }
                let after = cursor + pattern.count
                if matched, after == scalars.count || isWhitespace(scalars[after]) || scalars[after] == ">" || scalars[after] == "/" {
                    return cursor
                }
            }
            cursor += 1
        }
        return scalars.count
    }

    /// Decodes character references in an attribute value.
    private static func decodeReferences(_ slice: ArraySlice<Unicode.Scalar>) -> String {
        let scalars = Array(slice)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            if scalars[index] == "&", let (decoded, length) = HTMLEntities.decode(scalars, at: index) {
                result.append(decoded)
                index += length
            } else {
                result.append(scalars[index])
                index += 1
            }
        }
        return String(result)
    }

    // MARK: Scalar helpers

    private static func matches(_ literal: String, in scalars: [Unicode.Scalar], at index: Int) -> Bool {
        let pattern = Array(literal.unicodeScalars)
        guard index + pattern.count <= scalars.count else { return false }
        for offset in 0..<pattern.count where scalars[index + offset] != pattern[offset] {
            return false
        }
        return true
    }

    private static func firstIndex(of target: Unicode.Scalar, in scalars: [Unicode.Scalar], from start: Int) -> Int? {
        var cursor = start
        while cursor < scalars.count {
            if scalars[cursor] == target {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    private static func skipWhitespace(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
        var cursor = start
        while cursor < scalars.count, isWhitespace(scalars[cursor]) {
            cursor += 1
        }
        return cursor
    }

    private static func lowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        (0x41...0x5A).contains(scalar.value) ? Unicode.Scalar(scalar.value + 0x20) ?? scalar : scalar
    }

    /// Whether `scalar` is `[A-Za-z]`.
    static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    /// HTML white space: space, tab, line feed, form feed and carriage return.
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case " ", "\t", "\n", "\u{0C}", "\r": true
        default: false
        }
    }
}

// MARK: - HTMLTreeBuilder

/// Builds an element tree from tokens with the error recovery store content needs: end tags
/// without a matching open element are ignored, open elements are closed by their end tag's
/// ancestors, `p`, `li`, `dt`, `dd`, table rows and cells close implicitly like in browsers,
/// void elements never get children, and nesting deeper than `maximumDepth` is flattened so
/// that later recursive passes stay shallow.
enum HTMLTreeBuilder {
    /// The deepest nesting kept; deeper elements become siblings of their parent's children.
    static let maximumDepth = 96

    /// Elements that never have content.
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr",
    ]

    /// Elements that end an open paragraph when they start.
    static let paragraphClosers: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "dialog", "div", "dl", "fieldset", "figcaption",
        "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "main", "menu",
        "nav", "ol", "p", "pre", "section", "summary", "table", "ul",
    ]

    /// Inline elements, which an implicit paragraph end may cross.
    static let inlineElements: Set<String> = [
        "a", "abbr", "b", "bdi", "bdo", "big", "cite", "code", "data", "del", "dfn", "em", "font", "i", "ins", "kbd",
        "label", "mark", "nobr", "q", "s", "samp", "small", "span", "strike", "strong", "sub", "sup", "time", "tt", "u",
        "var",
    ]

    /// Builds the tree of `html` and returns its root (named `#root`).
    static func build(_ html: String) -> HTMLElementNode {
        let root = HTMLElementNode(name: "#root", attributes: [:])
        var stack: [HTMLElementNode] = [root]

        for token in HTMLTokenizer.tokens(html) {
            switch token {
            case let .text(text):
                stack[stack.count - 1].appendText(text)
            case let .startTag(name, attributes):
                closeImplicitly(before: name, stack: &stack)
                let element = HTMLElementNode(name: name, attributes: attributes)
                stack[stack.count - 1].children.append(.element(element))
                if !voidElements.contains(name), stack.count < maximumDepth {
                    stack.append(element)
                }
            case let .endTag(name):
                guard !voidElements.contains(name),
                      let index = stack.lastIndex(where: { $0.name == name }),
                      index > 0
                else { continue }
                stack.removeSubrange(index...)
            }
        }
        return root
    }

    /// Closes the elements the start tag `name` ends implicitly.
    private static func closeImplicitly(before name: String, stack: inout [HTMLElementNode]) {
        if paragraphClosers.contains(name) {
            close(["p"], stack: &stack) { !inlineElements.contains($0) && $0 != "p" }
        }
        switch name {
        case "li":
            close(["li"], stack: &stack) { ["ul", "ol", "menu", "table", "td", "th"].contains($0) }
        case "dt", "dd":
            close(["dt", "dd"], stack: &stack) { ["dl", "table", "td", "th"].contains($0) }
        case "tr":
            close(["tr"], stack: &stack) { ["table", "thead", "tbody", "tfoot"].contains($0) }
        case "td", "th":
            close(["td", "th"], stack: &stack) { ["tr", "table"].contains($0) }
        case "thead", "tbody", "tfoot":
            close(["thead", "tbody", "tfoot"], stack: &stack) { $0 == "table" }
        case "h1", "h2", "h3", "h4", "h5", "h6":
            if let current = stack.last?.name, ["h1", "h2", "h3", "h4", "h5", "h6"].contains(current) {
                stack.removeLast()
            }
        default:
            break
        }
    }

    /// Pops up to and including the nearest open element named in `names`, unless an element
    /// for which `isBoundary` holds comes first. The root is never popped.
    private static func close(_ names: Set<String>, stack: inout [HTMLElementNode], isBoundary: (String) -> Bool) {
        var index = stack.count - 1
        while index > 0 {
            let name = stack[index].name
            if names.contains(name) {
                stack.removeSubrange(index...)
                return
            }
            if isBoundary(name) {
                return
            }
            index -= 1
        }
    }
}
