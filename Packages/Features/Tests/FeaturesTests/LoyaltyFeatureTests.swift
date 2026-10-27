@testable import AccountFeature
import BackendKit
import CommerceUI
import Foundation
import Testing

// MARK: - Fixtures

private enum LoyaltyFixtures {
    static let steps = [
        LoyaltyStatus.RedeemStep(points: 1000, cents: 100, minSubtotalCents: 1000),
        LoyaltyStatus.RedeemStep(points: 3000, cents: 300, minSubtotalCents: 1500),
    ]

    static func status(available: Int = 1500, enabled: Bool = true, referral: LoyaltyStatus.Referral? = nil) -> LoyaltyStatus {
        LoyaltyStatus(
            enabled: enabled,
            tier: .init(
                tier: .gold,
                points: 1573,
                next: .init(tier: .platin, min: 2500, remaining: 927),
                progress: 0.63,
                maxReached: false
            ),
            perks: [.init(de: "Früher Zugang", en: "Early access")],
            reward: .init(available: available, pending: 0, expiringSoon: nil),
            redeem: .init(steps: steps, maxPercent: 20, minOrderCents: 1000, codeValidDays: 30),
            referral: referral,
            earn: .init(tierPerEuro: 10, rewardPerEuro: 10, holdDays: 7, tierWindowMonths: 12, rewardExpiryMonths: 12),
            history: []
        )
    }

    static let code = LoyaltyRedeemCode(
        code: "KX-ABCD-1234",
        cents: 100,
        minSubtotalCents: 1000,
        expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

/// Hands out `key-1`, `key-2`, ... so the tests can see which idempotency key a tap used.
private final class KeyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return "key-\(count)"
    }
}

// MARK: - View model

@Suite("Loyalty screen model")
@MainActor
struct LoyaltyViewModelTests {
    private func model(_ backend: StubBackend) -> LoyaltyViewModel {
        let counter = KeyCounter()
        return LoyaltyViewModel(backend: backend, makeKey: { counter.next() })
    }

    @Test("The Apple Wallet card is downloaded once; a failure shows the alert")
    func walletPass() async {
        let backend = StubBackend()
        let data = Data([0x50, 0x4B, 0x03, 0x04])
        await backend.setWalletPass(.success(data))
        let model = model(backend)

        #expect(await model.loadWalletPass() == data)
        #expect(!model.walletPassFailed)
        #expect(!model.isLoadingWalletPass)

        await backend.setWalletPass(.failure(.notFound))
        #expect(await model.loadWalletPass() == nil)
        #expect(model.walletPassFailed)
        #expect(await backend.calls == ["walletPass", "walletPass"])
    }

    @Test("The referral code is created once on a tap, only while the program runs, and the status reloads")
    func createReferral() async {
        let backend = StubBackend()
        let on = LoyaltyStatus.Referral(active: true, friendPercent: 10, rewardPoints: 5000, rewardCents: 500, maxPerYear: 20)
        await backend.setLoyalty(.success(LoyaltyFixtures.status(referral: on)))
        let code = LoyaltyReferralCode(code: "FREUND-AB23CD", link: URL(string: "https://www.karinex.de/discount/FREUND-AB23CD"), friendPercent: 10, rewardPoints: 5000)
        await backend.setReferral(.success(code))
        let model = model(backend)
        await model.load()

        await model.createReferral()
        #expect(!model.referralFailed)
        #expect(!model.isCreatingReferral)
        #expect(await backend.calls == ["loyalty", "referral", "loyalty"])

        await backend.setReferral(.failure(LoyaltyReferralError.disabled))
        await model.createReferral()
        #expect(model.referralFailed)

        let off = LoyaltyStatus.Referral(active: false, friendPercent: 10, rewardPoints: 5000, rewardCents: 500, maxPerYear: 20)
        await backend.setLoyalty(.success(LoyaltyFixtures.status(referral: off)))
        await model.load()
        let before = await backend.calls.count
        await model.createReferral()
        #expect(await backend.calls.count == before, "switched off: no request")
    }

