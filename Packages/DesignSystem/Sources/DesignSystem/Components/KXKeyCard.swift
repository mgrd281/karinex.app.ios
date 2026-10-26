import Foundation
import SwiftUI

// MARK: - KXLicenseKeyFormatting

/// Pure helpers that split a license key into display groups and lines, and mask it.
///
/// Keys are displayed in groups so that a key never breaks inside a group: at the dashes when
/// the key has dashes (`XXXXX-00000-XXXXX-00000-XXXXX`), otherwise at whitespace, otherwise in
/// chunks of ``fallbackGroupLength`` characters (line breaks only, no characters added).
public enum KXLicenseKeyFormatting {
    /// The character that replaces every key character while the key is hidden.
    public static let maskCharacter: Character = "\u{2022}"
    /// Group length used for keys without dashes or whitespace.
    public static let fallbackGroupLength = 5

    /// The display groups of `key`, without separators.
    public static func groups(of key: String) -> [String] {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains("-") {
            return trimmed.split(separator: "-").map(String.init)
        }
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count > 1 {
            return words
        }
        var chunks: [String] = []
        var start = trimmed.startIndex
        while start < trimmed.endIndex {
            let end = trimmed.index(start, offsetBy: fallbackGroupLength, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            chunks.append(String(trimmed[start..<end]))
            start = end
        }
        return chunks
    }

    /// The display lines of `key` with at most `groupsPerLine` groups per line.
    ///
    /// Groups of a dashed key are joined with "-" and every line except the last ends with the
    /// dash, so the key reads the same as on one line (`XXXXX-00000-` / `XXXXX`). Groups of a
    /// whitespace-separated key are joined with a space. Chunks of an unseparated key are joined
    /// without separator.
    ///
    /// - Parameters:
    ///   - key: The key (or its masked form).
    ///   - groupsPerLine: Maximum groups per line; values below 1 count as 1.
    public static func lines(of key: String, groupsPerLine: Int) -> [String] {
        let keyGroups = Self.groups(of: key)
        guard !keyGroups.isEmpty else { return [] }
        let joiner = Self.separator(of: key)
        let perLine = max(1, groupsPerLine)
        var result: [String] = []
        var index = 0
        while index < keyGroups.count {
            let end = min(index + perLine, keyGroups.count)
            var line = keyGroups[index..<end].joined(separator: joiner)
            if end < keyGroups.count, joiner == "-" {
                line += joiner
            }
            result.append(line)
            index = end
        }
        return result
    }

    /// Group counts per line to try, from the widest layout to the narrowest, e.g. `[5, 3, 2, 1]`
    /// for five groups. Always ends with 1 and never contains duplicates.
    public static func groupsPerLineCandidates(forGroupCount count: Int) -> [Int] {
        guard count > 1 else { return [1] }
        var candidates: [Int] = []
        for candidate in [count, (count + 1) / 2, 2, 1] where candidate <= count && !candidates.contains(candidate) {
            candidates.append(candidate)
        }
        return candidates
    }

    /// `key` with every character except dashes and whitespace replaced by ``maskCharacter``,
    /// so the masked key keeps the grouping of the real one.
    public static func masked(_ key: String) -> String {
        String(key.map { $0 == "-" || $0.isWhitespace ? $0 : maskCharacter })
    }

    /// Stand-in letters for a hidden key: the same grouping, but fixed characters that say
    /// nothing about the real key. ``KXKeyCard`` shows them blurred while the key is hidden, so
    /// the real key is never on screen, not even blurred.
    public static func veiled(_ key: String) -> String {
        let letters = Array("K7Q2MX9B4TR8VN3H")
        var index = 0
        return String(key.map { character in
            guard character != "-", !character.isWhitespace else { return character }
            defer { index += 1 }
            return letters[index % letters.count]
        })
    }

    /// The separator used to join groups when displaying `key`.
    static func separator(of key: String) -> String {
        if key.contains("-") {
            return "-"
        }
        if key.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: \.isWhitespace) {
            return " "
        }
        return ""
    }
}

// MARK: - KXKeyCard

