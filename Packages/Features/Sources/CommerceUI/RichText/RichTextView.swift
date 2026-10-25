import DesignSystem
import DesignTokens
import Foundation
import ShopifyKit
import SwiftUI

// MARK: - RichTextView

/// Renders Shopify rich text (`descriptionHtml`, `contentHtml`) natively from an
/// `HTMLDocument`: bold headings, body paragraphs, bulleted and numbered lists, tables as real
/// grids that scroll horizontally when they are wider than the screen, quotes with an ink rule,
/// images through ``ProductImage`` and hairline rules.
///
/// Inline formatting keeps bold, italic and code. Only `http` and `https` links are tappable
/// (opened through the `openURL` environment action); the parser already turned every other
/// scheme into plain text. Everything scales with Dynamic Type and wraps instead of clipping.
///
/// ```swift
/// RichTextView(document: HTMLDocument(html: product.descriptionHtml))
/// ```
public struct RichTextView: View {
    private let blocks: [HTMLBlock]

    /// Creates the view for a parsed document.
    public init(document: HTMLDocument) {
        blocks = document.blocks
    }

    /// Creates the view for raw HTML. Prefer parsing once in the view model with
    /// ``init(document:)`` for long texts.
    public init(html: String) {
        self.init(document: HTMLDocument(html: html))
    }

    public var body: some View {
        RichTextBlockList(blocks: blocks)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Blocks

/// A vertical stack of blocks; recursive for list items and quotes.
private struct RichTextBlockList: View {
    let blocks: [HTMLBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                RichTextBlockView(block: block)
            }
        }
    }
}

/// One block.
private struct RichTextBlockView: View {
    let block: HTMLBlock

    var body: some View {
        switch block {
        case let .heading(level, inlines):
            RichTextInlineText(inlines: inlines)
                .kxFont(RichTextStyle.headingStyle(level: level))
                .foregroundStyle(KXColor.textPrimary)
                .padding(.top, level <= 2 ? KXSpacing.xs : 0)
                .accessibilityAddTraits(.isHeader)
        case let .paragraph(inlines):
            if !RichTextStyle.isBlank(inlines) {
                RichTextInlineText(inlines: inlines)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textPrimary)
            }
        case let .list(ordered, items):
            RichTextList(ordered: ordered, items: items)
        case let .table(rows):
            RichTextTable(rows: rows)
        case let .quote(blocks):
            RichTextQuote(blocks: blocks)
        case let .image(url, alt):
            ProductImage(url: url, altText: alt)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous))
        case .rule:
            KXDivider()
                .padding(.vertical, KXSpacing.xs)
        }
    }
}

/// Inline content as one `Text`, so it wraps and scales like any paragraph.
private struct RichTextInlineText: View {
    let inlines: [HTMLInline]

    var body: some View {
        Text(RichTextStyle.attributedString(for: inlines))
            .tint(KXColor.accentText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lists

private struct RichTextList: View {
    let ordered: Bool
    let items: [[HTMLBlock]]

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                    Text(verbatim: ordered ? "\(index + 1)." : "\u{2022}")
                        .kxFont(.body)
                        .monospacedDigit()
                        .foregroundStyle(ordered ? KXColor.textSecondary : KXColor.accentText)
                        .accessibilityHidden(!ordered)
                    RichTextBlockList(blocks: item)
                }
            }
        }
        .padding(.leading, KXSpacing.xxs)
    }
}

// MARK: - Quotes

