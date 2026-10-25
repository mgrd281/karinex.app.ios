import Foundation

// MARK: - EU membership

extension CountryCode {
    /// The 27 member states of the European Union (ISO 3166-1 alpha-2, Greece as `GR`), as of
    /// 2026. Used to choose the tax wording next to prices; it never drives a computation.
    public static let euMemberStates: Set<CountryCode> = [
        "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU",
        "IE", "IT", "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK",
    ]

    /// Whether the country is a member state of the European Union. `false` for Switzerland,
    /// Norway and every other non-EU market.
    public var isEUMember: Bool {
        Self.euMemberStates.contains(self)
    }
}
