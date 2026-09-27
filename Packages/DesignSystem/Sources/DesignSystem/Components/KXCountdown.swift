import DesignTokens
import Foundation
import SwiftUI

// MARK: - KXCountdownComponents

/// The remaining time of a countdown, split into days, hours, minutes and seconds.
///
/// A pure value type without UI dependencies, so the arithmetic is unit-testable and the same
/// breakdown drives both the digits and the VoiceOver label of ``KXCountdown``.
///
/// Fractions of a second are rounded up, so a countdown shows "00:00:01" until the end date is
/// reached and "00:00:00" exactly at the end. Negative, zero and NaN intervals count as expired.
/// Very large intervals are capped at ``maximumTotalSeconds``.
///
/// ```swift
/// let parts = KXCountdownComponents(remaining: 2 * 86_400 + 3 * 3_600 + 4 * 60 + 5)
/// // parts.days == 2, parts.hours == 3, parts.minutes == 4, parts.seconds == 5
/// ```
public struct KXCountdownComponents: Hashable, Sendable {
    /// The largest representable remaining time: 9999 days, 23:59:59.
    public static let maximumTotalSeconds = 9_999 * 86_400 + 86_399

    /// Whole days remaining (0 when less than 24 hours remain).
    public let days: Int
    /// Hours remaining in the current day, 0...23.
    public let hours: Int
    /// Minutes remaining in the current hour, 0...59.
    public let minutes: Int
    /// Seconds remaining in the current minute, 0...59.
    public let seconds: Int

    /// Splits a number of whole seconds. Negative values count as zero; values above
    /// ``maximumTotalSeconds`` are capped.
    public init(totalSeconds: Int) {
        let total = min(max(totalSeconds, 0), Self.maximumTotalSeconds)
        days = total / 86_400
        hours = (total % 86_400) / 3_600
        minutes = (total % 3_600) / 60
        seconds = total % 60
    }

    /// Splits a remaining time interval, rounding fractions of a second up.
    public init(remaining interval: TimeInterval) {
        self.init(totalSeconds: Self.wholeSeconds(of: interval))
    }

    /// Splits the time from `now` until `endDate`.
    public init(from now: Date, to endDate: Date) {
        self.init(remaining: endDate.timeIntervalSince(now))
    }

    /// Converts an interval to whole seconds as displayed: fractions round up, negative and NaN
    /// values become 0, and the result never exceeds ``maximumTotalSeconds``.
    public static func wholeSeconds(of interval: TimeInterval) -> Int {
        guard !interval.isNaN, interval > 0 else { return 0 }
        let capped = min(interval, Double(maximumTotalSeconds))
        return Int(capped.rounded(.up))
    }

    /// The remaining time in whole seconds.
    public var totalSeconds: Int {
        days * 86_400 + hours * 3_600 + minutes * 60 + seconds
    }

    /// Whether the countdown has reached its end.
    public var isExpired: Bool {
        totalSeconds == 0
    }

    /// Whether the days field is shown, i.e. at least 24 hours remain.
    public var showsDays: Bool {
        days > 0
    }
}

// MARK: - KXCountdown

