import BackendKit
import CommerceUI
import DesignSystem
import Foundation
import Observation
import SwiftUI

// MARK: - DeleteAccountViewModel

/// The account deletion request (PROMPT.md 6.7, App Store guideline 5.1.1(v)): the backend
/// starts the GDPR erasure, Shopify confirms by e-mail, and the app signs out and wipes the
/// cached keys right away.
@MainActor
@Observable
final class DeleteAccountViewModel {
    /// The state of the request.
    enum State: Equatable {
        case idle
        case sending
        /// The backend accepted the request.
        case requested
        /// No backend yet: the request goes to customer service by e-mail.
        case byEmail
        case failed(UserFacingError)
    }

    /// The state.
    private(set) var state: State = .idle

    @ObservationIgnored private let backend: any BackendClient
    @ObservationIgnored private let sessionStore: CustomerSessionStore

    init(backend: any BackendClient, sessionStore: CustomerSessionStore) {
        self.backend = backend
        self.sessionStore = sessionStore
    }

    /// Sends the request; on success the session ends.
    func requestDeletion() async {
        state = .sending
        do {
            _ = try await backend.requestAccountDeletion()
            state = .requested
            await sessionStore.discardSession()
        } catch BackendError.notConfigured {
            state = .byEmail
        } catch {
            state = UserFacingError(error).map(State.failed) ?? .idle
        }
    }
}

// MARK: - DeleteAccountScreen

/// "Konto löschen": what deletion means, a confirmation, and the request.
public struct DeleteAccountScreen: View {
    private let supportEmail: String

    @State private var model: DeleteAccountViewModel
    @State private var isConfirmationPresented = false

    @Environment(\.openURL) private var openURL

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - backend: Starts the erasure.
    ///   - sessionStore: Ends the session after the request.
    ///   - supportEmail: The address for the e-mail fallback.
    public init(
        backend: any BackendClient,
        sessionStore: CustomerSessionStore,
        supportEmail: String = RemoteAppConfig.fallback.supportEmail
    ) {
        _model = State(initialValue: DeleteAccountViewModel(backend: backend, sessionStore: sessionStore))
        self.supportEmail = supportEmail
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.l) {
                switch model.state {
                case .requested:
                    KXEmptyState(
                        systemImage: "checkmark.circle",
                        title: String(localized: "account.delete.done.title", bundle: .module),
                        message: String(localized: "account.delete.done.message", bundle: .module)
                    )
                    .accessibilityIdentifier("account.delete.done")
                case .byEmail:
                    emailFallback
                case .idle, .sending, .failed:
                    explanation
                }
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.deleteAccount")
        .kxScreenBackground()
        .navigationTitle(Text("account.delete.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            Text("account.delete.confirm.title", bundle: .module),
            isPresented: $isConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await model.requestDeletion() }
            } label: {
                Text("account.delete.confirm.action", bundle: .module)
            }
        } message: {
            Text("account.delete.confirm.message", bundle: .module)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            KXCard {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    Text("account.delete.intro", bundle: .module)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("account.delete.keys", bundle: .module)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("account.delete.retention", bundle: .module)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if case let .failed(error) = model.state {
                KXBanner(.error, message: error.message)
            }
            KXButton(
                String(localized: "account.delete.action", bundle: .module),
                systemImage: "trash",
                isFullWidth: true,
                isLoading: model.state == .sending
            ) {
                isConfirmationPresented = true
            }
            .accessibilityIdentifier("account.delete.request")
        }
    }

    private var emailFallback: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            KXCard {
                Text("account.delete.email.message \(supportEmail)", bundle: .module)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = mailtoURL {
                KXButton(
                    String(localized: "account.delete.email.action", bundle: .module),
                    systemImage: "envelope",
                    isFullWidth: true
                ) {
                    openURL(url)
                }
                .accessibilityIdentifier("account.delete.email")
            }
        }
    }

    private var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: String(localized: "account.delete.email.subject", bundle: .module))]
        return components.url
    }
}
