import BackendKit
import CommerceUI
import Core
import DesignSystem
import LocalAuthentication
import SwiftUI

// MARK: - LicenseVaultScreen

/// "Meine Lizenzen": certificate-style key cards with "Kopieren" (expiring, local-only
/// clipboard), "Anleitung" and "Support zu dieser Lizenz" (PROMPT.md 6.7).
///
/// - Keys come from the Keychain cache first and are refreshed from the backend.
/// - With the lock enabled in the settings, the vault opens only after Face ID, Touch ID or the
///   device code. Leaving the app hides every key and locks the vault again; the App also
///   covers the whole window in the app switcher.
public struct LicenseVaultScreen: View {
    private let locksVault: Bool
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: LicenseVaultViewModel
    @State private var isUnlocked = false
    @State private var isAuthenticating = false

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// Creates the vault.
    ///
    /// - Parameters:
    ///   - orderID: Limits the vault to one order (numeric order ID).
    ///   - backend: Delivers the keys.
    ///   - cache: The Keychain cache.
    ///   - locksVault: Whether Face ID, Touch ID or the device code is required.
    ///   - onRoute: Opens the support screen.
    public init(
        orderID: String?,
        backend: any BackendClient,
        cache: LicenseKeyCache,
        locksVault: Bool,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        _model = State(initialValue: LicenseVaultViewModel(orderID: orderID, backend: backend, cache: cache))
        self.locksVault = locksVault
        self.onRoute = onRoute
    }

    public var body: some View {
        Group {
            if locksVault, !isUnlocked {
                lockedView
            } else {
                vault
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.licenses")
        .kxScreenBackground()
        .navigationTitle(Text("licenses.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .task {
            if locksVault, !isUnlocked {
                await unlock()
            }
            if model.backendState == .idle {
                await model.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.hideAll()
                if locksVault {
                    isUnlocked = false
                }
            }
        }
    }

    // MARK: Lock

    private var lockedView: some View {
        ScrollView {
            KXEmptyState(
                systemImage: "lock",
                title: String(localized: "licenses.locked.title", bundle: .module),
                message: String(localized: "licenses.locked.message", bundle: .module),
                actionTitle: String(localized: "licenses.locked.unlock", bundle: .module),
                action: { Task { await unlock() } }
            )
            .accessibilityIdentifier("licenses.locked")
        }
    }

    /// Asks for Face ID, Touch ID or the device code. A device without any of them cannot lock,
    /// so the vault opens.
    private func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = true
            return
        }
        let reason = String(localized: "licenses.locked.reason", bundle: .module)
        isUnlocked = await (try? context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    // MARK: Vault

    private var vault: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.l) {
                notices
                if model.keys.isEmpty {
                    emptyState
                } else {
                    ForEach(model.keys) { key in
                        keyCard(key)
                    }
                }
                Text("licenses.footnote", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
        }
        .refreshable { await model.refresh() }
    }

    private func keyCard(_ key: LicenseKey) -> some View {
        let orderName = model.orderName(for: key)
        return KXKeyCard(
            productName: key.productTitle,
            licenseKey: key.key,
            isRevealed: Binding(
                get: { model.isRevealed(key) },
                set: { model.setRevealed($0, for: key) }
            ),
            subtitle: orderName.map { String(localized: "licenses.order \($0)", bundle: .module) },
            onShowGuide: guideAction(for: key),
            onContactSupport: { onRoute(.account(.support(orderName: orderName))) }
        )
        .accessibilityIdentifier("licenses.key")
    }

    private func guideAction(for key: LicenseKey) -> (@MainActor () -> Void)? {
        guard let url = key.activationGuideURL else { return nil }
        let openURL = openURL
        return { openURL(url) }
    }

    @ViewBuilder private var notices: some View {
        switch model.backendState {
        case .unavailable:
            KXBanner(.info, message: String(localized: "licenses.email.notice", bundle: .module))
                .accessibilityIdentifier("licenses.emailNotice")
        case let .failed(error):
            KXBanner(.error, message: error.message, actionTitle: UserFacingError.retryTitle, action: {
                Task { await model.refresh() }
            })
        case .refreshing where model.keys.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("licenses.loading", bundle: .module))
        case .idle, .refreshing, .available:
            EmptyView()
        }
        if !model.pendingOrders.isEmpty {
            KXBanner(
                .info,
                message: String(localized: "licenses.pending \(model.pendingOrders.joined(separator: ", "))", bundle: .module)
            )
            .accessibilityIdentifier("licenses.pending")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.backendState != .refreshing {
            KXEmptyState(
                systemImage: "key",
                title: String(localized: "licenses.empty.title", bundle: .module),
                message: String(localized: "licenses.empty.message", bundle: .module)
            )
            .accessibilityIdentifier("licenses.empty")
        }
    }
}

// MARK: - Previews

#Preview("LicenseVaultScreen, no backend") {
    NavigationStack {
        LicenseVaultScreen(
            orderID: nil,
            backend: UnavailableBackendClient(),
            cache: LicenseKeyCache(store: InMemorySecureStore()),
            locksVault: false,
            onRoute: { _ in }
        )
    }
}
