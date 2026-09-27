@testable import DesignSystem
import DesignTokens
import Foundation
import SwiftUI
import Testing
import UIKit

// MARK: - KXCountdownComponents

@Suite("KXCountdownComponents")
struct KXCountdownComponentsTests {
    @Test("Splits whole seconds into days, hours, minutes and seconds")
    func splitsTotalSeconds() {
        let parts = KXCountdownComponents(totalSeconds: 2 * 86_400 + 3 * 3_600 + 4 * 60 + 5)
        #expect(parts.days == 2)
        #expect(parts.hours == 3)
        #expect(parts.minutes == 4)
        #expect(parts.seconds == 5)
        #expect(parts.totalSeconds == 2 * 86_400 + 3 * 3_600 + 4 * 60 + 5)
        #expect(parts.showsDays)
        #expect(!parts.isExpired)
    }

    @Test("Shows days only from 24 hours on")
    func daysThreshold() {
        let justBelow = KXCountdownComponents(totalSeconds: 86_399)
        #expect(justBelow.days == 0)
        #expect(justBelow.hours == 23)
        #expect(justBelow.minutes == 59)
        #expect(justBelow.seconds == 59)
        #expect(!justBelow.showsDays)

        let oneDay = KXCountdownComponents(totalSeconds: 86_400)
        #expect(oneDay.days == 1)
        #expect(oneDay.hours == 0)
        #expect(oneDay.minutes == 0)
        #expect(oneDay.seconds == 0)
        #expect(oneDay.showsDays)
    }

    @Test("Treats zero and negative values as expired", arguments: [0, -1, -86_400, Int.min])
    func expired(totalSeconds: Int) {
        let parts = KXCountdownComponents(totalSeconds: totalSeconds)
        #expect(parts.isExpired)
        #expect(parts.totalSeconds == 0)
        #expect(!parts.showsDays)
        #expect(parts == KXCountdownComponents(totalSeconds: 0))
    }

    @Test("Caps very large values at the maximum")
    func capsLargeValues() {
        let parts = KXCountdownComponents(totalSeconds: .max)
        #expect(parts.totalSeconds == KXCountdownComponents.maximumTotalSeconds)
        #expect(parts.days == 9_999)
        #expect(parts.hours == 23)
        #expect(parts.minutes == 59)
        #expect(parts.seconds == 59)
    }

    @Test(
        "Rounds fractions of a second up and maps invalid intervals to zero",
        arguments: [
            (0.2, 1),
            (1.0, 1),
            (1.5, 2),
            (59.001, 60),
            (0.0, 0),
            (-0.5, 0),
            (-3_600.0, 0),
            (1e12, KXCountdownComponents.maximumTotalSeconds),
        ]
    )
    func wholeSeconds(interval: TimeInterval, expected: Int) {
        #expect(KXCountdownComponents.wholeSeconds(of: interval) == expected)
        #expect(KXCountdownComponents(remaining: interval).totalSeconds == expected)
    }

    // Non-finite intervals are tested without test arguments: JSON cannot encode them, and
    // Swift Testing encodes arguments to identify test cases.
    @Test("Treats NaN as expired and infinity as the maximum")
    func nonFiniteIntervals() {
        #expect(KXCountdownComponents.wholeSeconds(of: .nan) == 0)
        #expect(KXCountdownComponents(remaining: .nan).isExpired)
        #expect(KXCountdownComponents.wholeSeconds(of: -.infinity) == 0)
        #expect(KXCountdownComponents.wholeSeconds(of: .infinity) == KXCountdownComponents.maximumTotalSeconds)
        #expect(KXCountdownComponents(remaining: .infinity).totalSeconds == KXCountdownComponents.maximumTotalSeconds)
    }

    @Test("Shows 00:00:01 until the end and zero exactly at the end")
    func lastSecond() {
        let almostDone = KXCountdownComponents(remaining: 0.001)
        #expect(almostDone.seconds == 1)
        #expect(!almostDone.isExpired)
        #expect(KXCountdownComponents(remaining: 0).isExpired)
    }

    @Test("Measures the time between two dates")
    func betweenDates() {
        let reference = Date(timeIntervalSinceReferenceDate: 812_160_000)
        let end = reference.addingTimeInterval(3 * 3_600 + 4 * 60 + 5)
        let parts = KXCountdownComponents(from: reference, to: end)
        #expect(parts == KXCountdownComponents(totalSeconds: 3 * 3_600 + 4 * 60 + 5))
        #expect(!parts.showsDays)
        #expect(KXCountdownComponents(from: end, to: reference).isExpired)
    }
}

// MARK: - KXLicenseKeyFormatting

