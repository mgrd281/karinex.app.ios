import DesignTokens
import SwiftUI

// MARK: - KXLoyaltyCardAction

/// One of the tiles under the ring of the membership card.
public struct KXLoyaltyCardAction: Identifiable {
    /// A stable identity.
    public let id: String
    /// The SF Symbol on the tile.
    public let systemImage: String
    /// The short label under the symbol.
    public let title: String
    /// The VoiceOver hint.
    public let hint: String?
    /// What the tile does.
    public let perform: @MainActor () -> Void

    /// Creates an action tile.
    public init(id: String, systemImage: String, title: String, hint: String? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id
        self.systemImage = systemImage
        self.title = title
        self.hint = hint
        self.perform = perform
    }
}

// MARK: - KXLoyaltyCard

/// The membership card of the loyalty program: a calm gradient in the color of the level, a
/// progress ring with round ends open at the bottom, the name of the level in its center, the
/// points and what is missing for the next level, and up to three action tiles.
///
/// The card shows what the backend computed and calculates nothing. It takes finished texts so
/// the feature owns the wording and the number formatting. The ring fills once when the card
/// appears and again when the value changes; with Reduce Motion it just shows the value.
///
/// ```swift
/// KXLoyaltyCard(
///     style: .gold, tierName: "Gold", progress: 0.63,
///     pointsLine: "1.573 / 2.500 Statuspunkte", message: "Noch 927 Punkte bis zum Platin-Status",
///     accessibilitySummary: "Gold, 1.573 von 2.500 Statuspunkten",
///     actions: [KXLoyaltyCardAction(id: "rewards", systemImage: "gift", title: "Prämien") { open() }]
/// )
/// ```
public struct KXLoyaltyCard: View {
    private let style: LoyaltyTierStyle
    private let tierName: String
    private let progress: Double
    private let pointsLine: String
    private let message: String
    private let accessibilitySummary: String
    private let actions: [KXLoyaltyCardAction]

    @State private var shownProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var ringSide: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 52

    /// The part of a full circle the ring covers (the rest is the opening at the bottom).
    static let arcFraction: Double = 0.75
    /// Where the arc starts: the lower left, so the opening faces down.
    static let startAngle: Double = 135

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - style: The level, which sets the colors.
    ///   - tierName: The name of the level shown in the ring.
    ///   - progress: 0...1, the part of the ring that is filled.
    ///   - pointsLine: The points, e.g. "1.573 / 2.500 Statuspunkte".
    ///   - message: What is missing for the next level, or that the top level is reached.
    ///   - accessibilitySummary: One sentence for VoiceOver.
    ///   - actions: The action tiles, at most three are shown.
    public init(
        style: LoyaltyTierStyle,
        tierName: String,
        progress: Double,
        pointsLine: String,
        message: String,
        accessibilitySummary: String,
        actions: [KXLoyaltyCardAction]
    ) {
        self.style = style
        self.tierName = tierName
        self.progress = min(1, max(0, progress.isFinite ? progress : 0))
        self.pointsLine = pointsLine
        self.message = message
        self.accessibilitySummary = accessibilitySummary
        self.actions = Array(actions.prefix(3))
    }

    private var colors: LoyaltyPanelColors {
        LoyaltyPalette.colors(for: style)
    }

    public var body: some View {
        VStack(spacing: KXSpacing.l) {
            ring
            VStack(spacing: KXSpacing.xs) {
                Text(verbatim: pointsLine)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.fixed(colors.text))
                    .multilineTextAlignment(.center)
                Text(verbatim: message)
                    .kxFont(.callout)
                    .foregroundStyle(KXColor.fixed(colors.mutedText))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityHidden(true)
            if !actions.isEmpty {
                HStack(alignment: .top, spacing: KXSpacing.s) {
                    ForEach(actions) { action in
                        tile(action)
                    }
                }
            }
        }
        .padding(.horizontal, KXSpacing.m)
        .padding(.vertical, KXSpacing.l)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [KXColor.fixed(colors.top), KXColor.fixed(colors.bottom)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: KXRadius.large, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("loyalty.card")
        .onAppear { fill() }
        .onChange(of: progress) { fill() }
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: Self.arcFraction)
                .stroke(KXColor.fixed(colors.ringTrack), style: StrokeStyle(lineWidth: ringLine, lineCap: .round))
                .rotationEffect(.degrees(Self.startAngle))
            Circle()
                .trim(from: 0, to: Self.arcFraction * shownProgress)
                .stroke(KXColor.fixed(colors.ring), style: StrokeStyle(lineWidth: ringLine, lineCap: .round))
                .rotationEffect(.degrees(Self.startAngle))
            Text(verbatim: tierName)
                .kxFont(.display)
                .foregroundStyle(KXColor.fixed(colors.text))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, ringLine * 2)
        }
        .padding(ringLine / 2)
        .frame(width: ringSide, height: ringSide)
        // The ring is decoration; the card's summary carries the content for VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
        .accessibilityAddTraits(.isHeader)
    }

    private var ringLine: CGFloat {
        ringSide * 0.075
    }

    private func fill() {
        if reduceMotion {
            shownProgress = progress
        } else {
            withAnimation(.easeOut(duration: KXMotion.ringFillDuration)) {
                shownProgress = progress
            }
        }
    }

    // MARK: Tiles

    private func tile(_ action: KXLoyaltyCardAction) -> some View {
        Button {
            action.perform()
        } label: {
            VStack(spacing: KXSpacing.xs) {
                Image(systemName: action.systemImage)
                    .fontWeight(.light)
                    .kxFont(.title3)
                    .foregroundStyle(KXColor.fixed(colors.text))
                    .frame(width: tileSide, height: tileSide)
                    .background(KXColor.fixed(colors.tile), in: RoundedRectangle(cornerRadius: KXRadius.large, style: .continuous))
                    .accessibilityHidden(true)
                Text(verbatim: action.title)
                    .kxFont(.caption)
                    .foregroundStyle(KXColor.fixed(colors.text))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: KXSpacing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: action.title))
        .accessibilityHint(Text(verbatim: action.hint ?? ""))
        .accessibilityIdentifier("loyalty.action.\(action.id)")
    }
}