    @Test("The status is loaded from the backend")
    func load() async {
        let backend = StubBackend()
        await backend.setLoyalty(.success(LoyaltyFixtures.status()))
        let model = model(backend)

        await model.load()

        #expect(model.state.value?.tier.tier == .gold)
        #expect(await backend.calls == ["loyalty"])
    }

    @Test("Only steps the points cover can be redeemed, and only while the program is on")
    func canRedeem() async {
        let backend = StubBackend()
        await backend.setLoyalty(.success(LoyaltyFixtures.status(available: 1500)))
        let model = model(backend)
        await model.load()

        #expect(model.canRedeem(LoyaltyFixtures.steps[0]))
        #expect(!model.canRedeem(LoyaltyFixtures.steps[1]))

        await backend.setLoyalty(.success(LoyaltyFixtures.status(available: 5000, enabled: false)))
        await model.load()

        #expect(!model.canRedeem(LoyaltyFixtures.steps[0]))
    }

    @Test("A redemption shows the code and reloads the balance")
    func redeem() async {
        let backend = StubBackend()
        await backend.setLoyalty(.success(LoyaltyFixtures.status()))
        await backend.setRedeem(.success(LoyaltyFixtures.code))
        let model = model(backend)
        await model.load()

        await model.redeem(LoyaltyFixtures.steps[0])

        #expect(model.outcome == .code(LoyaltyFixtures.code))
        #expect(model.redeeming == nil)
        #expect(await backend.calls == ["loyalty", "redeem:1000:key-1", "loyalty"])
    }

    @Test("A step the points do not cover never reaches the backend")
    func tooFewPoints() async {
        let backend = StubBackend()
        await backend.setLoyalty(.success(LoyaltyFixtures.status(available: 500)))
        let model = model(backend)
        await model.load()

        await model.redeem(LoyaltyFixtures.steps[0])

        #expect(model.outcome == nil)
        #expect(await backend.calls == ["loyalty"])
    }

    @Test("After a failure the next tap reuses the key, so the points are never spent twice")
    func retryKeepsKey() async {
        let backend = StubBackend()
        await backend.setLoyalty(.success(LoyaltyFixtures.status()))
        await backend.setRedeem(.failure(BackendError.server(statusCode: 503, code: nil, requestID: nil)))
        let model = model(backend)
        await model.load()

        await model.redeem(LoyaltyFixtures.steps[0])
        guard case .failed = model.outcome else {
            Issue.record("Expected a failure, got \(String(describing: model.outcome))")
            return
        }
        model.dismissOutcome()
        await backend.setRedeem(.success(LoyaltyFixtures.code))
        await model.redeem(LoyaltyFixtures.steps[0])

        #expect(model.outcome == .code(LoyaltyFixtures.code))
        let redeemCalls = await backend.calls.filter { $0.hasPrefix("redeem:") }
        #expect(redeemCalls == ["redeem:1000:key-1", "redeem:1000:key-1"])
    }

    @Test("After the code arrived the next redemption gets a new key")
    func newKeyAfterSuccess() async {
        let backend = StubBackend()
        await backend.setLoyalty(.success(LoyaltyFixtures.status(available: 5000)))
        await backend.setRedeem(.success(LoyaltyFixtures.code))
        let model = model(backend)
        await model.load()

        await model.redeem(LoyaltyFixtures.steps[0])
        model.dismissOutcome()
        await model.redeem(LoyaltyFixtures.steps[0])

        let redeemCalls = await backend.calls.filter { $0.hasPrefix("redeem:") }
        #expect(redeemCalls == ["redeem:1000:key-1", "redeem:1000:key-2"])
    }