/// A flip-clock style countdown to a date: HH:MM:SS, with a days field while 24 hours or more
/// remain. Used for deals ("Blitzangebote") whose end comes from the store.
///
/// Digits are serif numerals on ink (or brand) tiles with a terracotta accent edge; the
/// separators are terracotta dots. Changing digits roll like flip cards
/// (`numericText(countsDown:)`); with Reduce Motion they change without animation.
///
/// The live countdown updates once per second with `TimelineView(.periodic(from:by:))`, aligned
/// to the end date so that it reaches zero exactly at `endsAt`. When it reaches zero it stops
/// ticking, shows zeros and calls `onExpire` once. If `endsAt` is already in the past on
/// appear, `onExpire` is called right away, so the caller can hide an ended deal.
///
/// Pass `now` to render a single static frame for that reference date (snapshot tests,
/// previews). The static frame never ticks and never calls `onExpire`.
///
/// VoiceOver reads the countdown as one element at minute precision, e.g. "Endet in 2 Tagen,
/// 3 Stunden, 4 Minuten". The label changes at most once a minute and is never announced on its
/// own, so VoiceOver does not read every second.
///
/// At large text sizes the fields wrap into two rows, then into a column, instead of
/// truncating.
///
/// ```swift
/// KXCountdown(endsAt: dealEnd) { viewModel.dealDidEnd() }
/// KXCountdown(endsAt: fixedEnd, now: fixedReferenceDate) // deterministic snapshot
/// ```
public struct KXCountdown: View {
    /// Tile colors of a ``KXCountdown``.
    public enum Style: String, CaseIterable, Sendable {
        /// Ink tiles with cream digits in both appearances (the certificate ink of the brand).
        case ink
        /// Brand tiles: forest with cream digits in light mode, gold with ink digits in dark
        /// mode.
        case brand
    }

    /// Type scale of a ``KXCountdown``.
    public enum Size: String, CaseIterable, Sendable {
        /// Large numerals for heroes and product detail.
        case regular
        /// Smaller numerals for product cards and carousels.
        case compact
    }

    private let endsAt: Date
    private let referenceDate: Date?
    private let style: Style
    private let size: Size
    private let onExpire: (@MainActor () -> Void)?

    @State private var hasExpired = false

    /// Creates a countdown.
    ///
    /// - Parameters:
    ///   - endsAt: The moment the countdown reaches zero.
    ///   - now: A fixed reference date. When set, the countdown renders one static frame for
    ///     that date without a timeline and never calls `onExpire`. Leave `nil` (the default)
    ///     for a live countdown.
    ///   - style: Tile colors. Defaults to ``Style/ink``.
    ///   - size: Type scale. Defaults to ``Size/regular``.
    ///   - onExpire: Called once on the main actor when a live countdown reaches zero, or on
    ///     appear when `endsAt` has already passed.
    public init(
        endsAt: Date,
        now: Date? = nil,
        style: Style = .ink,
        size: Size = .regular,
        onExpire: (@MainActor () -> Void)? = nil
    ) {
        self.endsAt = endsAt
        referenceDate = now
        self.style = style
        self.size = size
        self.onExpire = onExpire
    }

    public var body: some View {
        Group {
            if let referenceDate {
                KXCountdownFace(components: KXCountdownComponents(from: referenceDate, to: endsAt), style: style, size: size)
            } else if hasExpired {
                KXCountdownFace(components: KXCountdownComponents(totalSeconds: 0), style: style, size: size)
            } else {
                TimelineView(.periodic(from: Self.firstTick(endsAt: endsAt, now: Date()), by: 1)) { context in
                    let components = KXCountdownComponents(from: context.date, to: endsAt)
                    KXCountdownFace(components: components, style: style, size: size)
                        .onChange(of: components.isExpired, initial: true) { _, isExpired in
                            if isExpired {
                                expire()
                            }
                        }
                }
            }
        }
        .onChange(of: endsAt) {
            hasExpired = false
        }
    }

    private func expire() {
        guard !hasExpired else { return }
        hasExpired = true
        onExpire?()
    }

    /// The first timeline entry: the latest date at or before `now` that lies a whole number of
    /// seconds before `endsAt`. Every following tick is then exactly N seconds before the end,
    /// so the display changes on the second and reaches zero exactly at `endsAt`.
    private static func firstTick(endsAt: Date, now: Date) -> Date {
        let remaining = endsAt.timeIntervalSince(now)
        guard remaining.isFinite, remaining > 0 else { return now }
        return endsAt.addingTimeInterval(-remaining.rounded(.up))
    }
}

// MARK: - Face

/// One rendered frame of the countdown for a given breakdown.
private struct KXCountdownFace: View {
    let components: KXCountdownComponents
    let style: KXCountdown.Style
    let size: KXCountdown.Size

