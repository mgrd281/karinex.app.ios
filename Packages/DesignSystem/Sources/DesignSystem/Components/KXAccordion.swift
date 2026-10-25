import SwiftUI

// MARK: - KXAccordionItem

/// One expandable row of a ``KXAccordion``: a title that toggles the row and the content
/// revealed below it.
///
/// ```swift
/// KXAccordionItem(title: entry.question, text: entry.answer)
/// KXAccordionItem(title: activationTitle) { ActivationSteps(product: product) }
/// ```
public struct KXAccordionItem: Identifiable {
    /// Stable identity of the row, used to remember which rows are expanded. Must be unique
    /// within one accordion. Defaults to the title.
    public let id: String
    /// The already-localized row title, e.g. an FAQ question.
    public let title: String
    /// The type-erased content shown while the row is expanded.
    let content: AnyView

    /// Creates a row with custom content.
    ///
    /// The content inherits the body text style (`kxFont(.body)`, `textSecondary`); override
    /// it inside the content where needed.
    ///
    /// - Parameters:
    ///   - title: The already-localized row title.
    ///   - id: Stable identity. Defaults to `title`; pass an explicit value when titles can
    ///     repeat or change while the accordion is on screen.
    ///   - content: The content revealed when the row is expanded.
    @MainActor
    public init(title: String, id: String? = nil, @ViewBuilder content: () -> some View) {
        self.id = id ?? title
        self.title = title
        self.content = AnyView(content())
    }

    /// Creates a row whose content is a paragraph of already-localized text, e.g. an FAQ
    /// answer from the `karinex.faq` metafield.
    ///
    /// - Parameters:
    ///   - title: The already-localized row title.
    ///   - text: The already-localized text revealed when the row is expanded.
    ///   - id: Stable identity. Defaults to `title`.
    @MainActor
    public init(title: String, text: String, id: String? = nil) {
        self.init(title: title, id: id) {
            Text(text)
        }
    }
}

// MARK: - KXAccordion

/// A list of expandable rows separated by hairlines, each with a gold "+" that turns into an
/// "x" while the row is open. Used for the product FAQ and other progressive disclosure.
///
/// Expansion is either ``Expansion/single`` (opening a row closes the others) or
/// ``Expansion/multiple``. The accordion keeps its own state, or you can own it through the
/// `expandedIDs` binding, for example to open a row from a deep link.
///
/// Each title is a button for VoiceOver with the value "Ausgeklappt" or "Eingeklappt" and a
/// hint describing the action. The content slides in with a snappy spring; with Reduce Motion
/// it cross-fades and the "+" swaps to an "x" without rotating.
///
/// ```swift
/// KXAccordion(items: faq.map { KXAccordionItem(title: $0.question, text: $0.answer) }, expansion: .single)
/// ```
public struct KXAccordion: View {
    /// How many rows can be open at the same time.
    public enum Expansion: String, CaseIterable, Sendable {
        /// Opening a row closes the previously open row.
        case single
        /// Rows open and close independently.
        case multiple
    }

    private let items: [KXAccordionItem]
    private let expansion: Expansion
    private let externalExpandedIDs: Binding<Set<String>>?
    @State private var internalExpandedIDs: Set<String>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// Creates an accordion that manages its expansion state itself.
    ///
    /// - Parameters:
    ///   - items: The rows in display order. Their ids must be unique.
    ///   - expansion: Whether one or several rows can be open. Defaults to
    ///     ``Expansion/multiple``.
    ///   - initiallyExpanded: Ids of the rows that start open. In ``Expansion/single`` mode only
    ///     the first matching row (in display order) opens.
    public init(items: [KXAccordionItem], expansion: Expansion = .multiple, initiallyExpanded: Set<String> = []) {
        self.items = items
        self.expansion = expansion
        externalExpandedIDs = nil
        _internalExpandedIDs = State(
            initialValue: Self.normalized(initiallyExpanded, items: items, expansion: expansion)
        )
    }

