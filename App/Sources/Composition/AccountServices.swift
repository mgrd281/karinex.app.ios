import BackendKit
import Core
import Foundation
import ShopifyKit

// MARK: - AccountServices

/// Builds the login, the Customer Account API and the backend client from the configuration.
///
/// - Login needs a client ID and a shop ID (`AppConfiguration.isLoginConfigured`); without them
///   there is no session and the repository reports every customer as signed out.
/// - The backend needs `KXBackendHost`; without it `UnavailableBackendClient` makes the screens
///   show their e-mail fallbacks. Customer endpoints send the Customer Account access token.
struct AccountServices {
    /// The OAuth session, `nil` without login configuration.
    let session: CustomerAccountSession?
    /// The customer data.
    let repository: any CustomerAccountRepository
    /// The backend.
    let backend: any BackendClient
    /// Whether the Keychain holds tokens from an earlier launch.
    let hasStoredTokens: Bool

    init(configuration: AppConfiguration, services: AppServices) {
        let discovery = CustomerAccountDiscovery(
            openIDConfigurationURL: configuration.openIDConfigurationURL,
            customerAccountAPIURL: configuration.customerAccountDiscoveryURL,
            apiVersion: configuration.customerAccountAPIVersion,
            httpClient: services.httpClient
        )
        let session: CustomerAccountSession? = if configuration.isLoginConfigured,
                                                  let clientID = configuration.customerAccountClientID,
                                                  let redirectURI = configuration.customerAccountRedirectURI
        {
            CustomerAccountSession(
                clientID: clientID,
                redirectURI: redirectURI,
                discovery: discovery,
                httpClient: services.httpClient,
                secureStore: services.secureStore
            )
        } else {
            nil
        }
        self.session = session
        if let session {
            let client = CustomerAccountAPIClient(discovery: discovery, session: session, httpClient: services.httpClient)
            repository = ShopifyCustomerAccountRepository(client: client)
        } else {
            repository = UnavailableCustomerAccountRepository()
        }
        if let baseURL = configuration.backendBaseURL {
            backend = HTTPBackendClient(
                baseURL: baseURL,
                httpClient: services.httpClient,
                accessToken: {
                    guard let session else { throw BackendError.unauthorized }
                    return try await session.accessToken()
                },
                appVersion: configuration.appVersion,
                languageCode: { Bundle.main.preferredLocalizations.first ?? "de" }
            )
        } else {
            backend = UnavailableBackendClient()
        }
        hasStoredTokens = session != nil && ((try? services.secureStore.data(for: CustomerAccountSession.tokenStorageKey)) ?? nil) != nil
    }
}