/// A license card in the style of a premium payment card: a black panel with the product name,
/// the eyebrow "Lizenzschlüssel" and the monospaced key, which wraps between its groups.
///
/// Actions:
/// - "Kopieren" copies the key with ``KXClipboard/copySensitive(_:expiresAfter:)`` (local to
///   this device, removed after two minutes), plays the success haptic, announces "Lizenzschlüssel
///   kopiert" to VoiceOver and shows "Kopiert" for two seconds.
/// - The round eye button beside "Kopieren", or a tap on the key field, toggles `isRevealed`.
///   The key stays on one line (it shrinks to fit; it wraps only at accessibility text sizes). While hidden the
///   field shows blurred stand-in letters with "Zum Anzeigen tippen" (``KXLicenseKeyFormatting/veiled(_:)``;
///   the real key is never drawn) and copying still works.
/// - "Anleitung" and "Support zu dieser Lizenz" appear only when their closures are passed.
///
/// VoiceOver reads the revealed key character by character (`speechSpellsOutCharacters`), and
/// "Lizenzschlüssel verborgen" while it is hidden. The key is marked `privacySensitive`, so it
/// is redacted wherever the system hides private content.
///
/// The card uses the `keyCard*` color tokens and is dark in light and dark mode. Its buttons
/// are ``KXButtonStyle`` buttons in their dark-appearance colors, because the panel is a dark
/// surface in both appearances: "Kopieren" is white with a black label, the eye button is a
/// light disc, "Anleitung" and "Support zu dieser Lizenz" are white text links.
///
/// ```swift
/// @State private var isRevealed = false
///
/// KXKeyCard(
///     productName: license.productTitle,
///     licenseKey: license.key,
///     isRevealed: $isRevealed,
///     onShowGuide: { router.showGuide(for: license) },
///     onContactSupport: { router.contactSupport(about: license) }
/// )
/// ```
public struct KXKeyCard: View {
    private let productName: String
    private let licenseKey: String
    private let subtitle: String?
    @Binding private var isRevealed: Bool
    private let onShowGuide: (@MainActor () -> Void)?
    private let onContactSupport: (@MainActor () -> Void)?