private struct RichTextQuote: View {
    let blocks: [HTMLBlock]

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.s) {
            Rectangle()
                .fill(KXColor.accent)
                .frame(width: KXBorder.emphasis)
                .accessibilityHidden(true)
            RichTextBlockList(blocks: blocks)
                .italic()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Tables

/// A table as a `Grid`. When it is wider than the available space it scrolls horizontally;
/// cells never truncate.
private struct RichTextTable: View {
    let rows: [[HTMLTableCell]]

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid
            ScrollView(.horizontal) {
                grid
                    .padding(.bottom, KXSpacing.xs)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var grid: some View {
        let columnCount = rows.map(\.count).max() ?? 0
        return Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        cell(column < row.count ? row[column] : nil, isFirstRow: rowIndex == 0)
                    }
                }
                if rowIndex < rows.count - 1 {
                    Rectangle()
                        .fill(KXColor.hairline)
                        .frame(height: 1 / max(displayScale, 1))
                        .gridCellUnsizedAxes(.horizontal)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(KXColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
                .strokeBorder(KXColor.hairline, lineWidth: 1 / max(displayScale, 1))
        }
    }

    @ViewBuilder
    private func cell(_ cell: HTMLTableCell?, isFirstRow: Bool) -> some View {
        let isHeader = cell?.isHeader ?? false
        RichTextInlineText(inlines: cell?.inlines ?? [])
            .kxFont(isHeader ? .headline : .subheadline)
            .foregroundStyle(KXColor.textPrimary)
            .frame(minWidth: 96, maxWidth: 280, alignment: .leading)
            .padding(.horizontal, KXSpacing.s)
            .padding(.vertical, KXSpacing.xs)
            .background(isHeader && isFirstRow ? KXColor.surfaceElevated : Color.clear)
            .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
}

// MARK: - Styling

/// The mapping from HTML to typography and attributed strings.
enum RichTextStyle {
    /// The typography token of a heading level: `h1` and `h2` large titles, `h3` a title, deeper
    /// levels the sans headline.
    static func headingStyle(level: Int) -> TypographyToken {
        switch level {
        case ...2:
            .title2
        case 3:
            .title3
        default:
            .headline
        }
    }

    /// Whether the inlines contain no visible text.
    static func isBlank(_ inlines: [HTMLInline]) -> Bool {
        plainText(inlines).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The text of the inlines without formatting.
    static func plainText(_ inlines: [HTMLInline]) -> String {
        inlines.map { inline in
            switch inline {
            case let .text(text), let .code(text):
                text
            case let .strong(children), let .emphasis(children), let .link(_, children):
                plainText(children)
            case .lineBreak:
                "\n"
            }
        }
        .joined()
    }

    /// The attributed string of the inlines: bold, italic and code as inline presentation
    /// intents, `http`/`https` links as tappable, underlined links, every other link as text.
    static func attributedString(for inlines: [HTMLInline], intent: InlinePresentationIntent = []) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            switch inline {
            case let .text(text):
                result += styled(text, intent: intent)
            case let .strong(children):
                result += attributedString(for: children, intent: intent.union(.stronglyEmphasized))
            case let .emphasis(children):
                result += attributedString(for: children, intent: intent.union(.emphasized))
            case let .code(text):
                result += styled(text, intent: intent.union(.code))
            case let .link(url, children):
                var linked = attributedString(for: children, intent: intent)
                if isTappable(url) {
                    linked.link = url
                    linked.underlineStyle = .single
                }
                result += linked
            case .lineBreak:
                result += AttributedString("\n")
            }
        }
        return result
    }

    /// Whether a link may be opened: only web links.
    static func isTappable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func styled(_ text: String, intent: InlinePresentationIntent) -> AttributedString {
        var string = AttributedString(text)
        if !intent.isEmpty {
            string.inlinePresentationIntent = intent
        }
        return string
    }
}

// MARK: - Previews

// A shortened excerpt of the recorded Office 2024 Professional Plus description (DE/DE), as
// blocks so the preview does not depend on the parser.
private let richTextPreviewBlocks: [HTMLBlock] = [
    .heading(level: 2, inlines: [.text("Microsoft Office 2024 Professional Plus")]),
    .paragraph([
        .text("Die "), .strong([.text("Dauerlizenz")]), .text(" für einen PC. Mehr dazu im "),
        .link(url: URL(string: "https://www.karinex.de/blogs/guides") ?? URL(fileURLWithPath: "/"), [.text("Ratgeber")]),
        .text("."),
    ]),
    .list(ordered: false, items: [
        [.paragraph([.text("Word, Excel, PowerPoint, Outlook")])],
        [.paragraph([.text("Access und Publisher")])],
    ]),
    .table(rows: [
        [HTMLTableCell(isHeader: true, inlines: [.text("Merkmal")]), HTMLTableCell(isHeader: true, inlines: [.text("Wert")])],
        [HTMLTableCell(isHeader: false, inlines: [.text("Lizenz")]), HTMLTableCell(isHeader: false, inlines: [.text("Dauerlizenz")])],
    ]),
    .rule,
]

#Preview("RichTextView") {
    ScrollView {
        RichTextBlockList(blocks: richTextPreviewBlocks)
            .padding(KXSpacing.gutter)
    }
    .kxScreenBackground()
}

#Preview("RichTextView, dark, accessibility size") {
    ScrollView {
        RichTextBlockList(blocks: richTextPreviewBlocks)
            .padding(KXSpacing.gutter)
    }
    .kxScreenBackground()
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}
