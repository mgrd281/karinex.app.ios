import SwiftUI

// MARK: - KXTrustItem

/// One fact in a ``KXTrustStrip``: an SF Symbol and a short, already-localized text such as
/// "Lieferung per E-Mail in Minuten".
///
/// Items with a condition (for example "100 Tage Geld-zurück") carry a footnote marker and an
/// `onTap` action that presents the condition, so that it is always one tap away.
public struct KXTrustItem: Identifiable {
    /// Stable identity. Defaults to the text; must be unique within one strip.
    public let id: String
    /// SF Symbol name shown in the gold ring, e.g. `"envelope"`. Decorative.
    public let systemImage: String
    /// The already-localized fact, without the footnote marker.
    public let text: String
    /// Optional marker appended to the text, e.g. `"*"`. Visual only: VoiceOver reads the text
    /// and the hint instead.
    public let footnoteMarker: String?
    /// Optional already-localized VoiceOver hint for an interactive item. Defaults to
    /// "Zeigt weitere Informationen an." when `onTap` is set.
    public let accessibilityHint: String?
    /// Called when the item is tapped. When `nil` the item is static text.
    public let onTap: (@MainActor () -> Void)?

    /// Creates a trust item.
    ///
    /// - Parameters:
    ///   - systemImage: SF Symbol name, e.g. `"envelope"`, `"creditcard"`.
    ///   - text: The already-localized fact.
    ///   - footnoteMarker: Optional marker appended to the text, e.g. `"*"`.
    ///   - accessibilityHint: Optional already-localized hint for the tap action.
    ///   - id: Stable identity. Defaults to `text`.
    ///   - onTap: Optional action, typically presenting the condition behind the marker.
    public init(
        systemImage: String,
        text: String,
        footnoteMarker: String? = nil,
        accessibilityHint: String? = nil,
        id: String? = nil,
        onTap: (@MainActor () -> Void)? = nil
    ) {
        self.id = id ?? text
        self.systemImage = systemImage
        self.text = text
        self.footnoteMarker = footnoteMarker
        self.accessibilityHint = accessibilityHint
        self.onTap = onTap
    }

    /// The text as displayed, including the footnote marker.
    var displayText: String {
        guard let footnoteMarker, !footnoteMarker.isEmpty else { return text }
        return text + footnoteMarker
    }
}

// MARK: - KXTrustStrip

/// A set of short trust facts (delivery, payment methods, money-back condition, support
/// hours), each an SF Symbol in a gold ring above a short text on a cream tile.
///
/// Arrangements:
/// - ``Arrangement/grid``: two columns with equal row heights (the 2x2 grid of the Start tab).
///   Place it inside the screen gutters like any other content.
/// - ``Arrangement/carousel``: one horizontally scrolling row that snaps to tiles. Place it edge
///   to edge (without horizontal padding); it applies the standard gutter as content margins.
///
/// At accessibility text sizes both arrangements become a single column of full-width rows so
/// that no text is truncated.
///
/// Items with `onTap` are buttons: they show an info glyph, and VoiceOver reads the text with
/// the button trait and a hint. Static items are read as plain text.
///
/// ```swift
/// KXTrustStrip(items: [
///     KXTrustItem(systemImage: "envelope", text: deliveryText),
///     KXTrustItem(systemImage: "arrow.uturn.backward", text: refundText, footnoteMarker: "*") {
///         isRefundConditionPresented = true
///     },
/// ])
/// ```
public struct KXTrustStrip: View {
    /// Layout of a ``KXTrustStrip``.
    public enum Arrangement: String, CaseIterable, Sendable {
        /// Two columns with equal row heights.
        case grid
        /// A single horizontally scrolling row.
        case carousel
    }

    private let items: [KXTrustItem]
    private let arrangement: Arrangement

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var carouselTileWidth: CGFloat = 168

