@testable import BackendKit
import Core
import Foundation
import Testing

private final class QueueHTTPClient: HTTPClient {
    private let state: Locked<(requests: [HTTPRequest], replies: [HTTPResponse])>

    init(_ replies: [HTTPResponse]) {
        state = Locked(([], replies))
    }

    var requests: [HTTPRequest] {
        state.value.requests
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let reply = state.withLock { state -> HTTPResponse? in
            state.requests.append(request)
            return state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        guard let reply else { throw NetworkError.invalidResponse }
        return reply
    }
}

private struct ImmediateSleeper: Sleeper {
    func sleep(for _: Duration) async throws {}
}

private func reply(_ body: String, status: Int = 200) -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: [:], body: Data(body.utf8))
}

private func makeClient(_ http: QueueHTTPClient) -> HTTPBackendClient {
    HTTPBackendClient(
        baseURL: URL(string: "https://app-api.karinex.de")!,
        httpClient: http,
        accessToken: { "shcat_token" },
        appVersion: "0.2.0",
        languageCode: { "de" },
        sleeper: ImmediateSleeper(),
        logger: KXLogger(category: .networking, sink: RecordingLogSink())
    )
}

private let statusJSON = """
    {"enabled": true,
     "tier": {"id": "gold", "points": 1573, "pending": 399,
              "next": {"tier": "platin", "min": 2500, "remaining": 927}, "progress": 0.6292, "maxReached": false},
     "perks": [{"de": "Früher Zugang zu Aktionen", "en": "Early access to sales"}],
     "reward": {"available": 1573, "pending": 399, "expiringSoon": {"points": 200, "at": "2026-11-20T10:00:00.000Z"}},
     "redeem": {"steps": [{"points": 1000, "cents": 100, "minSubtotalCents": 1000},
                          {"points": 3000, "cents": 300, "minSubtotalCents": 1500}],
                "maxPercent": 20, "minOrderCents": 1000, "codeValidDays": 14},
     "earn": {"tierPerEuro": 10, "rewardPerEuro": 10, "holdDays": 7, "tierWindowMonths": 12, "rewardExpiryMonths": 12},
     "history": [
       {"id": "a", "type": "EARN", "status": "PENDING", "tierPoints": 399, "rewardPoints": 399,
        "orderNumber": "#5101", "at": "2026-10-25T09:00:00.000Z"},
       {"id": "b", "type": "REDEEM", "status": "CONFIRMED", "tierPoints": 0, "rewardPoints": -1000,
        "orderNumber": null, "at": "2026-10-20T09:00:00.000Z"},
       {"id": "c", "type": "SOMETHING_NEW", "status": "CONFIRMED", "tierPoints": 0, "rewardPoints": 5, "at": "2026-10-19T09:00:00Z"}]}
    """

