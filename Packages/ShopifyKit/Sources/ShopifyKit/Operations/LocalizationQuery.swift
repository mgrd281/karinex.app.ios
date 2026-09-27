import Foundation

/// Loads the store's countries, currencies and languages (Storefront `localization`).
///
/// Used on first launch to resolve the device region and language to a supported market
/// (`MarketResolver`) and by the market picker in Settings.
public struct LocalizationQuery: GraphQLOperation {
    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The store localization.
        public let localization: Localization
    }

    /// `Localization`.
    public static let operationName = "Localization"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation followed by `LanguageFields` and `CountryFields`.
    public static let document = """
        query Localization {
          localization {
            country {
              ...CountryFields
            }
            language {
              ...LanguageFields
            }
            availableCountries {
              ...CountryFields
            }
            availableLanguages {
              ...LanguageFields
            }
          }
        }

        """ + StorefrontFragments.language + "\n\n" + StorefrontFragments.country + "\n"

    /// Creates the query.
    public init() {}
}
