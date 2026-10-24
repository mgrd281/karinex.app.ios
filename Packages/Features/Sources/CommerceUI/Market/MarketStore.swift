import Core
import Foundation
import Observation
import ShopifyKit

// MARK: - MarketStore

/// Owns the market (country and content language) the store is shown in.
///
/// On first launch ``start()`` loads the store's `Localization`, resolves the market from the
/// device region and the preferred languages with `MarketResolver`, persists the
/// `MarketSelection` under ``selectionKey`` and sets ``needsConfirmation`` so the App shows
/// ``MarketConfirmationSheet`` once. Later launches reuse the stored selection (checked against
/// the store's current list).
///
/// Every change is pushed into the `MutableStorefrontContextProvider` (with the visitor consent
/// from `ConsentStoring`), so the next Storefront request uses it, and a country change is
/// reported to ``onCountryChange`` (the App forwards it to `CartStore.updateCountry(_:)`).
@MainActor
@Observable
public final class MarketStore {
    /// The key the selection is stored under.
    public static let selectionKey = "market.selection.v1"
    /// The key that records that the customer confirmed the selection.
    public static let confirmedKey = "market.confirmed.v1"

    // MARK: State

    /// The active market.
    public private(set) var selection: MarketSelection
    /// The store's countries and languages, once loaded.
    public private(set) var localization: Localization?
    /// The automatic resolution of the first launch, with the reason when the device's
    /// region or language had to be adjusted. `nil` when the selection came from storage.
    public private(set) var resolution: MarketResolution?
    /// Whether the confirmation sheet should be shown: `true` once after the first automatic
    /// resolution, `false` after ``confirm()``.
    public private(set) var needsConfirmation = false
    /// The last failure of ``start()``, if the store's markets could not be loaded.
    public private(set) var lastError: UserFacingError?

    /// Called after the market country changed, e.g. to move the cart to the new country.
    public var onCountryChange: (@MainActor (CountryCode) async -> Void)?

    // MARK: Dependencies

    @ObservationIgnored private let localizationRepository: any LocalizationRepository
    @ObservationIgnored private let contextProvider: MutableStorefrontContextProvider
    @ObservationIgnored private let consentStore: any ConsentStoring
    @ObservationIgnored private let store: any KeyValueStore
    @ObservationIgnored private let resolver: MarketResolver
    @ObservationIgnored private let regionCode: @Sendable () -> String?
    @ObservationIgnored private let preferredLanguages: @Sendable () -> [String]
    @ObservationIgnored private let logger: KXLogger

    /// Creates the market store and immediately applies a stored selection to the context
    /// provider, so the first requests of a later launch already use it.
    ///
    /// - Parameters:
    ///   - localizationRepository: Loads the store's countries and languages.
    ///   - contextProvider: Receives the `@inContext` values for every Storefront request.
    ///   - consentStore: Supplies the visitor consent sent with the context.
    ///   - store: Where the selection is persisted.
    ///   - resolver: The market resolution rules.
    ///   - regionCode: The device region, `Locale.current.region` by default.
    ///   - preferredLanguages: The languages in order of preference: the app's UI language
    ///     first, then the system's preferred languages.
    ///   - logger: The logger.
    public init(
        localizationRepository: any LocalizationRepository,
        contextProvider: MutableStorefrontContextProvider,
        consentStore: any ConsentStoring,
        store: any KeyValueStore,
        resolver: MarketResolver = MarketResolver(),
        regionCode: @escaping @Sendable () -> String? = { Locale.current.region?.identifier },
        preferredLanguages: @escaping @Sendable () -> [String] = {
            Bundle.main.preferredLocalizations + Locale.preferredLanguages
        },
        logger: KXLogger = KXLogger(category: .storefront)
    ) {
        self.localizationRepository = localizationRepository
        self.contextProvider = contextProvider
        self.consentStore = consentStore
        self.store = store
        self.resolver = resolver
        self.regionCode = regionCode
        self.preferredLanguages = preferredLanguages
        self.logger = logger
        selection = contextProvider.context.marketSelection
        if let stored = storedSelection {
            selection = stored
            pushContext()
        }
    }

    // MARK: Lifecycle

