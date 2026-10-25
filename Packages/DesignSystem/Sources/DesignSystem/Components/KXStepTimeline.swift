import SwiftUI

// MARK: - KXStepTimeline

/// A numbered sequence of steps connected by hairlines.
///
/// Use it for process explanations such as "So läuft es ab" (Bestellen, Bezahlen, Schlüssel per
/// E-Mail) and for progress timelines such as the order status (Bestellt, Bezahlt, Lizenz
/// versendet).
///
/// Every step shows its number in a circle:
/// - Steps without a ``Step/State`` are informational: a gold numeral (`accentText`) in a gold
///   ring, joined by gold hairlines. VoiceOver reads no progress state.
/// - ``Step/State/done``: a gold disc with an ink check mark; the line to the next step is a
///   stronger gold rule.
/// - ``Step/State/current``: a brand disc (forest; gold in dark mode) inside a gold ring.
/// - ``Step/State/upcoming``: a neutral ring with a muted numeral and title.
///
/// ``Direction/vertical`` suits any number of steps and longer detail texts.
/// ``Direction/horizontal`` suits three or four short steps; at accessibility text sizes it
/// falls back to the vertical layout so that no text is squeezed.
///
/// VoiceOver reads each step as one element, for example "Schritt 2 von 3: Bezahlen", followed
/// by the detail text, with the state ("Abgeschlossen", "Aktueller Schritt", "Ausstehend") as the
/// value.
///
/// ```swift
/// KXStepTimeline(steps: [
///     .init(title: orderedTitle, state: .done),
///     .init(title: paidTitle, detail: paidDetail, state: .current),
///     .init(title: deliveredTitle, state: .upcoming),
/// ])
/// ```
public struct KXStepTimeline: View {
    /// One step of a ``KXStepTimeline``.
    public struct Step: Hashable, Sendable {
        /// Progress state of a step in a progress timeline.
        public enum State: String, CaseIterable, Sendable {
            /// The step is completed.
            case done
            /// The step is in progress.
            case current
            /// The step has not started yet.
            case upcoming
        }

        /// The already-localized step title, e.g. "Bezahlen". Keep it to one to three words.
        public let title: String
        /// Optional already-localized supporting text shown below the title.
        public let detail: String?
        /// Progress state, or `nil` for an informational step in a process explanation.
        public let state: State?

        /// Creates a step.
        ///
        /// - Parameters:
        ///   - title: The already-localized step title.
        ///   - detail: Optional already-localized supporting text.
        ///   - state: Progress state. Pass `nil` (the default) for process explanations such as
        ///     "So läuft es ab", where no step is more advanced than another.
        public init(title: String, detail: String? = nil, state: State? = nil) {
            self.title = title
            self.detail = detail
            self.state = state
        }
    }

    /// Layout direction of a ``KXStepTimeline``.
    public enum Direction: String, CaseIterable, Sendable {
        /// Steps stacked top to bottom with a vertical connecting line. Suits any length.
        case vertical
        /// Steps side by side with a horizontal connecting line. Suits three or four short
        /// steps; switches to vertical at accessibility text sizes.
        case horizontal
    }

    private let steps: [Step]
    private let direction: Direction

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a step timeline.
    ///
    /// - Parameters:
    ///   - steps: The steps in order. They are numbered from 1.
    ///   - direction: Layout direction. Defaults to ``Direction/vertical``.
    public init(steps: [Step], direction: Direction = .vertical) {
        self.steps = steps
        self.direction = direction
    }

    public var body: some View {
        Group {
            if direction == .horizontal, !dynamicTypeSize.isAccessibilitySize {
                horizontalLayout
            } else {
                verticalLayout
            }
        }
        .kxAnimation(.standard, value: steps)
        .accessibilityElement(children: .contain)
    }

