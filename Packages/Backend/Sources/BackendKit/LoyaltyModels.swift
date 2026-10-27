import Foundation

// MARK: - LoyaltyTier

/// The membership levels of the loyalty program. The backend decides the level; the app only
/// shows it. An unknown level from a newer backend is shown as `starter`.
public enum LoyaltyTier: String, Sendable, Hashable, Codable, CaseIterable {
    case starter
    case silber
    case gold
    case platin
}

// MARK: - LoyaltyStatus

/// `GET /v1/app/loyalty`: the customer's standing in the loyalty program. Every number is
/// computed by the backend (docs/BFF_CONTRACT.md); the app never calculates points.
public struct LoyaltyStatus: Sendable, Hashable, Decodable {
    /// The level and the progress toward the next one.
    public struct Level: Sendable, Hashable, Decodable {
        /// The next level and what is missing for it.
        public struct Next: Sendable, Hashable, Decodable {
            public let tier: LoyaltyTier
            /// Status points needed for that level.
            public let min: Int
            /// Status points still missing.
            public let remaining: Int

            public init(tier: LoyaltyTier, min: Int, remaining: Int) {
                self.tier = tier
                self.min = min
                self.remaining = remaining
            }
        }

        public let tier: LoyaltyTier
        /// Confirmed status points in the current period.
        public let points: Int
        /// Status points of recent orders that are not confirmed yet.
        public let pending: Int
        public let next: Next?
        /// 0...1 for the ring: points divided by the next level's threshold, 1 at the top level.
        public let progress: Double
        /// Whether the top level is reached.
        public let maxReached: Bool

        private enum CodingKeys: String, CodingKey {
            case id, points, pending, next, progress, maxReached
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tier = try LoyaltyTier(rawValue: container.decode(String.self, forKey: .id)) ?? .starter
            points = try max(0, container.decode(Int.self, forKey: .points))
            pending = try max(0, container.decodeIfPresent(Int.self, forKey: .pending) ?? 0)
            next = try container.decodeIfPresent(Next.self, forKey: .next)
            let rawProgress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0
            progress = min(1, max(0, rawProgress.isFinite ? rawProgress : 0))
            maxReached = try container.decodeIfPresent(Bool.self, forKey: .maxReached) ?? false
        }

        /// Creates a level (tests and previews).
        public init(tier: LoyaltyTier, points: Int, pending: Int = 0, next: Next?, progress: Double, maxReached: Bool) {
            self.tier = tier
            self.points = points
            self.pending = pending
            self.next = next
            self.progress = progress
            self.maxReached = maxReached
        }
    }

    /// The reward points.
    public struct Reward: Sendable, Hashable, Decodable {
        /// Reward points the customer can redeem now.
        public let available: Int
        /// Reward points of recent orders that are not confirmed yet.
        public let pending: Int
        /// Reward points that expire soon.
        public let expiringSoon: Expiring?

        public struct Expiring: Sendable, Hashable, Decodable {
            public let points: Int
            public let at: Date

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: LoyaltyExpiringKeys.self)
                points = try container.decode(Int.self, forKey: .points)
                at = try LoyaltyDate.decode(container, forKey: .at)
            }

