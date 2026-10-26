import SwiftUI

// MARK: - KXFlowLayout

/// Lays its subviews out in rows like the words of a paragraph: each at its ideal size, a new
/// row as soon as the next one does not fit, and every row aligned in the width (centered by
/// default) with its subviews centered on the row's height. For marks, chips and tags that
/// wrap, such as the payment marks below a buy button.
///
/// ```swift
/// KXFlowLayout {
///     ForEach(methods) { method in
///         PaymentMark(method: method)
///     }
/// }
/// ```
public struct KXFlowLayout: Layout {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat
    private let lineSpacing: CGFloat

    /// Creates the layout.
    ///
    /// - Parameters:
    ///   - alignment: How each row lines up in the width: `.center` (the default), `.leading`
    ///     or `.trailing`.
    ///   - spacing: The space between two subviews of a row.
    ///   - lineSpacing: The space between two rows.
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat = KXSpacing.xs, lineSpacing: CGFloat = KXSpacing.xs) {
        self.alignment = alignment
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(widths: sizes.map(\.width), maximumWidth: proposal.width ?? .infinity, spacing: spacing)
        let heights = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }
        let height = heights.reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map { Self.width(of: $0, in: sizes, spacing: spacing) }.max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in Self.rows(widths: sizes.map(\.width), maximumWidth: bounds.width, spacing: spacing) {
            let rowWidth = Self.width(of: row, in: sizes, spacing: spacing)
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x = if alignment == .leading {
                bounds.minX
            } else if alignment == .trailing {
                bounds.maxX - rowWidth
            } else {
                bounds.minX + (bounds.width - rowWidth) / 2
            }
            for index in row {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }

    /// The indices of the subviews in each row: as many as fit in `maximumWidth`, in order. A
    /// subview wider than `maximumWidth` gets a row of its own.
    static func rows(widths: [CGFloat], maximumWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var row: [Int] = []
        var rowWidth: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let widthWithSubview = row.isEmpty ? width : rowWidth + spacing + width
            // Half a point of tolerance, so rounding never moves a subview that fits.
            if !row.isEmpty, widthWithSubview > maximumWidth + 0.5 {
                rows.append(row)
                row = [index]
                rowWidth = width
            } else {
                row.append(index)
                rowWidth = widthWithSubview
            }
        }
        if !row.isEmpty {
            rows.append(row)
        }
        return rows
    }

    /// The width of a row: its subviews and the spacing between them.
    private static func width(of row: [Int], in sizes: [CGSize], spacing: CGFloat) -> CGFloat {
        row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0))
    }
}
