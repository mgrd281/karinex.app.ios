import DesignSystem
import SwiftUI

// MARK: - AccountView

/// The Konto tab for signed-out users.
///
/// It lists the benefits of an account (orders and invoices at any time, license keys stored
/// securely on this device, faster checkout) and states that signing in is not available in
/// this version: the passwordless Customer Account login arrives in Phase 2, so there is no
/// button that would do nothing. The "Über die App" section shows version and build; DEBUG builds
/// add a link to the design system gallery.
///
/// Place it inside a `NavigationStack`; it uses a large title and pushes the gallery.
public struct AccountView: View {
    private let appInfo: AccountAppInfo

    /// Creates the account screen.
    ///
    /// - Parameters:
    ///   - appVersion: The marketing version, e.g. `AppConfiguration.appVersion` ("0.1.0").
    ///   - buildNumber: The build number, e.g. `AppConfiguration.buildNumber` ("1").
    public init(appVersion: String, buildNumber: String) {
        appInfo = AccountAppInfo(version: appVersion, build: buildNumber)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                benefitsCard
                aboutSection
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
        }
        .accessibilityIdentifier("screen.account")
        .kxScreenBackground()
        .navigationTitle(Text("account.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Benefits

    private var benefitsCard: some View {
        KXCard(showsInsetRing: true) {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    Text("account.intro.eyebrow", bundle: .module)
                        .kxFont(.eyebrow)
                        .foregroundStyle(KXColor.accentText)
                    Text("account.intro.title", bundle: .module)
                        .kxFont(.title2)
                        .foregroundStyle(KXColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    ForEach(AccountBenefit.allCases) { benefit in
                        AccountBenefitRow(benefit: benefit)
                    }
                }
                KXDivider()
                Text("account.signin.note", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            // Keeps the content clear of the gold inset ring.
            .padding(KXSpacing.xs)
        }
        .accessibilityIdentifier("account.benefits")
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "account.about.title", bundle: .module))
            if !appInfo.summary.isEmpty {
                KXCard {
                    KXSpecRow(String(localized: "account.about.version", bundle: .module), value: appInfo.summary)
                }
                .accessibilityIdentifier("account.about")
            }
            #if DEBUG
            NavigationLink {
                KXDesignSystemGallery()
            } label: {
                // DEBUG-only developer tool; never shipped, so the label is not localized.
                Label {
                    Text(verbatim: "Design System")
                } icon: {
                    Image(systemName: "paintpalette")
                }
            }
            .buttonStyle(.kx(.secondary, isFullWidth: true))
            .accessibilityIdentifier("account.designSystem")
            #endif
        }
    }
}

// MARK: - Benefit row

/// One benefit: a decorative symbol and the text, read by VoiceOver as one element.
private struct AccountBenefitRow: View {
    let benefit: AccountBenefit

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
            Image(systemName: benefit.systemImage)
                .fontWeight(.medium)
                .kxFont(.body)
                .foregroundStyle(KXColor.brand)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(benefit.text)
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("AccountView, light") {
    NavigationStack {
        AccountView(appVersion: "0.1.0", buildNumber: "1")
    }
}

#Preview("AccountView, dark") {
    NavigationStack {
        AccountView(appVersion: "0.1.0", buildNumber: "1")
    }
    .preferredColorScheme(.dark)
}

#Preview("AccountView, accessibility size") {
    NavigationStack {
        AccountView(appVersion: "0.1.0", buildNumber: "1")
    }
    .dynamicTypeSize(.accessibility2)
}