    // MARK: Layouts

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                KXTimelineVerticalRow(
                    step: step,
                    number: index + 1,
                    count: steps.count,
                    connector: index < steps.count - 1 ? kxTimelineConnector(after: step) : nil
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                KXTimelineHorizontalStep(
                    step: step,
                    number: index + 1,
                    count: steps.count,
                    leadingConnector: index > 0 ? kxTimelineConnector(after: steps[index - 1]) : nil,
                    trailingConnector: index < steps.count - 1 ? kxTimelineConnector(after: step) : nil
                )
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

// MARK: - Connector

/// Color and stroke width of the line that leads from one step to the next.
private struct KXTimelineConnector: Equatable {
    let color: Color
    let width: CGFloat
}

/// The line after `step`: gold while the path is completed or informational, neutral ahead of
/// the current step.
private func kxTimelineConnector(after step: KXStepTimeline.Step) -> KXTimelineConnector {
    switch step.state {
    case nil:
        KXTimelineConnector(color: KXColor.accent, width: KXBorder.regular)
    case .some(.done):
        KXTimelineConnector(color: KXColor.accent, width: KXBorder.emphasis)
    case .some(.current), .some(.upcoming):
        KXTimelineConnector(color: KXColor.divider, width: KXBorder.regular)
    }
}

// MARK: - Vertical row

private struct KXTimelineVerticalRow: View {
    let step: KXStepTimeline.Step
    let number: Int
    let count: Int
    let connector: KXTimelineConnector?

    @ScaledMetric(relativeTo: .headline) private var indicatorSize: CGFloat = 32
    /// Approximate line height of the headline title, used to center the first title line on
    /// the indicator. Scales with the same text style as the title.
    @ScaledMetric(relativeTo: .headline) private var titleLineHeight: CGFloat = 22

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.s) {
            VStack(spacing: KXSpacing.xxs) {
                KXTimelineIndicator(state: step.state, number: number, diameter: indicatorSize)
                if let connector {
                    Rectangle()
                        .fill(connector.color)
                        .frame(width: connector.width)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, KXSpacing.xxs)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: indicatorSize)

            KXTimelineStepText(step: step, isCentered: false)
                .padding(.top, max(0, (indicatorSize - titleLineHeight) / 2))
                .padding(.bottom, connector == nil ? 0 : KXSpacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Lets the connector grow to the height of the text column.
        .fixedSize(horizontal: false, vertical: true)
        .kxTimelineStepAccessibility(step: step, number: number, count: count)
    }
}

// MARK: - Horizontal step

private struct KXTimelineHorizontalStep: View {
    let step: KXStepTimeline.Step
    let number: Int
    let count: Int
    let leadingConnector: KXTimelineConnector?
    let trailingConnector: KXTimelineConnector?

    @ScaledMetric(relativeTo: .headline) private var indicatorSize: CGFloat = 32

    var body: some View {
        VStack(spacing: KXSpacing.s) {
            HStack(spacing: KXSpacing.xxs) {
                connectorLine(leadingConnector)
                KXTimelineIndicator(state: step.state, number: number, diameter: indicatorSize)
                connectorLine(trailingConnector)
            }
            KXTimelineStepText(step: step, isCentered: true)
                .padding(.horizontal, KXSpacing.xxs)
        }
        .kxTimelineStepAccessibility(step: step, number: number, count: count)
    }

    private func connectorLine(_ connector: KXTimelineConnector?) -> some View {
        Rectangle()
            .fill(connector?.color ?? Color.clear)
            .frame(height: connector?.width ?? KXBorder.regular)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

// MARK: - Indicator

/// The numbered circle (or check mark disc) of a step. Decorative for VoiceOver: the step
/// element announces the position and state in words.
private struct KXTimelineIndicator: View {
    let state: KXStepTimeline.Step.State?
    let number: Int
    let diameter: CGFloat

    var body: some View {
        glyph
            .frame(width: diameter, height: diameter)
            .background { backgroundShape }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .some(.done):
            Image(systemName: "checkmark")
                .font(KXFont.font(.headline, size: Double(diameter * 0.4)))
                .foregroundStyle(KXColor.textOnAccent)
        case .some(.current):
            numeral.foregroundStyle(KXColor.textOnBrand)
        case .some(.upcoming):
            numeral.foregroundStyle(KXColor.textTertiary)
        case nil:
            numeral.foregroundStyle(KXColor.accentText)
        }
    }

    private var numeral: some View {
        Text(number, format: .number)
            .font(KXFont.font(.title3, size: Double(diameter * 0.44)))
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder private var backgroundShape: some View {
        switch state {
        case .some(.done):
            Circle().fill(KXColor.accent)
        case .some(.current):
            ZStack {
                Circle().strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
                Circle()
                    .fill(KXColor.brand)
                    .padding(diameter * 0.12)
            }
        case .some(.upcoming):
            Circle().strokeBorder(KXColor.divider, lineWidth: KXBorder.regular)
        case nil:
            Circle().strokeBorder(KXColor.accent, lineWidth: KXBorder.regular)
        }
    }
}

// MARK: - Step text

private struct KXTimelineStepText: View {
    let step: KXStepTimeline.Step
    let isCentered: Bool

    var body: some View {
        VStack(alignment: isCentered ? .center : .leading, spacing: KXSpacing.xxs) {
            Text(step.title)
                .kxFont(.headline)
                .foregroundStyle(step.state == .upcoming ? KXColor.textSecondary : KXColor.textPrimary)
            if let detail = step.detail, !detail.isEmpty {
                Text(detail)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textSecondary)
            }
        }
        .multilineTextAlignment(isCentered ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Accessibility

extension View {
    /// Makes a step one VoiceOver element: "Schritt 2 von 3: Bezahlen, <detail>" with the
    /// progress state as the value.
    fileprivate func kxTimelineStepAccessibility(step: KXStepTimeline.Step, number: Int, count: Int) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(kxTimelineAccessibilityLabel(for: step, number: number, count: count)))
            .accessibilityValue(Text(step.state.map(kxTimelineStateDescription) ?? String()))
    }
}

private func kxTimelineAccessibilityLabel(for step: KXStepTimeline.Step, number: Int, count: Int) -> String {
    let position = String(localized: "kx.timeline.step \(number) \(count) \(step.title)", bundle: .module)
    guard let detail = step.detail, !detail.isEmpty else { return position }
    return [position, detail].joined(separator: ", ")
}

private func kxTimelineStateDescription(_ state: KXStepTimeline.Step.State) -> String {
    switch state {
    case .done: String(localized: "kx.timeline.state.done", bundle: .module)
    case .current: String(localized: "kx.timeline.state.current", bundle: .module)
    case .upcoming: String(localized: "kx.timeline.state.upcoming", bundle: .module)
    }
}

// MARK: - Previews

/// Sample steps follow the purchase flow and order states defined in PROMPT.md sections 2 and
/// 6.3/6.7 (payment methods and delivery by e-mail are store facts, not product claims).
private struct KXStepTimelinePreviewGallery: View {
    private let process: [KXStepTimeline.Step] = [
        .init(title: "Bestellen", detail: "Produkt in den Warenkorb legen"),
        .init(title: "Bezahlen", detail: "Apple Pay, Kreditkarte oder Klarna"),
        .init(title: "Schlüssel per E-Mail", detail: "In wenigen Minuten"),
    ]

    private let order: [KXStepTimeline.Step] = [
        .init(title: "Bestellt", state: .done),
        .init(title: "Bezahlt", state: .current),
        .init(title: "Lizenz versendet", state: .upcoming),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXStepTimeline(steps: process, direction: .horizontal)
                KXStepTimeline(steps: process)
                KXStepTimeline(steps: order)
                KXStepTimeline(steps: order, direction: .horizontal)
            }
            .padding(KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXStepTimeline, light") {
    KXStepTimelinePreviewGallery()
}

#Preview("KXStepTimeline, dark") {
    KXStepTimelinePreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXStepTimeline, accessibility size") {
    KXStepTimelinePreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