            public init(points: Int, at: Date) {
                self.points = points
                self.at = at
            }
        }

        public init(available: Int, pending: Int, expiringSoon: Expiring?) {
            self.available = available
            self.pending = pending
            self.expiringSoon = expiringSoon
        }
    }

    /// A perk of the current level, in German and English.
    public struct Perk: Sendable, Hashable, Decodable {
        public let de: String
        public let en: String

        public init(de: String, en: String) {
            self.de = de
            self.en = en
        }

        /// The text for `languageCode`: German for `de`, English otherwise, the other when one is empty.
        public func text(languageCode: String) -> String {
            let preferred = languageCode == "de" ? de : en
            return preferred.isEmpty ? (languageCode == "de" ? en : de) : preferred
        }
    }

    /// One way to redeem points.
    public struct RedeemStep: Sendable, Hashable, Decodable, Identifiable {
        public let points: Int
        /// The discount in cents.
        public let cents: Int
        /// The smallest value of goods in the cart for this discount, in cents.
        public let minSubtotalCents: Int

        public var id: Int {
            points
        }

        public init(points: Int, cents: Int, minSubtotalCents: Int) {
            self.points = points
            self.cents = cents
            self.minSubtotalCents = minSubtotalCents
        }
    }

    /// The rules shown before redeeming.
    public struct Redeem: Sendable, Hashable, Decodable {
        public let steps: [RedeemStep]
        /// The largest share of the goods a discount may cover, in percent.
        public let maxPercent: Int
        /// The smallest value of goods in the cart, in cents.
        public let minOrderCents: Int
        /// How many days a discount code stays valid.
        public let codeValidDays: Int

        public init(steps: [RedeemStep], maxPercent: Int, minOrderCents: Int, codeValidDays: Int) {
            self.steps = steps
            self.maxPercent = maxPercent
            self.minOrderCents = minOrderCents
            self.codeValidDays = codeValidDays
        }
    }

    /// How points are collected, so the app can explain it without hardcoding a number.
    public struct Earn: Sendable, Hashable, Decodable {
        /// Status points per full euro of goods.
        public let tierPerEuro: Int
        /// Reward points per full euro of goods.
        public let rewardPerEuro: Int
        /// Days after delivery until points of an order count.
        public let holdDays: Int
        /// Months that status points count toward the level.
        public let tierWindowMonths: Int
        /// Months until reward points expire.
        public let rewardExpiryMonths: Int

        public init(tierPerEuro: Int, rewardPerEuro: Int, holdDays: Int, tierWindowMonths: Int, rewardExpiryMonths: Int) {
            self.tierPerEuro = tierPerEuro
            self.rewardPerEuro = rewardPerEuro
            self.holdDays = holdDays
            self.tierWindowMonths = tierWindowMonths
            self.rewardExpiryMonths = rewardExpiryMonths
        }
    }

    /// What a history line records.
    public enum HistoryKind: String, Sendable, Hashable {
        case earn = "EARN"
        case refund = "REFUND"
        case redeem = "REDEEM"
        case release = "RELEASE"
        case adjust = "ADJUST"
        case expire = "EXPIRE"
        /// A kind a newer backend added.
        case other
    }

    /// One line of the history: both kinds of points of one event.
    public struct HistoryItem: Sendable, Hashable, Decodable, Identifiable {
        public let id: String
        public let kind: HistoryKind
        /// Whether the points are still pending.
        public let isPending: Bool
        public let statusPoints: Int
        public let rewardPoints: Int
        public let orderNumber: String?
        public let date: Date

        private enum CodingKeys: String, CodingKey {
            case id, type, status, tierPoints, rewardPoints, orderNumber, at
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            kind = try HistoryKind(rawValue: container.decode(String.self, forKey: .type)) ?? .other
            isPending = try container.decodeIfPresent(String.self, forKey: .status) == "PENDING"
            statusPoints = try container.decodeIfPresent(Int.self, forKey: .tierPoints) ?? 0
            rewardPoints = try container.decodeIfPresent(Int.self, forKey: .rewardPoints) ?? 0
            orderNumber = try container.decodeIfPresent(String.self, forKey: .orderNumber)
            date = try LoyaltyDate.decode(container, forKey: .at)
        }

        public init(
            id: String,
            kind: HistoryKind,
            isPending: Bool = false,
            statusPoints: Int,
            rewardPoints: Int,
            orderNumber: String? = nil,
            date: Date
        ) {
            self.id = id
            self.kind = kind
            self.isPending = isPending
            self.statusPoints = statusPoints
            self.rewardPoints = rewardPoints
            self.orderNumber = orderNumber
            self.date = date
        }
    }

    /// Whether the program is switched on.
    public let enabled: Bool
    public let tier: Level
    public let perks: [Perk]
    public let reward: Reward
    public let redeem: Redeem
    public let earn: Earn
    public let history: [HistoryItem]

    public init(enabled: Bool, tier: Level, perks: [Perk], reward: Reward, redeem: Redeem, earn: Earn, history: [HistoryItem]) {
        self.enabled = enabled
        self.tier = tier
        self.perks = perks
        self.reward = reward
        self.redeem = redeem
        self.earn = earn
        self.history = history
    }
}

// MARK: - LoyaltyRedeemCode

/// `POST /v1/app/loyalty/redeem`: the discount code a redemption produced.
public struct LoyaltyRedeemCode: Sendable, Hashable, Decodable, Identifiable {
    public var id: String {
        code
    }

    public let code: String
    /// The discount in cents.
    public let cents: Int
    /// The smallest value of goods in the cart, in cents.
    public let minSubtotalCents: Int
    public let expiresAt: Date

    private enum CodingKeys: String, CodingKey {
        case code, cents, minSubtotalCents, expiresAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        cents = try container.decode(Int.self, forKey: .cents)
        minSubtotalCents = try container.decode(Int.self, forKey: .minSubtotalCents)
        expiresAt = try LoyaltyDate.decode(container, forKey: .expiresAt)
    }

    public init(code: String, cents: Int, minSubtotalCents: Int, expiresAt: Date) {
        self.code = code
        self.cents = cents
        self.minSubtotalCents = minSubtotalCents
        self.expiresAt = expiresAt
    }
}

// MARK: - LoyaltyRedeemError

/// Why the backend refused a redemption (HTTP 409); the points were not spent.
public enum LoyaltyRedeemError: Error, Sendable, Hashable {
    /// The program is switched off.
    case disabled
    /// Not enough reward points.
    case insufficient
    /// The same request is still being processed.
    case inProgress
    /// Another reason a newer backend reports.
    case rejected

    init(reason: String?) {
        switch reason {
        case "disabled": self = .disabled
        case "insufficient": self = .insufficient
        case "in_progress": self = .inProgress
        default: self = .rejected
        }
    }
}

// MARK: - LoyaltyExpiringKeys

/// The keys of ``LoyaltyStatus/Reward/Expiring`` (kept at file level, SwiftLint nesting).
private enum LoyaltyExpiringKeys: String, CodingKey {
    case points, at
}

// MARK: - LoyaltyDate

enum LoyaltyDate {
    /// ISO 8601 with or without fractional seconds (the backend sends milliseconds).
    static func decode<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> Date {
        let text = try container.decode(String.self, forKey: key)
        if let date = parse(text) {
            return date
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not an ISO 8601 date.")
    }

    static func parse(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