    var body: some View {
        let units = kxCountdownUnits(for: components)
        ViewThatFits(in: .horizontal) {
            unitRow(units)
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                ForEach(Array(kxCountdownRows(of: units).enumerated()), id: \.offset) { _, row in
                    unitRow(row)
                }
            }
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                ForEach(units) { unit in
                    KXCountdownUnitView(unit: unit, style: style, size: size)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kxCountdownAccessibilityDescription(for: components)))
    }

    private func unitRow(_ units: [KXCountdownUnit]) -> some View {
        HStack(alignment: .kxCountdownTileCenter, spacing: KXSpacing.xs) {
            ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                if index > 0 {
                    KXCountdownSeparator()
                }
                KXCountdownUnitView(unit: unit, style: style, size: size)
            }
        }
    }
}

// MARK: - Units

private enum KXCountdownUnitKind: Hashable {
    case days
    case hours
    case minutes
    case seconds
}

private struct KXCountdownUnit: Identifiable {
    let id: KXCountdownUnitKind
    let value: Int
    let label: String
}

/// Days (only while at least 24 hours remain), hours, minutes and seconds with their short
/// localized labels.
private func kxCountdownUnits(for components: KXCountdownComponents) -> [KXCountdownUnit] {
    var units: [KXCountdownUnit] = []
    if components.showsDays {
        units.append(KXCountdownUnit(
            id: .days,
            value: components.days,
            // Xcode requires plural variations to contain the number, and the tile shows the
            // number separately, so the label uses two plain keys instead of a plural.
            label: components.days == 1
                ? String(localized: "kx.countdown.unit.day", bundle: .module)
                : String(localized: "kx.countdown.unit.days", bundle: .module)
        ))
    }
    units.append(KXCountdownUnit(
        id: .hours,
        value: components.hours,
        label: String(localized: "kx.countdown.unit.hours", bundle: .module)
    ))
    units.append(KXCountdownUnit(
        id: .minutes,
        value: components.minutes,
        label: String(localized: "kx.countdown.unit.minutes", bundle: .module)
    ))
    units.append(KXCountdownUnit(
        id: .seconds,
        value: components.seconds,
        label: String(localized: "kx.countdown.unit.seconds", bundle: .module)
    ))
    return units
}

/// Splits the units into rows of two for the wrapped layout.
private func kxCountdownRows(of units: [KXCountdownUnit]) -> [[KXCountdownUnit]] {
    stride(from: 0, to: units.count, by: 2).map { start in
        Array(units[start..<min(start + 2, units.count)])
    }
}

/// Two-digit (or longer, for 100+ days) zero-padded field value.
private func kxCountdownDigits(_ value: Int) -> String {
    let digits = String(value)
    return digits.count < 2 ? "0" + digits : digits
}

// MARK: - Unit view

private struct KXCountdownUnitView: View {
    let unit: KXCountdownUnit
    let style: KXCountdown.Style
    let size: KXCountdown.Size

