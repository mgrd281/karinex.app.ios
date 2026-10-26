import CommerceUI
import Core
import DesignSystem
import SwiftUI
import UIKit

// MARK: - SettingsScreen

/// "Einstellungen" (PROMPT.md 6.10): shop country and content language, the app language
/// (through the iOS per-app setting, ADR 9), appearance, privacy consents, the license lock,
/// the legal texts and the app version. Notifications are off until the customer turns a
/// category on here; only then does iOS ask for permission.
public struct SettingsScreen: View {
    private let marketStore: MarketStore
    private let consentStore: any ConsentStoring
    private let pushCoordinator: PushRegistrationCoordinator?
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
    ///   - pushCoordinator: Registers for notifications after consent; `nil` hides the section.
    ///   - appVersion: The version line, e.g. `0.2.0 (12)`.
    ///   - onRoute: Opens the legal texts.
    public init(
        marketStore: MarketStore,
        settings: AppSettingsStore,
        consentStore: any ConsentStoring,
        pushCoordinator: PushRegistrationCoordinator? = nil,
        appVersion: String,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        self.marketStore = marketStore
        _settings = Bindable(settings)
        self.consentStore = consentStore
        self.pushCoordinator = pushCoordinator
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
                if pushCoordinator != nil {
                    notificationsSection
                }
                licensesSection
                legalAndAboutSection
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
            .kxReadableWidth()
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
        SettingsGroup(Text("settings.market.title", bundle: .module)) {
            marketRow(
                systemImage: "globe.europe.africa",
                title: Text("settings.market.country", bundle: .module),
                value: countryName,
                identifier: "settings.market.change"
            )
            SettingsRowDivider()
            marketRow(
                systemImage: "text.bubble",
                title: Text("settings.market.language", bundle: .module),
                value: languageName,
                identifier: "settings.market.language"
            )
        }
    }

    private func marketRow(systemImage: String, title: Text, value: String, identifier: String) -> some View {
        Button {
            isMarketSheetPresented = true
        } label: {
            SettingsRow(systemImage: systemImage, title: title, value: value, accessory: .chevron)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("settings.market.change", bundle: .module))
        .accessibilityIdentifier(identifier)
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
        SettingsGroup {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                SettingsRow(
                    systemImage: "character.bubble",
                    title: Text("settings.language.title", bundle: .module),
                    value: appLanguageName,
                    accessory: .external
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("settings.language.open", bundle: .module))
            .accessibilityIdentifier("settings.language.open")
        } footer: {
            Text("settings.language.message", bundle: .module)
        }
    }

    /// The language the app is shown in, e.g. "Deutsch".
    private var appLanguageName: String? {
        guard let code = locale.language.languageCode?.identifier,
              let name = locale.localizedString(forLanguageCode: code)
        else { return nil }
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        SettingsGroup(Text("settings.appearance.title", bundle: .module)) {
            ForEach(Array(AppSettingsStore.Appearance.allCases.enumerated()), id: \.element) { index, appearance in
                if index > 0 {
                    SettingsRowDivider()
                }
                let isSelected = settings.appearance == appearance
                Button {
                    settings.appearance = appearance
                } label: {
                    SettingsRow(
                        systemImage: Self.systemImage(of: appearance),
                        title: Text(Self.title(of: appearance)),
                        accessory: isSelected ? .checkmark : .none
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("settings.appearance.\(appearance.rawValue)")
            }
        }
        .accessibilityIdentifier("settings.appearance")
    }

    private static func title(of appearance: AppSettingsStore.Appearance) -> String {
        switch appearance {
        case .system: String(localized: "settings.appearance.system", bundle: .module)
        case .light: String(localized: "settings.appearance.light", bundle: .module)
        case .dark: String(localized: "settings.appearance.dark", bundle: .module)
        }
    }

    private static func systemImage(of appearance: AppSettingsStore.Appearance) -> String {
        switch appearance {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        SettingsGroup(Text("settings.privacy.title", bundle: .module)) {
            SettingsToggleRow(
                systemImage: "chart.bar.xaxis",
                title: Text("settings.privacy.analytics", bundle: .module),
                detail: Text("settings.privacy.analytics.detail", bundle: .module),
                isOn: consentBinding(\.analytics)
            )
            .accessibilityIdentifier("settings.privacy.analytics")
            SettingsRowDivider()
            SettingsToggleRow(
                systemImage: "exclamationmark.bubble",
                title: Text("settings.privacy.crash", bundle: .module),
                detail: Text("settings.privacy.crash.detail", bundle: .module),
                isOn: consentBinding(\.crashReports)
            )
            .accessibilityIdentifier("settings.privacy.crash")
        } footer: {
            Text("settings.privacy.footnote", bundle: .module)
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
                if keyPath == \.orderUpdateNotifications || keyPath == \.dealNotifications {
                    Task {
                        await pushCoordinator?.consentDidChange(updated)
                    }
                }
            }
        )
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        SettingsGroup(Text("settings.notifications.title", bundle: .module)) {
            SettingsToggleRow(
                systemImage: "shippingbox",
                title: Text("settings.notifications.orders", bundle: .module),
                detail: Text("settings.notifications.orders.detail", bundle: .module),
                isOn: consentBinding(\.orderUpdateNotifications)
            )
            .accessibilityIdentifier("settings.notifications.orders")
            SettingsRowDivider()
            SettingsToggleRow(
                systemImage: "tag",
                title: Text("settings.notifications.deals", bundle: .module),
                detail: Text("settings.notifications.deals.detail", bundle: .module),
                isOn: consentBinding(\.dealNotifications)
            )
            .accessibilityIdentifier("settings.notifications.deals")
        } footer: {
            if pushCoordinator?.isPermissionDenied == true {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("settings.notifications.denied", bundle: .module)
                        .multilineTextAlignment(.leading)
                }
                .accessibilityIdentifier("settings.notifications.denied")
            }
        }
    }

    // MARK: Licenses

    private var licensesSection: some View {
        SettingsGroup(Text("settings.licenses.title", bundle: .module)) {
            SettingsToggleRow(
                systemImage: "faceid",
                title: Text("settings.licenses.lock", bundle: .module),
                detail: Text("settings.licenses.lock.detail", bundle: .module),
                isOn: $settings.locksLicenses
            )
            .accessibilityIdentifier("settings.licenses.lock")
        }
    }

    // MARK: Legal and about

    private var legalAndAboutSection: some View {
        SettingsGroup(Text("settings.about.title", bundle: .module)) {
            Button {
                onRoute(.account(.legal))
            } label: {
                SettingsRow(
                    systemImage: "doc.text",
                    title: Text("settings.legal", bundle: .module),
                    accessory: .chevron
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.legal")
            SettingsRowDivider()
            SettingsRow(
                systemImage: "info.circle",
                title: Text("settings.about.version", bundle: .module),
                value: appVersion
            )
            .accessibilityIdentifier("settings.about")
        }
    }
}