    @State private var showsCopiedConfirmation = false
    @State private var copyCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .headline) private var iconSide: CGFloat = 36
    @ScaledMetric(relativeTo: .headline) private var revealSide: CGFloat = KXSpacing.minimumTapTarget
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a license key card.
    ///
    /// - Parameters:
    ///   - productName: The product title from the store.
    ///   - licenseKey: The license key. It is never logged.
    ///   - isRevealed: Whether the key is shown in clear text. When `false` the key is masked and
    ///     the card offers "Anzeigen".
    ///   - subtitle: Optional already-localized secondary line below the product name, e.g. an
    ///     order reference.
    ///   - onShowGuide: Optional action for "Anleitung" (activation guide). The button is hidden
    ///     when `nil`.
    ///   - onContactSupport: Optional action for "Support zu dieser Lizenz". The button is hidden
    ///     when `nil`.
    public init(
        productName: String,
        licenseKey: String,
        isRevealed: Binding<Bool>,
        subtitle: String? = nil,
        onShowGuide: (@MainActor () -> Void)? = nil,
        onContactSupport: (@MainActor () -> Void)? = nil
    ) {
        self.productName = productName
        self.licenseKey = licenseKey
        self.subtitle = subtitle
        _isRevealed = isRevealed
        self.onShowGuide = onShowGuide
        self.onContactSupport = onContactSupport
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            header
            keyField
            Group {
                actions
                if onShowGuide != nil || onContactSupport != nil {
                    links
                }
            }
            // The panel is dark in both appearances; the dark-appearance button tokens are the
            // pairings allowed on it (white on black, black on white).
            .environment(\.colorScheme, .dark)
        }
        .padding(KXSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.keyCardBackground, in: shape)
        .overlay {
            shape
                .strokeBorder(KXColor.hairline, lineWidth: hairlineWidth)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .task(id: copyCount) {
            await hideCopiedConfirmationAfterDelay()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: KXSpacing.m) {
            Image(systemName: "key.fill")
                .kxFont(.headline)
                .foregroundStyle(KXColor.keyCardBackground)
                .frame(width: iconSide, height: iconSide)
                .background(KXColor.keyCardText, in: RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(productName)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.keyCardText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.keyCardMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The key on one line in an inset field: clear text when revealed, otherwise blurred
    /// stand-in letters under "Zum Anzeigen tippen". A tap toggles it. Only at accessibility
    /// text sizes the key may wrap between its groups.
    private var keyField: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
        let shown = isRevealed ? licenseKey : KXLicenseKeyFormatting.veiled(licenseKey)
        return Button {
            toggleReveal()
        } label: {
            ZStack {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        KXLicenseKeyText(key: shown)
                    } else {
                        Text(verbatim: shown)
                            .lineLimit(1)
                            .minimumScaleFactor(KXKeyCardMetrics.minimumKeyScale)
                    }
                }
                .kxFont(.licenseKey)
                .foregroundStyle(KXColor.keyCardText)
                .blur(radius: isRevealed ? 0 : KXKeyCardMetrics.veilBlur)
                .opacity(isRevealed ? 1 : 0.55)
                .frame(maxWidth: .infinity, alignment: .center)
                if !isRevealed {
                    HStack(spacing: KXSpacing.xs) {
                        Image(systemName: "eye")
                            .accessibilityHidden(true)
                        Text("kx.keycard.tap_to_reveal", bundle: .module)
                    }
                    .kxFont(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(KXColor.keyCardBackground)
                    .padding(.horizontal, KXSpacing.m)
                    .padding(.vertical, KXSpacing.xs)
                    .background(KXColor.keyCardText, in: Capsule())
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, KXSpacing.m)
            .padding(.vertical, KXSpacing.l)
            .background(KXColor.keyCardText.opacity(0.08), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("kx.keycard.eyebrow", bundle: .module) + Text(verbatim: ", ") + keyAccessibilityLabel)
        .accessibilityHint(isRevealed ? Text("kx.keycard.hide", bundle: .module) : Text("kx.keycard.tap_to_reveal", bundle: .module))
        .speechSpellsOutCharacters(isRevealed)
        .privacySensitive()
    }

    /// "Kopieren" across the card and a round eye button that shows or hides the key.
    private var actions: some View {
        HStack(spacing: KXSpacing.s) {
            copyButton
            Button {
                toggleReveal()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.keyCardText)
                    .frame(width: revealSide, height: revealSide)
                    .background(KXColor.keyCardText.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? Text("kx.keycard.hide", bundle: .module) : Text("kx.keycard.reveal", bundle: .module))
        }
    }

    /// "Anleitung" and "Support zu dieser Lizenz" as quiet text links.
    private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: KXSpacing.l) {
                guideButton
                supportButton
            }
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                guideButton
                supportButton
            }
        }
    }

    // MARK: Buttons

    private var copyButton: some View {
        Button {
            copyKey()
        } label: {
            HStack(spacing: KXSpacing.xs) {
                Image(systemName: showsCopiedConfirmation ? "checkmark" : "doc.on.doc")
                    .accessibilityHidden(true)
                if showsCopiedConfirmation {
                    Text("kx.keycard.copied", bundle: .module)
                } else {
                    Text("kx.keycard.copy", bundle: .module)
                }
            }
        }
        .buttonStyle(.kx(.primary, size: .compact, isFullWidth: true))
        .accessibilityHint(Text("kx.keycard.copy.hint", bundle: .module))
    }

    @ViewBuilder private var guideButton: some View {
        if let onShowGuide {
            Button {
                onShowGuide()
            } label: {
                HStack(spacing: KXSpacing.xs) {
                    Image(systemName: "book")
                        .accessibilityHidden(true)
                    Text("kx.keycard.guide", bundle: .module)
                }
            }
            .buttonStyle(.kx(.tertiary, size: .compact))
        }
    }

    @ViewBuilder private var supportButton: some View {
        if let onContactSupport {
            Button {
                onContactSupport()
            } label: {
                HStack(spacing: KXSpacing.xs) {
                    Image(systemName: "lifepreserver")
                        .accessibilityHidden(true)
                    Text("kx.keycard.support", bundle: .module)
                }
            }
            .buttonStyle(.kx(.tertiary, size: .compact))
        }
    }

    // MARK: Behavior

    private func toggleReveal() {
        withAnimation(KXMotion.animation(.fade, reduceMotion: reduceMotion)) {
            isRevealed.toggle()
        }
    }

    private func copyKey() {
        KXClipboard.copySensitive(licenseKey)
        KXHaptics.success()
        AccessibilityNotification.Announcement(
            String(localized: "kx.keycard.copied.announcement", bundle: .module)
        ).post()
        withAnimation(KXMotion.animation(.snappy, reduceMotion: reduceMotion)) {
            showsCopiedConfirmation = true
        }
        // Restarts the `.task(id:)` timer, so repeated copies keep the confirmation visible.
        copyCount &+= 1
    }

    private func hideCopiedConfirmationAfterDelay() async {
        guard copyCount != 0 else { return }
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            // Cancelled because the key was copied again or the card left the screen.
            return
        }
        withAnimation(KXMotion.animation(.fade, reduceMotion: reduceMotion)) {
            showsCopiedConfirmation = false
        }
    }

    // MARK: Accessibility

    private var keyAccessibilityLabel: Text {
        if isRevealed {
            return Text(verbatim: licenseKey).speechSpellsOutCharacters()
        }
        return Text("kx.keycard.accessibility.hidden", bundle: .module)
    }

    /// One physical pixel.
    private var hairlineWidth: CGFloat {
        1 / max(displayScale, 1)
    }
}

