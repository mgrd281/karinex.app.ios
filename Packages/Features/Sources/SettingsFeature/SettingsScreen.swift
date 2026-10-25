import CommerceUI
import Core
import DesignSystem
import SwiftUI
import UIKit

// MARK: - SettingsScreen

/// "Einstellungen" (PROMPT.md 6.10): shop country and content language, the app language
/// (through the iOS per-app setting, ADR 9), appearance, privacy consents, the license lock,
/// the legal texts and the app version. Push notifications follow in Phase 3.
public struct SettingsScreen: View {
    private let marketStore: MarketStore
    private let consentStore: any ConsentStoring
    private let appVersion: String
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @Bindable private var settings: AppSettingsStore
    @State private var consent: PrivacyConsent
    @State private var isMarketSheetPresented = false

    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    /// Creates the settings.
    ///
    /// - Parameters:
    ///   - marketStore: The shop country and content language.
    ///   - settings: Appearance and license lock.
    ///   - consentStore: The privacy consents.
    ///   - appVersion: The version line, e.g. `0.2.0 (12)`.
    ///   - onRoute: Opens the legal texts.
    public init(
        marketStore: MarketStore,
        settings: AppSettingsStore,
        consentStore: any ConsentStoring,
        appVersion: String,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        self.marketStore = marketStore
        _settings = Bindable(settings)
        self.consentStore = consentStore
        self.appVersion = appVersion
        self.onRoute = onRoute
        _consent = State(initialValue: consentStore.load())
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                marketSection
                languageSection
                appearanceSection
                privacySection
                licensesSection
                legalSection
                aboutSection
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.settings")
        .kxScreenBackground()
        .navigationTitle(Text("settings.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isMarketSheetPresented) {
            MarketConfirmationSheet(store: marketStore) {
                isMarketSheetPresented = false
            }
        }
    }

    // MARK: Market

    private var marketSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "settings.market.title", bundle: .module))
            KXCard {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    KXSpecRow(String(localized: "settings.market.country", bundle: .module), value: countryName)
                    KXSpecRow(String(localized: "settings.market.language", bundle: .module), value: languageName)
                    KXButton(
                        String(localized: "settings.market.change", bundle: .module),
                        style: .secondary,
                        isFullWidth: true
                    ) {
                        isMarketSheetPresented = true
                    }
                    .accessibilityIdentifier("settings.market.change")
                }
            }
        }
    }

    private var countryName: String {
        let code = marketStore.selection.country.rawValue
        return locale.localizedString(forRegionCode: code) ?? code
    }

    private var languageName: String {
        let code = marketStore.selection.language.rawValue.lowercased().replacingOccurrences(of: "_", with: "-")
        return locale.localizedString(forIdentifier: code) ?? code
    }

    // MARK: App language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "settings.language.title", bundle: .module))
            KXCard {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    Text("settings.language.message", bundle: .module)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    KXButton(
                        String(localized: "settings.language.open", bundle: .module),
                        systemImage: "gear",
                        style: .secondary,
                        isFullWidth: true
                    ) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .accessibilityIdentifier("settings.language.open")
                }
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "settings.appearance.title", bundle: .module))
            Picker(selection: $settings.appearance) {
                ForEach(AppSettingsStore.Appearance.allCases) { appearance in
                    Text(Self.title(of: appearance)).tag(appearance)
                }
            } label: {
                Text("settings.appearance.title", bundle: .module)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearance")
        }
    }

    private static func title(of appearance: AppSettingsStore.Appearance) -> String {
        switch appearance {
        case .system: String(localized: "settings.appearance.system", bundle: .module)
        case .light: String(localized: "settings.appearance.light", bundle: .module)
        case .dark: String(localized: "settings.appearance.dark", bundle: .module)
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "settings.privacy.title", bundle: .module))
            KXCard {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    Toggle(isOn: consentBinding(\.analytics)) {
                        SettingsToggleLabel(
                            title: String(localized: "settings.privacy.analytics", bundle: .module),
                            detail: String(localized: "settings.privacy.analytics.detail", bundle: .module)
                        )
                    }
                    .accessibilityIdentifier("settings.privacy.analytics")
                    KXDivider()
                    Toggle(isOn: consentBinding(\.crashReports)) {
                        SettingsToggleLabel(
                            title: String(localized: "settings.privacy.crash", bundle: .module),
                            detail: String(localized: "settings.privacy.crash.detail", bundle: .module)
                        )
                    }
                    .accessibilityIdentifier("settings.privacy.crash")
                }
                .tint(KXColor.brand)
            }
            Text("settings.privacy.footnote", bundle: .module)
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A binding to one consent that saves the decision and updates the buyer context, so
    /// Shopify checkout applies the same consent.
    private func consentBinding(_ keyPath: WritableKeyPath<PrivacyConsent, Bool>) -> Binding<Bool> {
        Binding(
            get: { consent[keyPath: keyPath] },
            set: { newValue in
                var updated = consent
                updated[keyPath: keyPath] = newValue
                updated = updated.decided()
                consent = updated
                consentStore.save(updated)
                marketStore.consentDidChange()
            }
        )
    }

    // MARK: Licenses

    private var licensesSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "settings.licenses.title", bundle: .module))
            KXCard {
                Toggle(isOn: $settings.locksLicenses) {
                    SettingsToggleLabel(
                        title: String(localized: "settings.licenses.lock", bundle: .module),
                        detail: String(localized: "settings.licenses.lock.detail", bundle: .module)
                    )
                }
                .tint(KXColor.brand)
                .accessibilityIdentifier("settings.licenses.lock")
            }
        }
    }

    // MARK: Legal and about

    private var legalSection: some View {
        KXButton(
            String(localized: "settings.legal", bundle: .module),
            systemImage: "doc.text",
            style: .secondary,
            isFullWidth: true
        ) {
            onRoute(.account(.legal))
        }
        .accessibilityIdentifier("settings.legal")
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "settings.about.title", bundle: .module))
            KXCard {
                KXSpecRow(String(localized: "settings.about.version", bundle: .module), value: appVersion)
            }
            .accessibilityIdentifier("settings.about")
        }
    }
}

// MARK: - SettingsToggleLabel

/// A toggle label with a title and a secondary explanation.
private struct SettingsToggleLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            Text(title)
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
            Text(detail)
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
