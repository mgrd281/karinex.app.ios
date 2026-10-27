import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - MarketConfirmationSheet

/// The one-time sheet after the first launch: explains which country, content language and
/// currency the store uses, says why when the device's region or language had to be adjusted
/// (`MarketResolution.reason`), lets the customer pick another country and content language
/// from the store's lists, and confirms with "Weiter".
///
/// Present it while ``MarketStore/needsConfirmation`` is `true`:
///
/// ```swift
/// .sheet(isPresented: $showsMarketSheet) {
///     MarketConfirmationSheet(store: marketStore)
/// }
/// ```
///
/// "Weiter" applies the choice, calls ``MarketStore/confirm()`` and dismisses the sheet.
public struct MarketConfirmationSheet: View {
    private let store: MarketStore
    private let onFinish: @MainActor () -> Void

    @State private var country: CountryCode
    @State private var language: LanguageCode
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title) private var heroSide: CGFloat = 64

    /// Creates the sheet.
    ///
    /// - Parameters:
    ///   - store: The market store.
    ///   - onFinish: Called after the choice was applied and confirmed, before the sheet dismisses.
    public init(store: MarketStore, onFinish: @escaping @MainActor () -> Void = {}) {
        self.store = store
        self.onFinish = onFinish
        _country = State(initialValue: store.selection.country)
        _language = State(initialValue: store.selection.language)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                header
                if let reason = reasonText {
                    KXBanner(.info, message: reason)
                        .accessibilityIdentifier("market.reason")
                }
                KXListGroup {
                    countryRow
                    KXListDivider()
                    languageRow
                    if let currency = currencyText {
                        KXListDivider()
                        KXListRow(
                            systemImage: "banknote",
                            title: Text("commerce.market.currency", bundle: .module),
                            value: currency
                        )
                        .accessibilityIdentifier("market.currency")
                    }
                } footer: {
                    Text("commerce.market.footnote", bundle: .module)
                }
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.top, KXSpacing.xl)
            .padding(.bottom, KXSpacing.l)
            .kxReadableWidth()
        }
        .safeAreaInset(edge: .bottom) {
            KXButton(
                String(localized: "commerce.market.continue", bundle: .module),
                isFullWidth: true,
                isLoading: isSaving
            ) {
                Task { await finish() }
            }
            .accessibilityIdentifier("market.continue")
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.top, KXSpacing.s)
            .padding(.bottom, KXSpacing.m)
            .kxReadableWidth()
            .background(KXColor.background)
        }
        .kxScreenBackground()
        .interactiveDismissDisabled(true)
        .accessibilityIdentifier("screen.market")
        .onChange(of: country) {
            let offered = store.availableLanguages(for: country).map(\.isoCode)
            if !offered.isEmpty, !offered.contains(language) {
                language = offered.first { $0 == store.selection.language } ?? offered[0]
            }
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            Image(systemName: "globe.europe.africa.fill")
                .kxFont(.title1)
                .foregroundStyle(KXColor.background)
                .frame(width: heroSide, height: heroSide)
                .background(KXColor.textPrimary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                Text("commerce.market.title", bundle: .module)
                    .kxFont(.title1)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("commerce.market.message", bundle: .module)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The country as a row that opens the store's countries in a menu.
    private var countryRow: some View {
        Menu {
            Picker(selection: $country) {
                ForEach(store.availableCountries(locale: locale)) { entry in
                    Text(MarketFlag.label(MarketStore.displayName(of: entry, locale: locale), country: entry.isoCode.rawValue))
                        .tag(entry.isoCode)
                }
            } label: {
                Text("commerce.market.country", bundle: .module)
            }
        } label: {
            KXListRow(
                systemImage: "mappin.and.ellipse",
                title: Text("commerce.market.country", bundle: .module),
                value: MarketFlag.label(countryName, country: country.rawValue),
                accessory: .menu
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("market.country")
    }

    /// The content language as a row that opens the languages of the chosen country.
    private var languageRow: some View {
        Menu {
            Picker(selection: $language) {
                ForEach(store.availableLanguages(for: country)) { entry in
                    Text(MarketStore.displayName(of: entry, locale: locale)).tag(entry.isoCode)
                }
            } label: {
                Text("commerce.market.language", bundle: .module)
            }
        } label: {
            KXListRow(
                systemImage: "text.bubble",
                title: Text("commerce.market.language", bundle: .module),
                value: languageName,
                accessory: .menu
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("market.language")
    }

    private var countryName: String {
        store.availableCountries(locale: locale).first { $0.isoCode == country }
            .map { MarketStore.displayName(of: $0, locale: locale) }
            ?? locale.localizedString(forRegionCode: country.rawValue)
            ?? country.rawValue
    }

    private var languageName: String {
        store.availableLanguages(for: country).first { $0.isoCode == language }
            .map { MarketStore.displayName(of: $0, locale: locale) }
            ?? language.rawValue
    }

    // MARK: Text

    private var currencyText: String? {
        guard let currency = store.localization?.country(for: country)?.currency else { return nil }
        let name = locale.localizedString(forCurrencyCode: currency.isoCode.rawValue) ?? currency.name
        return "\(name) (\(currency.isoCode.rawValue))"
    }

    private var reasonText: String? {
        guard let resolution = store.resolution, resolution.selection == store.selection else { return nil }
        switch resolution.reason {
        case .deviceMatch:
            return nil
        case .countryUnavailable:
            return String(localized: "commerce.market.reason.country", bundle: .module)
        case .languageUnavailable:
            return String(localized: "commerce.market.reason.language", bundle: .module)
        case .countryAndLanguageUnavailable:
            return String(localized: "commerce.market.reason.country_and_language", bundle: .module)
        }
    }

    // MARK: Actions

    private func finish() async {
        guard !isSaving else { return }
        isSaving = true
        if country != store.selection.country || language != store.selection.language {
            await store.select(country: country, language: language)
        }
        store.confirm()
        isSaving = false
        KXHaptics.confirm()
        onFinish()
        dismiss()
    }
}

// MARK: - MarketFlag

/// The flag emoji of a country before its name, e.g. "🇩🇪 Deutschland". Codes that are not two
/// letters get no flag.
enum MarketFlag {
    static func emoji(for country: String) -> String? {
        let letters = country.uppercased()
        guard letters.count == 2, letters.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        let scalars = letters.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }

    static func label(_ name: String, country: String) -> String {
        guard let flag = emoji(for: country) else { return name }
        return "\(flag) \(name)"
    }
}

// MARK: - Previews

private struct MarketConfirmationPreviewHost: View {
    @State private var store = CommercePreviewData.marketStore()

    var body: some View {
        MarketConfirmationSheet(store: store)
            .task { await store.start() }
    }
}

#Preview("MarketConfirmationSheet, light") {
    MarketConfirmationPreviewHost()
}

#Preview("MarketConfirmationSheet, dark, accessibility size") {
    MarketConfirmationPreviewHost()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