@Suite("KXLicenseKeyFormatting")
struct KXLicenseKeyFormattingTests {
    /// An obviously fake key; real keys never appear in code.
    private let dashedKey = "XXXXX-00000-XXXXX-00000-XXXXX"

    @Test("Splits dashed keys at the dashes")
    func dashedGroups() {
        #expect(KXLicenseKeyFormatting.groups(of: dashedKey) == ["XXXXX", "00000", "XXXXX", "00000", "XXXXX"])
        #expect(KXLicenseKeyFormatting.groups(of: "  XXXXX-00000 \n") == ["XXXXX", "00000"])
    }

    @Test("Splits space-separated keys at the whitespace")
    func whitespaceGroups() {
        #expect(KXLicenseKeyFormatting.groups(of: "XXXX 0000  XXXX") == ["XXXX", "0000", "XXXX"])
    }

    @Test("Chunks keys without separators into groups of five")
    func chunkedGroups() {
        #expect(KXLicenseKeyFormatting.groups(of: "XXXXX00000XX") == ["XXXXX", "00000", "XX"])
        #expect(KXLicenseKeyFormatting.groups(of: "XXX") == ["XXX"])
        #expect(KXLicenseKeyFormatting.fallbackGroupLength == 5)
    }

    @Test("Returns no groups for empty keys", arguments: ["", "   ", "\n"])
    func emptyGroups(key: String) {
        #expect(KXLicenseKeyFormatting.groups(of: key).isEmpty)
        #expect(KXLicenseKeyFormatting.lines(of: key, groupsPerLine: 3).isEmpty)
    }

    @Test("Keeps the trailing dash on every wrapped line of a dashed key")
    func dashedLines() {
        #expect(KXLicenseKeyFormatting.lines(of: dashedKey, groupsPerLine: 5) == [dashedKey])
        #expect(
            KXLicenseKeyFormatting.lines(of: dashedKey, groupsPerLine: 2)
                == ["XXXXX-00000-", "XXXXX-00000-", "XXXXX"]
        )
        #expect(
            KXLicenseKeyFormatting.lines(of: dashedKey, groupsPerLine: 3)
                == ["XXXXX-00000-XXXXX-", "00000-XXXXX"]
        )
        // Joining the lines restores the key.
        #expect(KXLicenseKeyFormatting.lines(of: dashedKey, groupsPerLine: 1).joined() == dashedKey)
    }

    @Test("Treats fewer than one group per line as one", arguments: [0, -3])
    func minimumGroupsPerLine(groupsPerLine: Int) {
        #expect(
            KXLicenseKeyFormatting.lines(of: dashedKey, groupsPerLine: groupsPerLine)
                == KXLicenseKeyFormatting.lines(of: dashedKey, groupsPerLine: 1)
        )
        #expect(KXLicenseKeyFormatting.lines(of: dashedKey, groupsPerLine: groupsPerLine).count == 5)
    }

    @Test("Joins space-separated groups with a space and chunks without a separator")
    func otherLines() {
        #expect(KXLicenseKeyFormatting.lines(of: "XXXX 0000 XXXX", groupsPerLine: 2) == ["XXXX 0000", "XXXX"])
        #expect(KXLicenseKeyFormatting.lines(of: "XXXXX00000XX", groupsPerLine: 2) == ["XXXXX00000", "XX"])
    }

    @Test(
        "Offers group counts per line from widest to narrowest",
        arguments: [
            (0, [1]),
            (1, [1]),
            (2, [2, 1]),
            (3, [3, 2, 1]),
            (4, [4, 2, 1]),
            (5, [5, 3, 2, 1]),
            (6, [6, 3, 2, 1]),
            (7, [7, 4, 2, 1]),
        ]
    )
    func candidates(groupCount: Int, expected: [Int]) {
        let candidates = KXLicenseKeyFormatting.groupsPerLineCandidates(forGroupCount: groupCount)
        #expect(candidates == expected)
        #expect(candidates.last == 1)
        #expect(Set(candidates).count == candidates.count)
    }

    @Test("Masks every character but keeps the grouping")
    func masking() {
        let bullets = String(repeating: KXLicenseKeyFormatting.maskCharacter, count: 5)
        let masked = KXLicenseKeyFormatting.masked(dashedKey)
        #expect(masked == Array(repeating: bullets, count: 5).joined(separator: "-"))
        #expect(masked.count == dashedKey.count)
        #expect(!masked.contains("X"))
        #expect(!masked.contains("0"))
        #expect(KXLicenseKeyFormatting.masked("AB CD") == "\(bullets.prefix(2)) \(bullets.prefix(2))")
        #expect(
            KXLicenseKeyFormatting.lines(of: masked, groupsPerLine: 2)
                == ["\(bullets)-\(bullets)-", "\(bullets)-\(bullets)-", bullets]
        )
    }

    @Test("Chooses the separator from the key")
    func separator() {
        #expect(KXLicenseKeyFormatting.separator(of: dashedKey) == "-")
        #expect(KXLicenseKeyFormatting.separator(of: "XXXX 0000") == " ")
        #expect(KXLicenseKeyFormatting.separator(of: " XXXX0000 ").isEmpty)
    }
}