// MARK: - Metrics

/// Fixed metrics of ``KXKeyCard`` that have no general design token.
private enum KXKeyCardMetrics {
    /// Blur of the stand-in letters while the key is hidden: the grouping stays visible, the
    /// letters do not.
    static let veilBlur: CGFloat = 6
    /// How far the key may shrink to stay on one line (a 29 character key on a small iPhone).
    static let minimumKeyScale: CGFloat = 0.5
}

// MARK: - Key text

/// The key in lines of whole groups: all groups on one line when they fit, otherwise the
/// widest grouping that fits, down to one group per line (which may wrap at the largest text
/// sizes).
private struct KXLicenseKeyText: View {
    let key: String

    var body: some View {
        let groupCount = KXLicenseKeyFormatting.groups(of: key).count
        let candidates = KXLicenseKeyFormatting.groupsPerLineCandidates(forGroupCount: groupCount)
        ViewThatFits(in: .horizontal) {
            KXLicenseKeyLines(lines: lines(candidates, at: 0), allowsWrapping: false)
            KXLicenseKeyLines(lines: lines(candidates, at: 1), allowsWrapping: false)
            KXLicenseKeyLines(lines: lines(candidates, at: 2), allowsWrapping: false)
            KXLicenseKeyLines(lines: KXLicenseKeyFormatting.lines(of: key, groupsPerLine: 1), allowsWrapping: true)
        }
    }

    /// The lines for the candidate at `index`, repeating the narrowest candidate when there
    /// are fewer candidates than layouts.
    private func lines(_ candidates: [Int], at index: Int) -> [String] {
        let groupsPerLine = candidates.isEmpty ? 1 : candidates[min(index, candidates.count - 1)]
        return KXLicenseKeyFormatting.lines(of: key, groupsPerLine: groupsPerLine)
    }
}

private struct KXLicenseKeyLines: View {
    let lines: [String]
    let allowsWrapping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .fixedSize(horizontal: !allowsWrapping, vertical: true)
            }
        }
    }
}

// MARK: - Previews

// Product names recorded from the live Storefront API on 2026-09-26 (Storefront API 2026-10,
// DE/DE). The key is an obviously fake placeholder; real keys never appear in code.
private struct KXKeyCardPreviewGallery: View {
    @State private var isOfficeKeyRevealed = true
    @State private var isWindowsKeyRevealed = false

    var body: some View {
        ScrollView {
            VStack(spacing: KXSpacing.l) {
                KXKeyCard(
                    productName: "Microsoft Office 2024 Professional Plus Download kaufen",
                    licenseKey: "XXXXX-00000-XXXXX-00000-XXXXX",
                    isRevealed: $isOfficeKeyRevealed,
                    onShowGuide: {},
                    onContactSupport: {}
                )
                KXKeyCard(
                    productName: "Windows 11 Pro kaufen \u{2013} Dauerlizenz 1 PC, Download",
                    licenseKey: "XXXXX-00000-XXXXX-00000-XXXXX",
                    isRevealed: $isWindowsKeyRevealed
                )
            }
            .padding(KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXKeyCard, light") {
    KXKeyCardPreviewGallery()
}

#Preview("KXKeyCard, dark") {
    KXKeyCardPreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("KXKeyCard, accessibility size") {
    KXKeyCardPreviewGallery()
        .dynamicTypeSize(.accessibility2)
}
