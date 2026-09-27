import Foundation

// MARK: - LocalizationRepository

/// Read access to the store's markets and languages.
public protocol LocalizationRepository: Sendable {
    /// The store localization for the current buyer context.
    ///
    /// - Throws: `ShopifyError`.
    func localization() async throws -> Localization
}

// MARK: - StorefrontLocalizationRepository

/// `LocalizationRepository` backed by the Storefront `localization` query.
public final class StorefrontLocalizationRepository: LocalizationRepository {
    private let client: StorefrontClient
    private let contextProvider: any StorefrontContextProviding

    /// Creates a repository.
    ///
    /// - Parameters:
    ///   - client: The Storefront client.
    ///   - contextProvider: Supplies the buyer context (country names are localized into its
    ///     language).
    public init(client: StorefrontClient, contextProvider: any StorefrontContextProviding) {
        self.client = client
        self.contextProvider = contextProvider
    }

    /// Loads the localization in the current context.
    public func localization() async throws -> Localization {
        let context = await contextProvider.currentContext()
        return try await client.execute(LocalizationQuery(), context: context).localization
    }
}