    var body: some View {
        VStack(spacing: KXSpacing.xxs) {
            KXCountdownTile(digits: kxCountdownDigits(unit.value), style: style, size: size)
                .alignmentGuide(.kxCountdownTileCenter) { dimensions in
                    dimensions[VerticalAlignment.center]
                }
            Text(unit.label)
                .kxFont(.eyebrow)
                .foregroundStyle(KXColor.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// A flip-card tile: serif numerals, a subtle lighter upper half, a hinge line across the
/// middle and a terracotta accent along the bottom edge.
private struct KXCountdownTile: View {
    let digits: String
    let style: KXCountdown.Style
    let size: KXCountdown.Size

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
        Text(verbatim: digits)
            .kxFont(size == .regular ? .numeral : .title3)
            .foregroundStyle(style.digitColor)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(reduceMotion ? nil : KXMotion.animation(.snappy, reduceMotion: false), value: digits)
            .padding(.horizontal, size == .regular ? KXSpacing.s : KXSpacing.xs)
            .padding(.vertical, size == .regular ? KXSpacing.xs : KXSpacing.xxs)
            .background {
                VStack(spacing: 0) {
                    style.digitColor.opacity(0.06)
                    Color.clear
                }
                .background(style.tileColor)
                .overlay {
                    KXColor.scrim.frame(height: KXBorder.regular)
                }
                .overlay(alignment: .bottom) {
                    KXColor.urgency.frame(height: KXBorder.emphasis)
                }
                .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(KXColor.hairline, lineWidth: 1 / max(displayScale, 1))
            }
    }
}

/// Two terracotta dots between fields, centered on the tiles.
private struct KXCountdownSeparator: View {
    @ScaledMetric(relativeTo: .title) private var dotSize: CGFloat = 4

    var body: some View {
        VStack(spacing: dotSize * 1.5) {
            Circle().fill(KXColor.urgency).frame(width: dotSize, height: dotSize)
            Circle().fill(KXColor.urgency).frame(width: dotSize, height: dotSize)
        }
        .accessibilityHidden(true)
    }
}

extension KXCountdown.Style {
    /// Tile fill. Both fills are paired with their text color in `ContrastRequirement.all`
    /// (`keyCardText` on `keyCardBackground`, `textOnBrand` on `brand`).
    fileprivate var tileColor: Color {
        switch self {
        case .ink: KXColor.keyCardBackground
        case .brand: KXColor.brand
        }
    }

    fileprivate var digitColor: Color {
        switch self {
        case .ink: KXColor.keyCardText
        case .brand: KXColor.textOnBrand
        }
    }
}

extension VerticalAlignment {
    /// Aligns the separator dots with the vertical center of the digit tiles (not of the whole
    /// tile plus unit label).
    fileprivate enum KXCountdownTileCenterID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    fileprivate static var kxCountdownTileCenter: VerticalAlignment {
        VerticalAlignment(KXCountdownTileCenterID.self)
    }
}

// MARK: - Accessibility

/// "Endet in 2 Tagen, 3 Stunden, 4 Minuten" at minute precision, "Endet in weniger als einer
/// Minute" during the last minute and "Beendet" at zero.
private func kxCountdownAccessibilityDescription(for components: KXCountdownComponents) -> String {
    if components.isExpired {
        return String(localized: "kx.countdown.accessibility.ended", bundle: .module)
    }
    if components.totalSeconds < 60 {
        return String(localized: "kx.countdown.accessibility.under_minute", bundle: .module)
    }
    var parts: [String] = []
    if components.days > 0 {
        parts.append(String(localized: "kx.countdown.accessibility.days \(components.days)", bundle: .module))
    }
    if components.hours > 0 {
        parts.append(String(localized: "kx.countdown.accessibility.hours \(components.hours)", bundle: .module))
    }
    if components.minutes > 0 {
        parts.append(String(localized: "kx.countdown.accessibility.minutes \(components.minutes)", bundle: .module))
    }
    let duration = parts.joined(separator: ", ")
    return String(localized: "kx.countdown.accessibility.remaining \(duration)", bundle: .module)
}

// MARK: - Previews

/// The live samples count down to `Date.now` plus 2 days and 3 hours (contract section 5). The
/// static samples use a fixed reference date so they render the same frame every time.
private struct KXCountdownPreviewGallery: View {
    private let liveEnd = Date.now.addingTimeInterval(2 * 86_400 + 3 * 3_600)
    private let reference = Date(timeIntervalSinceReferenceDate: 812_160_000)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXCountdown(endsAt: liveEnd)
                KXCountdown(endsAt: liveEnd, style: .brand, size: .compact)
                KXCountdown(endsAt: reference.addingTimeInterval(3 * 3_600 + 4 * 60 + 5), now: reference)
                KXCountdown(endsAt: reference, now: reference, size: .compact)
            }
            .padding(KXSpacing.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kxScreenBackground()
    }
}

#Preview("KXCountdown, light") {
    KXCountdownPreviewGallery()
}

#Preview("KXCountdown, dark") {
    KXCountdownPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXCountdown, accessibility size") {
    KXCountdownPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