    @Test("A refusal is shown as such and ends the attempt")
    func refusal() async {
        let backend = StubBackend()
        await backend.setLoyalty(.success(LoyaltyFixtures.status()))
        await backend.setRedeem(.failure(LoyaltyRedeemError.insufficient))
        let model = model(backend)
        await model.load()

        await model.redeem(LoyaltyFixtures.steps[0])
        #expect(model.outcome == .refused(.insufficient))

        model.dismissOutcome()
        await backend.setRedeem(.success(LoyaltyFixtures.code))
        await model.redeem(LoyaltyFixtures.steps[0])

        let redeemCalls = await backend.calls.filter { $0.hasPrefix("redeem:") }
        #expect(redeemCalls == ["redeem:1000:key-1", "redeem:1000:key-2"])
    }

    @Test("A request that is still running keeps its key")
    func inProgressKeepsKey() async {
        let backend = StubBackend()
        await backend.setLoyalty(.success(LoyaltyFixtures.status()))
        await backend.setRedeem(.failure(LoyaltyRedeemError.inProgress))
        let model = model(backend)
        await model.load()

        await model.redeem(LoyaltyFixtures.steps[0])
        model.dismissOutcome()
        await model.redeem(LoyaltyFixtures.steps[0])

        let redeemCalls = await backend.calls.filter { $0.hasPrefix("redeem:") }
        #expect(redeemCalls == ["redeem:1000:key-1", "redeem:1000:key-1"])
    }
}

// MARK: - Presentation

@Suite("Loyalty presentation")
struct LoyaltyPresentationTests {
    @Test("Every level has a card style of the same name")
    func styles() {
        for tier in LoyaltyTier.allCases {
            #expect(tier.style.rawValue == tier.rawValue)
        }
    }

    @Test("Numbers and euros follow the customer's language")
    func formatting() {
        let german = LoyaltyFormat(locale: Locale(identifier: "de_DE"))
        let english = LoyaltyFormat(locale: Locale(identifier: "en_GB"))

        #expect(german.points(1573) == "1.573")
        #expect(english.points(1573) == "1,573")
        #expect(german.signedPoints(399) == "+399")
        #expect(german.euro(cents: 300).contains("3,00"))
    }
}

// MARK: - Strings

@Suite("Loyalty strings")
struct LoyaltyStringTests {
    @Test("Every loyalty text resolves without dashes", arguments: appLanguages)
    func allTexts(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: AccountResources.bundle)
        let keys = [
            "account.menu.loyalty",
            "account.menu.loyalty.subtitle",
            "account.gate.loyalty.message",
            "account.loyalty.title",
            "account.loyalty.tier.starter",
            "account.loyalty.tier.silber",
            "account.loyalty.tier.gold",
            "account.loyalty.tier.platin",
            "account.loyalty.tier.diamant",
            "account.loyalty.tier.elite",
            "account.loyalty.discount.title",
            "account.loyalty.discount.current.detail",
            "account.loyalty.discount.none",
            "account.loyalty.referral.title",
            "account.loyalty.referral.create",
            "account.loyalty.referral.share",
            "account.loyalty.referral.share.subject",
            "account.loyalty.referral.error.title",
            "account.loyalty.referral.error.message",
            "account.loyalty.history.referral",
            "account.loyalty.message.max",
            "account.loyalty.action.collect",
            "account.loyalty.action.rewards",
            "account.loyalty.action.history",
            "account.loyalty.balance.title",
            "account.loyalty.rewards.title",
            "account.loyalty.history.title",
            "account.loyalty.history.empty",
            "account.loyalty.confirm.action",
            "account.loyalty.code.title",
            "account.loyalty.code.apply",
            "account.loyalty.error.title",
            "account.loyalty.collect.title",
        ]

        for key in keys {
            let text = strings(key)
            #expect(text != key, "\(key) has no \(language) value")
            #expect(!containsForbiddenDash(text), "Dash in \(key)")
        }
    }
}
