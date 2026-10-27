import ShopifyKit

// MARK: - LegalSection

/// One section of a legal text: a heading and the blocks up to the next heading of the same
/// level, e.g. "§ 3 Widerrufsrecht" with its paragraphs.
struct LegalSection: Identifiable, Equatable {
    /// The position in the text, also the scroll target of the table of contents.
    let id: Int
    /// The heading text, e.g. "3. Widerrufsrecht".
    let title: String
    /// Everything below the heading, including lower headings.
    let blocks: [HTMLBlock]
}

// MARK: - LegalOutline

/// Splits a legal text into sections the way the KARINEX website shows it: a table of contents
/// and one panel per section. The section level is the highest heading level that occurs at
/// least twice (a text with a single `h2` and many `h3` uses the `h3`); a leading heading that
/// repeats the document title is dropped. Texts without such headings stay one block.
enum LegalOutline {
    /// The blocks before the first section, and the sections.
    static func split(_ blocks: [HTMLBlock], title: String) -> (intro: [HTMLBlock], sections: [LegalSection]) {
        var blocks = blocks
        if case let .heading(_, inlines) = blocks.first, normalized(plainText(inlines)) == normalized(title) {
            blocks.removeFirst()
        }
        guard let level = sectionLevel(blocks) else { return (blocks, []) }

        var intro: [HTMLBlock] = []
        var sections: [LegalSection] = []
        var currentTitle: String?
        var current: [HTMLBlock] = []
        for block in blocks {
            if case let .heading(blockLevel, inlines) = block, blockLevel == level {
                if let currentTitle {
                    sections.append(LegalSection(id: sections.count, title: currentTitle, blocks: current))
                }
                currentTitle = plainText(inlines).trimmingCharacters(in: .whitespacesAndNewlines)
                current = []
            } else if currentTitle == nil {
                intro.append(block)
            } else {
                current.append(block)
            }
        }
        if let currentTitle {
            sections.append(LegalSection(id: sections.count, title: currentTitle, blocks: current))
        }
        return (intro, sections)
    }

    /// The highest heading level that occurs at least twice, `nil` when there is none.
    static func sectionLevel(_ blocks: [HTMLBlock]) -> Int? {
        var counts: [Int: Int] = [:]
        for case let .heading(level, inlines) in blocks where !plainText(inlines).trimmingCharacters(in: .whitespaces).isEmpty {
            counts[level, default: 0] += 1
        }
        return counts.filter { $0.value >= 2 }.keys.min()
    }

    /// The text of inlines without formatting.
    static func plainText(_ inlines: [HTMLInline]) -> String {
        inlines.map { inline in
            switch inline {
            case let .text(text), let .code(text):
                text
            case let .strong(children), let .emphasis(children), let .link(_, children):
                plainText(children)
            case .lineBreak:
                " "
            }
        }
        .joined()
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