    /// Loads the store's markets and settles the selection: resolves it on first launch (and
    /// asks for confirmation), otherwise validates the stored one against the store's list.
    /// Safe to call again, e.g. after a failure.
    public func start() async {
        let loaded: Localization
        do {
            loaded = try await localizationRepository.localization()
        } catch {
            if let failure = UserFacingError(error) {
                lastError = failure
                logger.error("Store markets could not be loaded: \((error as? ShopifyError)?.logDescription ?? "unknown")")
            }
            return
        }
        localization = loaded
        lastError = nil

        if let stored = storedSelection, Self.isValid(stored, in: loaded) {
            needsConfirmation = store.bool(forKey: Self.confirmedKey) != true
            await apply(stored)
            return
        }
        let resolved = resolver.resolve(regionCode: regionCode(), preferredLanguages: preferredLanguages(), localization: loaded)
        resolution = resolved
        needsConfirmation = true
        store.set(false, forKey: Self.confirmedKey)
        await apply(resolved.selection)
    }

    /// Records that the customer confirmed the market; the sheet is not shown again.
    public func confirm() {
        needsConfirmation = false
        store.set(true, forKey: Self.confirmedKey)
    }

    /// Switches to another country and content language. A language the country does not
    /// offer is replaced by the resolver's fallback for that country.
    public func select(country: CountryCode, language: LanguageCode) async {
        var next = MarketSelection(country: country, language: language)
        if let localization {
            guard localization.sells(to: country) else { return }
            if !Self.isValid(next, in: localization) {
                next = resolver.resolve(
                    regionCode: country.rawValue,
                    preferredLanguages: [language.rawValue.replacingOccurrences(of: "_", with: "-")] + preferredLanguages(),
                    localization: localization
                ).selection
            }
        }
        await apply(next)
    }

    /// Sends the current visitor consent with the context again, after the customer changed
    /// their privacy choices.
    public func consentDidChange() {
        pushContext()
    }

    // MARK: Lists for pickers

    /// The countries the store sells to, sorted by their name in `locale`.
    public func availableCountries(locale: Locale = .current) -> [Country] {
        (localization?.availableCountries ?? []).sorted {
            Self.displayName(of: $0, locale: locale).localizedStandardCompare(Self.displayName(of: $1, locale: locale))
                == .orderedAscending
        }
    }

    /// The content languages `country` offers, in the store's order.
    public func availableLanguages(for country: CountryCode) -> [Language] {
        localization?.country(for: country)?.availableLanguages ?? []
    }

    /// The store's country entry for the active market.
    public var currentCountry: Country? {
        localization?.country(for: selection.country)
    }

    /// The name of `country` in `locale`, falling back to the store's own name.
    public static func displayName(of country: Country, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: country.isoCode.rawValue) ?? country.name
    }

    /// The name of `language` in `locale`, falling back to the store's endonym.
    public static func displayName(of language: Language, locale: Locale = .current) -> String {
        let identifier = language.isoCode.rawValue.lowercased().replacingOccurrences(of: "_", with: "-")
        return locale.localizedString(forIdentifier: identifier) ?? language.endonymName
    }

    // MARK: Private

    private var storedSelection: MarketSelection? {
        do {
            return try store.value(MarketSelection.self, forKey: Self.selectionKey)
        } catch {
            logger.error("Stored market selection is unreadable; resolving it again")
            return nil
        }
    }

    private func apply(_ next: MarketSelection) async {
        let previousCountry = contextProvider.context.country
        selection = next
        do {
            try store.setValue(next, forKey: Self.selectionKey)
        } catch {
            logger.fault("Market selection could not be encoded")
        }
        pushContext()
        if previousCountry != next.country {
            await onCountryChange?(next.country)
        }
    }

    private func pushContext() {
        let consent = VisitorConsent(privacyConsent: consentStore.load())
        contextProvider.update(to: selection.storefrontContext(visitorConsent: consent))
    }

    /// Whether the store sells to the selection's country in its language.
    static func isValid(_ selection: MarketSelection, in localization: Localization) -> Bool {
        localization.country(for: selection.country)?.offers(selection.language) ?? false
    }
}

// MARK: - StorefrontContext

extension StorefrontContext {
    /// The market part of the context.
    fileprivate var marketSelection: MarketSelection {
        MarketSelection(country: country, language: language)
    }
}
