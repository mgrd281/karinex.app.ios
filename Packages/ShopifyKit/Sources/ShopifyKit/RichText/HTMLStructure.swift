import Foundation

// MARK: - Layout hints

/// Recognizes the layouts the store builds its descriptions from and turns them into
/// structured blocks (facts, cards, steps, callouts, eyebrows, leads and notes).
///
/// The inline `style` attribute is only read here, as a hint; it never reaches the screen. Any
/// container that does not match a layout exactly falls back to the plain blocks, so unusual
/// markup is never lost, only shown less structured.
extension HTMLBlockBuilder {
    /// The structured blocks of a container, or `nil` when it matches no known layout.
    func structuredBlocks(_ element: HTMLElementNode) -> [HTMLBlock]? {
        let style = Self.style(of: element)
        if style["display"] == "grid", let grid = gridBlocks(element) {
            return grid
        }
        if let rows = rowBlocks(element) {
            return rows
        }
        if Self.hasLeadingBorder(style) {
            let inner = blocks(from: element.children)
            return inner.isEmpty ? [] : [.callout(inner)]
        }
        return nil
    }

    /// A paragraph, as an eyebrow, lead or note when its style says so.
    func styledParagraph(_ element: HTMLElementNode) -> [HTMLBlock] {
        let inner = blocks(from: element.children)
        guard inner.count == 1, case let .paragraph(inlines) = inner[0] else { return inner }
        let style = Self.style(of: element)
        if style["text-transform"] == "uppercase" {
            return [.eyebrow(inlines)]
        }
        if style["font-style"] == "italic" {
            return [.note(inlines)]
        }
        if let size = Self.pixels(style["font-size"]) {
            if size >= 17 {
                return [.lead(inlines)]
            }
            if size <= 13 {
                return [.note(inlines)]
            }
        }
        return inner
    }

    // MARK: Grids

    /// A grid of boxes: each box a heading with text (cards) or two paragraphs (facts).
    private func gridBlocks(_ element: HTMLElementNode) -> [HTMLBlock]? {
        guard let items = Self.elementChildren(of: element), items.count >= 2 else { return nil }
        var cards: [HTMLCard] = []
        var facts: [HTMLFact] = []
        for item in items {
            guard let parts = Self.elementChildren(of: item), parts.count >= 2 else { return nil }
            if Self.isHeading(parts[0]) {
                let title = inlines(of: parts[0])
                let body = blocks(from: parts.dropFirst().map { HTMLNode.element($0) })
                guard !title.isEmpty else { return nil }
                cards.append(HTMLCard(title: title, body: body))
            } else if parts.count == 2, parts[0].name == "p" {
                let label = inlines(of: parts[0])
                let value = blocks(from: parts[1].children)
                guard !label.isEmpty, !value.isEmpty else { return nil }
                facts.append(HTMLFact(label: label, value: value))
            } else {
                return nil
            }
        }
        if cards.count == items.count {
            return [.cards(cards)]
        }
        if facts.count == items.count {
            return [.facts(layout: .tiles, items: facts)]
        }
        return nil
    }

    // MARK: Rows

    /// Rows of two columns each: numbered rows become steps, the others label and value rows.
    private func rowBlocks(_ element: HTMLElementNode) -> [HTMLBlock]? {
        guard let rows = Self.elementChildren(of: element), rows.count >= 2 else { return nil }
        var pairs: [(first: HTMLElementNode, second: HTMLElementNode)] = []
        for row in rows {
            guard Self.style(of: row)["display"] == "flex",
                  let columns = Self.elementChildren(of: row), columns.count == 2 else { return nil }
            pairs.append((columns[0], columns[1]))
        }
        let numbers = pairs.map { Self.collapsedText(of: $0.first) }
        if numbers.allSatisfy(Self.isStepNumber) {
            let steps = zip(numbers, pairs).map { number, pair in
                HTMLStep(number: number, body: blocks(from: pair.second.children))
            }
            let filled = steps.filter { !$0.body.isEmpty }
            return filled.isEmpty ? [] : [.steps(filled)]
        }
        var facts: [HTMLFact] = []
        for pair in pairs {
            let label = inlines(of: pair.first)
            let value = blocks(from: pair.second.children)
            guard !label.isEmpty, !value.isEmpty else { return nil }
            facts.append(HTMLFact(label: label, value: value))
        }
        return [.facts(layout: .rows, items: facts)]
    }

    // MARK: Helpers

    /// The inline content of an element; images inside are dropped.
    private func inlines(of element: HTMLElementNode) -> [HTMLInline] {
        var images: [HTMLBlock] = []
        return InlineNormalizer.normalize(childPieces(of: element, hoistedImages: &images))
    }

    /// The element children of `element`, or `nil` when it also holds visible text.
    static func elementChildren(of element: HTMLElementNode) -> [HTMLElementNode]? {
        var result: [HTMLElementNode] = []
        for child in element.children {
            switch child {
            case let .text(text):
                if !text.unicodeScalars.allSatisfy(HTMLTokenizer.isWhitespace) {
                    return nil
                }
            case let .element(child):
                if !droppedElements.contains(child.name) {
                    result.append(child)
                }
            }
        }
        return result
    }

    /// Whether the element is a heading `h2` to `h6`.
    private static func isHeading(_ element: HTMLElementNode) -> Bool {
        ["h2", "h3", "h4", "h5", "h6"].contains(element.name)
    }

    /// Whether `text` is a row number such as "01", "2" or "3.".
    static func isStepNumber(_ text: String) -> Bool {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasSuffix(".") || digits.hasSuffix(")") {
            digits.removeLast()
        }
        return (1...3).contains(digits.count) && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Whether the style draws a visible border on the leading edge only.
    private static func hasLeadingBorder(_ style: [String: String]) -> Bool {
        guard let border = style["border-left"], style["border"] == nil else { return false }
        let parts = border.split(separator: " ")
        return !parts.contains("none") && !parts.contains("0") && !parts.contains("0px")
    }

    /// The declarations of an inline `style` attribute, with lower-case names and values.
    static func style(of element: HTMLElementNode) -> [String: String] {
        guard let attribute = element.attributes["style"] else { return [:] }
        var result: [String: String] = [:]
        for declaration in attribute.lowercased().split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, result[name] == nil {
                result[name] = value
            }
        }
        return result
    }

    /// The pixel size of a CSS length such as "18px", or `nil` for other units.
    static func pixels(_ value: String?) -> Double? {
        guard let value, value.hasSuffix("px") else { return nil }
        return Double(value.dropLast(2).trimmingCharacters(in: .whitespaces))
    }
}
