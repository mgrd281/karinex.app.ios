import BackendKit
import CommerceUI
import DesignSystem
import SwiftUI

// MARK: - ReferralScreen

/// "Freunde einladen": its own screen in the Konto tab, apart from the Treueprogramm. The
/// customer creates a personal code once, copies or shares it, and sees how the invitation works.
/// Everything shown comes from the backend (`referral` in `GET /v1/app/loyalty`); the app
/// calculates nothing. While the store has the referral program switched off, the screen says so.
public struct ReferralScreen: View {
    @State private var model: LoyaltyViewModel

    @Environment(\.locale) private var locale

    /// Creates the screen.
    ///
    /// - Parameter backend: The backend client.
    public init(backend: any BackendClient) {
        _model = State(initialValue: LoyaltyViewModel(backend: backend))
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            retry: { await model.load() },
            content: { status in
                content(status)
            }
        )
        .accessibilityIdentifier("screen.referral")
        .kxScreenBackground()
        .navigationTitle(Text("account.loyalty.referral.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
        .alert(
            Text("account.loyalty.referral.error.title", bundle: .module),
            isPresented: $model.referralFailed
        ) {
            Button(role: .cancel) {} label: {
                Text("account.signin.error.close", bundle: .module)
            }
        } message: {
            Text("account.loyalty.referral.error.message", bundle: .module)
        }
    }

    // MARK: Content

    private func content(_ status: LoyaltyStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                if status.referral?.active == true {
                    LoyaltyReferralSection(
                        status: status,
                        format: LoyaltyFormat(locale: locale),
                        isCreating: model.isCreatingReferral
                    ) {
                        Task { await model.createReferral() }
                    }
                } else {
                    Label {
                        Text("account.referral.unavailable", bundle: .module)
                    } icon: {
                        Image(systemName: "pause.circle")
                            .accessibilityHidden(true)
                    }
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textSecondary)
                    .accessibilityIdentifier("referral.unavailable")
                }
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
            .kxReadableWidth()
        }
        .refreshable { await model.load() }
    }
}
