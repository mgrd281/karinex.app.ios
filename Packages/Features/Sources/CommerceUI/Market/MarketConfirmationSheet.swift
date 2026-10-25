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
            VStack(alignment: .leading, spacing: KXSpacing.l) {
                header
                if let reason = reasonText {
                    KXBanner(.info, message: reason)
                        .accessibilityIdentifier("market.reason")
                }
                KXCard {
                    VStack(alignment: .leading, spacing: KXSpacing.m) {
                        countryPicker
                        KXDivider()
                        languagePicker
                        if let currency = currencyText {
                            KXDivider()
                            KXSpecRow(String(localized: "commerce.market.currency", bundle: .module), value: currency)
                        }
                    }
                }
                Text("commerce.market.footnote", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                KXButton(
                    String(localized: "commerce.market.continue", bundle: .module),
                    isFullWidth: true,
                    isLoading: isSaving
                ) {
                    Task { await finish() }
                }
                .accessibilityIdentifier("market.continue")
            }
            .padding(KXSpacing.gutter)
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
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            Text("commerce.market.title", bundle: .module)
                .kxFont(.title1)
                .foregroundStyle(KXColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("commerce.market.message", bundle: .module)
                .kxFont(.body)
                .foregroundStyle(KXColor.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var countryPicker: some View {
        pickerRow(title: String(localized: "commerce.market.country", bundle: .module)) {
            Picker(selection: $country) {
                ForEach(store.availableCountries(locale: locale)) { entry in
                    Text(MarketStore.displayName(of: entry, locale: locale)).tag(entry.isoCode)
                }
            } label: {
                Text("commerce.market.country", bundle: .module)
            }
            .accessibilityIdentifier("market.country")
        }
    }

    private var languagePicker: some View {
        pickerRow(title: String(localized: "commerce.market.language", bundle: .module)) {
            Picker(selection: $language) {
                ForEach(store.availableLanguages(for: country)) { entry in
                    Text(MarketStore.displayName(of: entry, locale: locale)).tag(entry.isoCode)
                }
            } label: {
                Text("commerce.market.language", bundle: .module)
            }
            .accessibilityIdentifier("market.language")
        }
    }

    private func pickerRow(title: String, @ViewBuilder picker: () -> some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: KXSpacing.s) {
                pickerTitle(title)
                Spacer(minLength: KXSpacing.s)
                picker()
            }
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                pickerTitle(title)
                picker()
            }
        }
        .pickerStyle(.menu)
        .tint(KXColor.accentText)
        .frame(minHeight: KXSpacing.minimumTapTarget)
    }

    private func pickerTitle(_ title: String) -> some View {
        Text(title)
            .kxFont(.body)
            .foregroundStyle(KXColor.textPrimary)
            .accessibilityHidden(true)
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