    /// Creates an accordion whose expansion state is owned by the caller.
    ///
    /// - Parameters:
    ///   - items: The rows in display order. Their ids must be unique.
    ///   - expansion: Whether one or several rows can be open. Defaults to
    ///     ``Expansion/multiple``. The accordion enforces it when the user toggles a row.
    ///   - expandedIDs: The ids of the open rows.
    public init(items: [KXAccordionItem], expansion: Expansion = .multiple, expandedIDs: Binding<Set<String>>) {
        self.items = items
        self.expansion = expansion
        externalExpandedIDs = expandedIDs
        _internalExpandedIDs = State(initialValue: [])
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rule
            ForEach(items) { item in
                KXAccordionRow(item: item, isExpanded: expandedIDs.contains(item.id)) {
                    toggle(item.id)
                }
                rule
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: State

    private var expandedIDs: Set<String> {
        externalExpandedIDs?.wrappedValue ?? internalExpandedIDs
    }

    private func setExpandedIDs(_ ids: Set<String>) {
        if let externalExpandedIDs {
            externalExpandedIDs.wrappedValue = ids
        } else {
            internalExpandedIDs = ids
        }
    }

    private func toggle(_ id: String) {
        var ids = expandedIDs
        if ids.contains(id) {
            ids.remove(id)
        } else if expansion == .single {
            ids = [id]
        } else {
            ids.insert(id)
        }
        withAnimation(KXMotion.animation(.snappy, reduceMotion: reduceMotion)) {
            setExpandedIDs(ids)
        }
    }

    /// Restricts the initial selection to existing rows, and to the first one in single mode.
    private static func normalized(_ ids: Set<String>, items: [KXAccordionItem], expansion: Expansion) -> Set<String> {
        let existing = items.map(\.id).filter { ids.contains($0) }
        switch expansion {
        case .single: return Set(existing.prefix(1))
        case .multiple: return Set(existing)
        }
    }

    // MARK: Parts

    private var rule: some View {
        Rectangle()
            .fill(KXColor.divider)
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Row

private struct KXAccordionRow: View {
    let item: KXAccordionItem
    let isExpanded: Bool
    let onToggle: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var toggleSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onToggle()
            } label: {
                HStack(alignment: .center, spacing: KXSpacing.m) {
                    Text(item.title)
                        .kxFont(.headline)
                        .foregroundStyle(KXColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    toggleGlyph
                }
                .padding(.vertical, KXSpacing.m)
                .frame(minHeight: KXSpacing.minimumTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(KXAccordionRowButtonStyle())
            .accessibilityValue(stateText)
            .accessibilityHint(hintText)

            if isExpanded {
                item.content
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, KXSpacing.m)
                    .transition(contentTransition)
            }
        }
        .clipped()
    }

    /// Gold "+" in a gold ring. It rotates by 45 degrees into an "x"; with Reduce Motion the
    /// symbol swaps without rotating.
    private var toggleGlyph: some View {
        Image(systemName: reduceMotion && isExpanded ? "xmark" : "plus")
            .font(KXFont.font(.headline, size: Double(toggleSize * 0.46)))
            .foregroundStyle(KXColor.accentText)
            .rotationEffect(.degrees(!reduceMotion && isExpanded ? 45 : 0))
            .frame(width: toggleSize, height: toggleSize)
            .overlay {
                Circle().strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
            }
            .accessibilityHidden(true)
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .move(edge: .top))
    }

    private var stateText: Text {
        isExpanded ? Text("kx.accordion.expanded", bundle: .module) : Text("kx.accordion.collapsed", bundle: .module)
    }

    private var hintText: Text {
        isExpanded ? Text("kx.accordion.hint.collapse", bundle: .module) : Text("kx.accordion.hint.expand", bundle: .module)
    }
}

/// Dims the row title while it is pressed; the row itself stays in place.
private struct KXAccordionRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Previews

/// Sample questions and answers restate the business facts of PROMPT.md section 2 (delivery,
/// payment methods, support hours, refund condition); they are not product claims.
private struct KXAccordionPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXAccordion(
                    items: [
                        KXAccordionItem(
                            title: "Wie erhalte ich meinen Lizenzschlüssel?",
                            text: "Nach der Zahlung erhalten Sie den Schlüssel und die Rechnung per E-Mail."
                        ),
                        KXAccordionItem(
                            title: "Welche Zahlungsarten stehen zur Verfügung?",
                            text: "Apple Pay, Kreditkarte und Klarna."
                        ),
                        KXAccordionItem(
                            title: "Wann ist der Support erreichbar?",
                            text: "Montag bis Sonntag, 06:00 bis 23:00 Uhr deutscher Zeit, per WhatsApp, E-Mail und Live-Chat."
                        ),
                    ],
                    expansion: .single,
                    initiallyExpanded: ["Wie erhalte ich meinen Lizenzschlüssel?"]
                )
                KXAccordion(items: [
                    KXAccordionItem(title: "100 Tage Geld-zurück") {
                        VStack(alignment: .leading, spacing: KXSpacing.xs) {
                            Text(verbatim: "Gilt nur für aktivierte Lizenzschlüssel und physische Ware.")
                            Text(verbatim: "Zugestellte, nicht aktivierte Schlüssel werden nicht freiwillig erstattet.")
                            Text(verbatim: "Ihre gesetzlichen Gewährleistungsrechte bleiben unberührt.")
                                .kxFont(.footnote)
                        }
                    },
                ])
            }
            .padding(KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXAccordion, light") {
    KXAccordionPreviewGallery()
}

#Preview("KXAccordion, dark") {
    KXAccordionPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXAccordion, accessibility size") {
    KXAccordionPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
