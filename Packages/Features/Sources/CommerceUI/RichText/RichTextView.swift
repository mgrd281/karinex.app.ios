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
/// The structured blocks the parser recognizes in the store layout get their own calm
/// presentation: an uppercase eyebrow, larger lead paragraphs, key facts as tiles or label and
/// value rows, titled cards, numbered steps with a round number, highlighted callouts on a grey
/// panel and small notes. Section headings get extra air above them.
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
                .padding(.top, level == 2 ? KXSpacing.m : 0)
                .accessibilityAddTraits(.isHeader)
        case let .eyebrow(inlines):
            RichTextInlineText(inlines: inlines)
                .kxFont(.eyebrow)
                .textCase(.uppercase)
                .foregroundStyle(KXColor.textTertiary)
        case let .lead(inlines):
            RichTextInlineText(inlines: inlines)
                .kxFont(.title3)
                .fontWeight(.regular)
                .foregroundStyle(KXColor.textPrimary)
        case let .note(inlines):
            RichTextInlineText(inlines: inlines)
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textTertiary)
        case let .facts(layout, facts):
            switch layout {
            case .tiles:
                RichTextFactTiles(facts: facts)
            case .rows:
                RichTextFactRows(facts: facts)
            }
        case let .cards(cards):
            RichTextCards(cards: cards)
        case let .steps(steps):
            RichTextSteps(steps: steps)
        case let .callout(blocks):
            KXCard {
                RichTextBlockList(blocks: blocks)
            }
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

// MARK: - Facts, cards and steps

/// Short facts as tiles in two columns (one column at large text sizes).
private struct RichTextFactTiles: View {
    let facts: [HTMLFact]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: KXSpacing.xs, alignment: .top),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
        LazyVGrid(columns: columns, alignment: .leading, spacing: KXSpacing.xs) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    RichTextInlineText(inlines: fact.label)
                        .kxFont(.caption)
                        .foregroundStyle(KXColor.textTertiary)
                    RichTextValue(blocks: fact.value)
                        .kxFont(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(KXColor.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .padding(KXSpacing.s)
                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Facts with longer values: label above value, rows separated by hairlines on a grey panel.
private struct RichTextFactRows: View {
    let facts: [HTMLFact]

    var body: some View {
        KXCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        RichTextInlineText(inlines: fact.label)
                            .kxFont(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(KXColor.textTertiary)
                        RichTextValue(blocks: fact.value)
                            .kxFont(.subheadline)
                            .foregroundStyle(KXColor.textPrimary)
                    }
                    .padding(.horizontal, KXSpacing.m)
                    .padding(.vertical, KXSpacing.s)
                    .accessibilityElement(children: .combine)
                    if index < facts.count - 1 {
                        KXDivider()
                            .padding(.leading, KXSpacing.m)
                    }
                }
            }
        }
    }
}

/// Titled boxes: one column on the phone, two side by side when there is room.
private struct RichTextCards: View {
    let cards: [HTMLCard]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: KXSpacing.xs, alignment: .top)],
            alignment: .leading,
            spacing: KXSpacing.xs
        ) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    RichTextInlineText(inlines: card.title)
                        .kxFont(.headline)
                        .foregroundStyle(KXColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    RichTextValue(blocks: card.body)
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(KXSpacing.m)
                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Numbered rows: the store's number in a round ink badge, the text beside it.
private struct RichTextSteps: View {
    let steps: [HTMLStep]

    var body: some View {
        KXCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: KXSpacing.s) {
                        Text(verbatim: step.number)
                            .kxFont(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(KXColor.textOnBrand)
                            .frame(minWidth: 28, minHeight: 28)
                            .background(KXColor.brand, in: Circle())
                        RichTextValue(blocks: step.body)
                            .kxFont(.subheadline)
                            .foregroundStyle(KXColor.textPrimary)
                            .padding(.top, KXSpacing.xxs)
                    }
                    .padding(.horizontal, KXSpacing.m)
                    .padding(.vertical, KXSpacing.s)
                    .accessibilityElement(children: .combine)
                    if index < steps.count - 1 {
                        KXDivider()
                            .padding(.leading, KXSpacing.m + 28 + KXSpacing.s)
                    }
                }
            }
        }
    }
}

/// The blocks of a value or card text, taking the font and color of the surrounding view:
/// paragraphs as plain text, anything else (lists, links in paragraphs) as regular blocks.
private struct RichTextValue: View {
    let blocks: [HTMLBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .paragraph(inlines), let .lead(inlines), let .note(inlines), let .eyebrow(inlines):
                    RichTextInlineText(inlines: inlines)
                default:
                    RichTextBlockView(block: block)
                }
            }
        }
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
    /// intents, `http`/`https` links as tappable bold links without underline (owner decision 2026-10-28), every other link as text.
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
                let tappable = isTappable(url)
                var linked = attributedString(for: children, intent: tappable ? intent.union(.stronglyEmphasized) : intent)
                if tappable {
                    linked.link = url
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
    .eyebrow([.text("Microsoft Office 2024 Professional Plus")]),
    .heading(level: 1, inlines: [.text("Office 2024 Professional Plus kaufen")]),
    .lead([.text("Die aktuelle Office-Suite mit Word, Excel, PowerPoint und Outlook als Dauerlizenz.")]),
    .facts(layout: .tiles, items: [
        HTMLFact(label: [.text("Lizenztyp")], value: [.paragraph([.text("Dauerlizenz (LTSC)")])]),
        HTMLFact(label: [.text("Lieferung")], value: [.paragraph([.text("Sofort per E-Mail")])]),
    ]),
    .steps([
        HTMLStep(number: "01", body: [.paragraph([.strong([.text("E-Mail prüfen")]), .text(" und den Schlüssel kopieren.")])]),
        HTMLStep(number: "02", body: [.paragraph([.strong([.text("Installer laden")]), .text(" vom Microsoft-Server.")])]),
    ]),
    .cards([
        HTMLCard(title: [.text("Word 2024")], body: [.paragraph([.text("Textverarbeitung mit Dark Mode.")])]),
        HTMLCard(title: [.text("Excel 2024")], body: [.paragraph([.text("Tabellen mit dynamischen Arrays.")])]),
    ]),
    .callout([.paragraph([.strong([.text("Lizenzart")])]), .paragraph([.text("Vollversion zur dauerhaften Nutzung.")])]),
    .note([.text("Es erfolgt kein physischer Versand.")]),
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
