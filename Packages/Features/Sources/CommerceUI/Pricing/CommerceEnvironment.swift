import ShopifyKit
import SwiftUI

// MARK: - Market country in the environment

extension EnvironmentValues {
    /// The country of the active market. Price views use it for the tax note ("inkl. MwSt." in
    /// EU markets, nothing in Switzerland). Defaults to Germany; the App sets it from
    /// ``MarketStore/selection`` with `commerceCountry(_:)`.
    public var commerceCountry: CountryCode {
        get { self[CommerceCountryKey.self] }
        set { self[CommerceCountryKey.self] = newValue }
    }
}

private struct CommerceCountryKey: EnvironmentKey {
    static let defaultValue: CountryCode = .de
}

extension View {
    /// Sets the country of the active market for every price in this view hierarchy.
    ///
    /// ```swift
    /// RootView()
    ///     .commerceCountry(marketStore.selection.country)
    /// ```
    public func commerceCountry(_ country: CountryCode) -> some View {
        environment(\.commerceCountry, country)
    }
}