// MARK: - KXClipboard

@MainActor
@Suite("KXClipboard")
struct KXClipboardTests {
    @Test(
        "Applies at least one second and falls back to the default for non-finite lifetimes",
        arguments: [
            (120.0, 120.0),
            (3_600.0, 3_600.0),
            (1.0, 1.0),
            (0.2, 1.0),
            (0.0, 1.0),
            (-30.0, 1.0),
        ]
    )
    func effectiveLifetime(requested: TimeInterval, expected: TimeInterval) {
        #expect(KXClipboard.effectiveLifetime(requested) == expected)
    }

    @Test("Uses the default lifetime for non-finite values")
    func nonFiniteLifetime() {
        #expect(KXClipboard.effectiveLifetime(.nan) == KXClipboard.defaultExpiration)
        #expect(KXClipboard.effectiveLifetime(.infinity) == KXClipboard.defaultExpiration)
        #expect(KXClipboard.effectiveLifetime(-.infinity) == KXClipboard.defaultExpiration)
    }

    @Test("Defaults to two minutes")
    func defaultExpiration() {
        #expect(KXClipboard.defaultExpiration == 120)
    }

    @Test("Marks sensitive items local only with an expiration date")
    func sensitiveOptions() throws {
        let now = Date(timeIntervalSinceReferenceDate: 812_160_000)
        let options = KXClipboard.sensitiveOptions(expiresAfter: 120, now: now)
        #expect(options.count == 2)
        #expect(options[.localOnly] as? Bool == true)
        let expiration = try #require(options[.expirationDate] as? Date)
        #expect(expiration == now.addingTimeInterval(120))

        let clamped = KXClipboard.sensitiveOptions(expiresAfter: 0, now: now)
        #expect(clamped[.expirationDate] as? Date == now.addingTimeInterval(1))
    }

    @Test("Writes plain text to the given pasteboard")
    func copiesToPasteboard() throws {
        let name = UIPasteboard.Name("de.karinex.designsystem.tests.\(UUID().uuidString)")
        let pasteboard = try #require(UIPasteboard(name: name, create: true))
        defer { UIPasteboard.remove(withName: name) }

        let key = "XXXXX-00000-XXXXX-00000-XXXXX"
        KXClipboard.copySensitive(key, to: pasteboard)
        #expect(pasteboard.string == key)
        #expect(pasteboard.numberOfItems == 1)

        // A second copy replaces the first item instead of adding one.
        KXClipboard.copySensitive("XXXXX-11111", expiresAfter: 30, to: pasteboard)
        #expect(pasteboard.string == "XXXXX-11111")
        #expect(pasteboard.numberOfItems == 1)
    }
}

// MARK: - Models

@Suite("Component models")
struct ComponentModelTests {
    @Test("A trust item appends its footnote marker for display only")
    func trustItemDisplayText() {
        let plain = KXTrustItem(systemImage: "envelope", text: "Lieferung per E-Mail in Minuten")
        #expect(plain.id == "Lieferung per E-Mail in Minuten")
        #expect(plain.displayText == "Lieferung per E-Mail in Minuten")
        let plainIsInteractive = plain.onTap != nil
        #expect(!plainIsInteractive)

        let marked = KXTrustItem(
            systemImage: "arrow.uturn.backward",
            text: "100 Tage Geld-zurück",
            footnoteMarker: "*",
            id: "refund",
            onTap: {}
        )
        #expect(marked.id == "refund")
        #expect(marked.text == "100 Tage Geld-zurück")
        #expect(marked.displayText == "100 Tage Geld-zurück*")
        let markedIsInteractive = marked.onTap != nil
        #expect(markedIsInteractive)

        let emptyMarker = KXTrustItem(systemImage: "creditcard", text: "Apple Pay, Kreditkarte, Klarna", footnoteMarker: "")
        #expect(emptyMarker.displayText == "Apple Pay, Kreditkarte, Klarna")
    }