@Suite("Loyalty")
struct LoyaltyTests {
    @Test("The Apple Wallet card comes back as pass data; anything else is rejected")
    func walletPass() async throws {
        let pass = Data([0x50, 0x4B, 0x03, 0x04, 0x01, 0x02])
        let http = QueueHTTPClient([
            HTTPResponse(statusCode: 200, headers: [:], body: pass),
            reply("<html>no</html>"),
            reply(#"{"code":"not_found","message":"x","requestId":"r"}"#, status: 404),
        ])
        let client = makeClient(http)
        #expect(try await client.walletPass() == pass)
        #expect(http.requests.first?.url.path == "/v1/app/wallet-card")
        #expect(http.requests.first?.headers["Accept"] == "application/vnd.apple.pkpass")
        #expect(http.requests.first?.headers["Authorization"] == "Bearer shcat_token")
        await #expect(throws: BackendError.decoding) { try await client.walletPass() }
        await #expect(throws: BackendError.notFound) { try await client.walletPass() }
    }

    @Test("The status decodes: level, ring, rewards, rules and history")
    func status() async throws {
        let http = QueueHTTPClient([reply(statusJSON)])
        let status = try await makeClient(http).loyalty()
        #expect(http.requests.first?.url.path == "/v1/app/loyalty")
        #expect(http.requests.first?.headers["Authorization"] == "Bearer shcat_token")
        #expect(status.enabled)
        #expect(status.tier.tier == .gold)
        #expect(status.tier.points == 1573)
        #expect(status.tier.next == .init(tier: .platin, min: 2500, remaining: 927))
        #expect(abs(status.tier.progress - 0.6292) < 0.0001)
        #expect(status.reward.available == 1573)
        #expect(status.reward.expiringSoon?.points == 200)
        #expect(status.redeem.steps.map(\.cents) == [100, 300])
        #expect(status.redeem.steps[1].minSubtotalCents == 1500)
        #expect(status.redeem.codeValidDays == 14)
        #expect(status.earn == .init(tierPerEuro: 10, rewardPerEuro: 10, holdDays: 7, tierWindowMonths: 12, rewardExpiryMonths: 12))
        #expect(status.history.map(\.kind) == [.earn, .redeem, .other])
        #expect(status.history[0].isPending)
        #expect(status.history[1].rewardPoints == -1000)
        #expect(status.perks[0].text(languageCode: "de") == "Früher Zugang zu Aktionen")
        #expect(status.perks[0].text(languageCode: "fr") == "Early access to sales")
    }

    @Test("A backend without permanent discounts decodes; the discount is nil")
    func noDiscount() async throws {
        let status = try await makeClient(QueueHTTPClient([reply(statusJSON)])).loyalty()
        #expect(status.discount == nil)
    }

    @Test("The permanent discount decodes with the next level and all levels")
    func discount() throws {
        let json = #"""
            {"active": true, "percent": 5, "next": {"tier": "platin", "percent": 8},
             "ladder": [{"tier": "silber", "min": 1000, "percent": 3}, {"tier": "elite", "min": 25000, "percent": 15},
                        {"tier": "someday", "min": 99000, "percent": 20}]}
            """#
        let discount = try JSONDecoder().decode(LoyaltyStatus.Discount.self, from: Data(json.utf8))
        #expect(discount.applies)
        #expect(discount.percent == 5)
        #expect(discount.next == .init(tier: .platin, percent: 8))
        #expect(discount.ladder.map(\.tier) == [.silber, .elite, .starter])
        let off = try JSONDecoder().decode(LoyaltyStatus.Discount.self, from: Data(#"{"active": false}"#.utf8))
        #expect(!off.applies)
        #expect(off.ladder.isEmpty)
    }

    @Test("A next level unknown to this app does not break the status")
    func unknownNextLevel() throws {
        let json = #"{"id": "gold", "points": 12, "next": {"tier": "legend", "min": 90000, "remaining": 1}, "progress": 0.1}"#
        let level = try JSONDecoder().decode(LoyaltyStatus.Level.self, from: Data(json.utf8))
        #expect(level.next?.tier == .starter)
    }

    @Test("An unknown level shows as starter and the ring stays within 0 to 1")
    func unknownLevel() throws {
        let json = #"{"id": "legend", "points": 12, "progress": 7.5}"#
        let level = try JSONDecoder().decode(LoyaltyStatus.Level.self, from: Data(json.utf8))
        #expect(level.tier == .starter)
        #expect(level.progress == 1)
        #expect(level.next == nil)
    }

    @Test("Redeeming posts the points and the key, and returns the code")
    func redeem() async throws {
        let http =
            QueueHTTPClient(
                [reply(#"{"code": "KXABCDEFGH23", "cents": 300, "minSubtotalCents": 1500, "expiresAt": "2026-11-10T10:00:00.000Z"}"#)]
            )
        let code = try await makeClient(http).redeemLoyalty(points: 3000, idempotencyKey: "key-12345678")
        let request = try #require(http.requests.first)
        #expect(request.method == .post)
        #expect(request.url.path == "/v1/app/loyalty/redeem")
        let body = try JSONSerialization.jsonObject(with: #require(request.body)) as? [String: Any]
        #expect(body?["points"] as? Int == 3000)
        #expect(body?["idempotencyKey"] as? String == "key-12345678")
        #expect(code.code == "KXABCDEFGH23")
        #expect(code.cents == 300)
        #expect(code.minSubtotalCents == 1500)
    }

    @Test("A refused redemption throws the reason, never a generic error")
    func refused() async throws {
        for (reason, expected) in [
            ("insufficient", LoyaltyRedeemError.insufficient),
            ("disabled", .disabled),
            ("in_progress", .inProgress),
            ("neu", .rejected),
        ] {
            let http = QueueHTTPClient([
                reply(#"{"code": "redeem_rejected", "reason": "\#(reason)", "message": "x", "requestId": "r"}"#, status: 409),
            ])
            await #expect(throws: expected) {
                try await makeClient(http).redeemLoyalty(points: 1000, idempotencyKey: "key-12345678")
            }
        }
    }

    @Test("A redemption is never repeated after a server error")
    func notRepeated() async throws {
        let http = QueueHTTPClient([
            reply(#"{"code": "upstream_unavailable", "message": "x", "requestId": "r"}"#, status: 503),
            reply("{}"),
        ])
        await #expect(throws: BackendError.self) {
            try await makeClient(http).redeemLoyalty(points: 1000, idempotencyKey: "key-12345678")
        }
        #expect(http.requests.count == 1)
    }

    @Test("Dates with and without fractional seconds parse")
    func dates() {
        #expect(LoyaltyDate.parse("2026-10-25T09:00:00.123Z") != nil)
        #expect(LoyaltyDate.parse("2026-10-25T09:00:00Z") != nil)
        #expect(LoyaltyDate.parse("gestern") == nil)
    }
}
