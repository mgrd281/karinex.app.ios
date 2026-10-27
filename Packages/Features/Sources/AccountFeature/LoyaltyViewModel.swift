import BackendKit
import CommerceUI
import Foundation
import Observation

// MARK: - LoyaltyViewModel

/// The loyalty screen: loads the status from the backend and redeems reward points.
///
/// The backend computes every number; this model only keeps what it sent. A redemption uses one
/// idempotency key per attempt: after a failure that may or may not have reached the backend
/// (network, server error) the next tap reuses the key, so the backend returns the same code and
/// never spends the points twice. A clear answer (code, refusal) ends the attempt.
@MainActor
@Observable
final class LoyaltyViewModel {
    /// What a redemption ended in.
    enum Outcome: Equatable {
        /// The code was issued.
        case code(LoyaltyRedeemCode)
        /// The backend refused; the points were not spent.
        case refused(LoyaltyRedeemError)
        /// The request failed; the points are safe and the tap can be repeated.
        case failed(UserFacingError)
    }

    /// The status.
    private(set) var state: LoadState<LoyaltyStatus> = .idle
    /// The points of the redemption that is running.
    private(set) var redeeming: Int?
    /// The result of the last redemption, shown until dismissed.
    var outcome: Outcome?
    /// Whether the Apple Wallet card is being downloaded.
    private(set) var isLoadingWalletPass = false
    /// Whether the last attempt to get the Apple Wallet card failed; shown until dismissed.
    var walletPassFailed = false

    @ObservationIgnored private let backend: any BackendClient
    @ObservationIgnored private let makeKey: @Sendable () -> String
    @ObservationIgnored private var attempt: (points: Int, key: String)?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - backend: The backend client.
    ///   - makeKey: Creates an idempotency key (8 to 64 letters, digits, `-` or `_`).
    init(backend: any BackendClient, makeKey: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.backend = backend
        self.makeKey = makeKey
    }

    /// Loads the status.
    func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            state = try await .loaded(backend.loyalty())
        } catch BackendError.notConfigured {
            state = .failed(UserFacingError(kind: .server))
        } catch {
            if let failure = UserFacingError(error), state.value == nil {
                state = .failed(failure)
            }
        }
    }

    /// Whether the customer has enough reward points for `step`.
    func canRedeem(_ step: LoyaltyStatus.RedeemStep) -> Bool {
        guard let status = state.value else { return false }
        return status.enabled && status.reward.available >= step.points
    }

    /// Redeems `step` and shows the code.
    func redeem(_ step: LoyaltyStatus.RedeemStep) async {
        guard redeeming == nil, canRedeem(step) else { return }
        let key: String
        if let attempt, attempt.points == step.points {
            key = attempt.key
        } else {
            key = makeKey()
            attempt = (step.points, key)
        }
        redeeming = step.points
        defer { redeeming = nil }
        do {
            let code = try await backend.redeemLoyalty(points: step.points, idempotencyKey: key)
            attempt = nil
            outcome = .code(code)
            await load()
        } catch let refusal as LoyaltyRedeemError {
            if refusal != .inProgress {
                attempt = nil
            }
            outcome = .refused(refusal)
            await load()
        } catch {
            outcome = .failed(UserFacingError(error) ?? UserFacingError(kind: .unknown))
        }
    }

    /// Downloads the customer's KARINEX card for Apple Wallet. Returns the `.pkpass` data, or `nil`
    /// when it is already loading, was cancelled or failed (then `walletPassFailed` is set).
    func loadWalletPass() async -> Data? {
        guard !isLoadingWalletPass else { return nil }
        isLoadingWalletPass = true
        defer { isLoadingWalletPass = false }
        do {
            return try await backend.walletPass()
        } catch {
            if UserFacingError(error) != nil {
                walletPassFailed = true
            }
            return nil
        }
    }

    /// Clears the result after it was shown.
    func dismissOutcome() {
        outcome = nil
    }
}