    @MainActor
    @Test("An accordion item is identified by its title unless an id is given")
    func accordionItemIdentity() {
        let byTitle = KXAccordionItem(title: "Wie erhalte ich meinen Lizenzschlüssel?", text: "Per E-Mail.")
        #expect(byTitle.id == "Wie erhalte ich meinen Lizenzschlüssel?")
        #expect(byTitle.title == "Wie erhalte ich meinen Lizenzschlüssel?")

        let explicit = KXAccordionItem(title: "Support", id: "faq.support") {
            Text(verbatim: "WhatsApp, E-Mail und Live-Chat")
        }
        #expect(explicit.id == "faq.support")
    }

    @Test("A product card model defaults to a gold badge and no optional content")
    func productCardModelDefaults() {
        let model = KXProductCardModel(id: "windows-11-pro", title: "Windows 11 Pro", price: "12,90 €")
        #expect(model.badgeTone == .gold)
        #expect(model.vendor == nil)
        #expect(model.compareAtPrice == nil)
        #expect(model.taxNote == nil)
        #expect(model.badge == nil)
        #expect(model.imageURL == nil)
        #expect(model.availabilityNote == nil)
        #expect(model == KXProductCardModel(id: "windows-11-pro", title: "Windows 11 Pro", price: "12,90 €"))
        #expect(model != KXProductCardModel(id: "windows-11-pro", title: "Windows 11 Pro", price: "12,90 €", badgeTone: .urgency))
    }

    @Test("A timeline step without a state is informational")
    func timelineStepDefaults() {
        let step = KXStepTimeline.Step(title: "Bestellen")
        #expect(step.detail == nil)
        #expect(step.state == nil)
        #expect(step != KXStepTimeline.Step(title: "Bestellen", state: .done))
    }
}

// MARK: - KXColor

@Suite("KXColor")
struct KXColorTests {
    @Test("Resolves every token to its light and dark value", arguments: ColorToken.allCases)
    func resolvesTokens(token: ColorToken) {
        let color = KXColor.uiColor(token)
        let light = Self.components(of: color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
        let dark = Self.components(of: color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
        Self.expect(light, matches: token.light)
        Self.expect(dark, matches: token.dark)
    }

    private static func components(of color: UIColor) -> [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let converted = color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(converted)
        return [red, green, blue, alpha]
    }

    private static func expect(
        _ components: [CGFloat],
        matches value: RGBAColor,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let expected = [value.red, value.green, value.blue, value.alpha].map { CGFloat($0) }
        for (actual, wanted) in zip(components, expected) {
            #expect(abs(actual - wanted) < 0.002, sourceLocation: sourceLocation)
        }
    }
}

// MARK: - Gallery

#if DEBUG
@Suite("KXDesignSystemGallery")
struct KXDesignSystemGalleryTests {
    @Test("Lists every foundation and component exactly once")
    func topicsArePartitioned() {
        let all = KXGalleryTopic.foundations + KXGalleryTopic.components
        #expect(all == KXGalleryTopic.allCases)
        #expect(KXGalleryTopic.foundations == [.colors, .typography, .layout])
        #expect(Set(all.map(\.title)).count == all.count)
        #expect(all.allSatisfy { !$0.summary.isEmpty && !$0.systemImage.isEmpty })
    }

    @Test("Has a page for every component of the design system")
    func coversComponents() {
        let titles = Set(KXGalleryTopic.components.map(\.title))
        let expected: Set = [
            "KXButton", "KXCard", "KXBadge", "KXPriceTag", "KXSectionHeader", "KXSpecRow", "KXDivider",
            "KXWordmark", "KXSkeleton", "KXEmptyState", "KXBanner", "KXStepTimeline", "KXAccordion",
            "KXCountdown", "KXTrustStrip", "KXProductCard", "KXKeyCard",
        ]
        #expect(titles == expected)
    }

    @Test("Shows every color token in exactly one group")
    func colorGroupsCoverTokens() {
        let grouped = KXGalleryColorGroup.all.flatMap(\.tokens)
        #expect(grouped.count == ColorToken.allCases.count)
        #expect(Set(grouped) == Set(ColorToken.allCases))
    }

    @Test("Maps the preview settings to environment overrides")
    func previewSettings() {
        #expect(KXGalleryAppearance.system.colorScheme == nil)
        #expect(KXGalleryAppearance.light.colorScheme == .light)
        #expect(KXGalleryAppearance.dark.colorScheme == .dark)
        #expect(KXGalleryTextSize.system.dynamicTypeSize == nil)
        #expect(KXGalleryTextSize.large.dynamicTypeSize == .large)
        #expect(KXGalleryTextSize.accessibility3.dynamicTypeSize == .accessibility3)
        #expect(KXGalleryTextSize.accessibility3.dynamicTypeSize?.isAccessibilitySize == true)
    }
}
#endif
