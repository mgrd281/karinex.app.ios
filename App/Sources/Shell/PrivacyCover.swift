import DesignSystem
import SwiftUI

// MARK: - PrivacyCover

/// Covers the app while it is not active, so the app switcher never shows license keys, orders
/// or addresses (PROMPT.md 11). Decorative and hidden from VoiceOver.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            KXColor.brand
                .ignoresSafeArea()
            KXWordmark(size: .large, color: KXColor.textOnBrand)
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("shell.privacyCover")
    }
}

// MARK: - AccountVersionText

/// The version line shown in the settings, e.g. `0.2.0 (12)`.
enum AccountVersionText {
    static func summary(version: String, build: String) -> String {
        let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = build.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (version.isEmpty, build.isEmpty) {
        case (false, false): return "\(version) (\(build))"
        case (false, true): return version
        case (true, false): return build
        case (true, true): return ""
        }
    }
}