    /// Creates a trust strip.
    ///
    /// - Parameters:
    ///   - items: The facts in display order. Their ids must be unique.
    ///   - arrangement: Layout. Defaults to ``Arrangement/grid``.
    public init(items: [KXTrustItem], arrangement: Arrangement = .grid) {
        self.items = items
        self.arrangement = arrangement
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                list
            } else {
                switch arrangement {
                case .grid:
                    grid
                case .carousel:
                    carousel
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Arrangements

    private var grid: some View {
        VStack(spacing: KXSpacing.s) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                HStack(alignment: .top, spacing: KXSpacing.s) {
                    KXTrustTile(item: items[start], layout: .stacked)
                    if start + 1 < items.count {
                        KXTrustTile(item: items[start + 1], layout: .stacked)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                // Equal tile heights within a row.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: KXSpacing.s) {
                ForEach(items) { item in
                    KXTrustTile(item: item, layout: .stacked)
                        .frame(width: carouselTileWidth)
                }
            }
            .scrollTargetLayout()
            // Equal tile heights across the row.
            .fixedSize(horizontal: false, vertical: true)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, KXSpacing.gutter, for: .scrollContent)
    }

    private var list: some View {
        VStack(spacing: KXSpacing.s) {
            ForEach(items) { item in
                KXTrustTile(item: item, layout: .inline)
            }
        }
        // The carousel is placed edge to edge, so the stacked fallback adds the gutter itself.
        .padding(.horizontal, arrangement == .carousel ? KXSpacing.gutter : 0)
    }
}

// MARK: - Tile

private struct KXTrustTile: View {
    enum TileLayout {
        /// Icon above the text (grid and carousel).
        case stacked
        /// Icon leading the text (single-column fallback).
        case inline
    }

    let item: KXTrustItem
    let layout: TileLayout

    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 36

    var body: some View {
        if let onTap = item.onTap {
            Button {
                onTap()
            } label: {
                tile(isInteractive: true)
            }
            .buttonStyle(KXTrustTileButtonStyle())
            .accessibilityLabel(Text(item.text))
            .accessibilityHint(hintText)
        } else {
            tile(isInteractive: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(item.text))
        }
    }

    private var hintText: Text {
        if let hint = item.accessibilityHint, !hint.isEmpty {
            return Text(hint)
        }
        return Text("kx.trust.hint.details", bundle: .module)
    }

    @ViewBuilder
    private func tile(isInteractive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
        Group {
            switch layout {
            case .stacked:
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    HStack(alignment: .top, spacing: KXSpacing.xs) {
                        icon
                        Spacer(minLength: 0)
                        if isInteractive {
                            infoGlyph
                        }
                    }
                    label
                }
            case .inline:
                HStack(alignment: .center, spacing: KXSpacing.s) {
                    icon
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isInteractive {
                        infoGlyph
                    }
                }
            }
        }
        .padding(KXSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minHeight: KXSpacing.minimumTapTarget)
        .background(KXColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(KXColor.hairline, lineWidth: 1 / max(displayScale, 1))
        }
        .contentShape(shape)
    }

    private var icon: some View {
        Image(systemName: item.systemImage)
            .font(KXFont.font(.headline, size: Double(iconSize * 0.45)))
            .foregroundStyle(KXColor.brand)
            .frame(width: iconSize, height: iconSize)
            .overlay {
                Circle().strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
            }
            .accessibilityHidden(true)
    }

    private var infoGlyph: some View {
        Image(systemName: "info.circle")
            .font(KXFont.font(.subheadline, size: Double(iconSize * 0.42)))
            .foregroundStyle(KXColor.accentText)
            .accessibilityHidden(true)
    }

    private var label: some View {
        Text(item.displayText)
            .kxFont(.subheadline)
            .foregroundStyle(KXColor.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Dims an interactive tile while it is pressed.
private struct KXTrustTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Previews

/// The four facts of the Start tab (PROMPT.md section 6.1). The money-back item carries its
/// footnote marker and opens the condition on tap.
private struct KXTrustStripPreviewGallery: View {
    private let items: [KXTrustItem] = [
        KXTrustItem(systemImage: "envelope", text: "Lieferung per E-Mail in Minuten"),
        KXTrustItem(systemImage: "creditcard", text: "Apple Pay, Kreditkarte, Klarna"),
        KXTrustItem(systemImage: "arrow.uturn.backward", text: "100 Tage Geld-zurück", footnoteMarker: "*") {},
        KXTrustItem(systemImage: "bubble.left.and.bubble.right", text: "Support Mo. bis So., 06:00 bis 23:00 Uhr deutscher Zeit"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXTrustStrip(items: items)
                    .padding(.horizontal, KXSpacing.gutter)
                KXTrustStrip(items: items, arrangement: .carousel)
            }
            .padding(.vertical, KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXTrustStrip, light") {
    KXTrustStripPreviewGallery()
}

#Preview("KXTrustStrip, dark") {
    KXTrustStripPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXTrustStrip, accessibility size") {
    KXTrustStripPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
