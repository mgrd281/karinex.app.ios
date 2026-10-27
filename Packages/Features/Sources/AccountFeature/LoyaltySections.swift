import BackendKit
import DesignSystem
import SwiftUI

// MARK: - LoyaltyPerksSection

/// The perks of the current level, in the customer's language; nothing when there are none.
struct LoyaltyPerksSection: View {
    let perks: [LoyaltyStatus.Perk]

    @Environment(\.locale) private var locale

    var body: some View {
        let code = locale.language.languageCode?.identifier ?? "de"
        let texts = perks.map { $0.text(languageCode: code) }.filter { !$0.isEmpty }
        if !texts.isEmpty {
            KXListGroup(Text("account.loyalty.perks.title", bundle: .module)) {
                ForEach(Array(texts.enumerated()), id: \.offset) { index, text in
                    if index > 0 {
                        KXListDivider()
                    }
                    KXListRow(systemImage: "sparkles", title: Text(verbatim: text))
                }
            }
        }
    }
}

// MARK: - LoyaltyDiscountSection

/// "Ihr Dauerrabatt": the permanent discount of the level and the next one, only while the
/// store has it switched on.
struct LoyaltyDiscountSection: View {
    let status: LoyaltyStatus

    var body: some View {
        if let discount = status.discount, discount.active {
            KXListGroup(Text("account.loyalty.discount.title", bundle: .module)) {
                if discount.percent > 0 {
                    KXListRow(
                        systemImage: "percent",
                        title: Text("account.loyalty.discount.current \(discount.percent)", bundle: .module),
                        detail: Text("account.loyalty.discount.current.detail", bundle: .module)
                    )
                } else {
                    KXListRow(systemImage: "percent", title: Text("account.loyalty.discount.none", bundle: .module))
                }
                if let next = discount.next {
                    KXListDivider()
                    KXListRow(
                        systemImage: "arrow.up.circle",
                        title: Text("account.loyalty.discount.next \(next.tier.name) \(next.percent)", bundle: .module)
                    )
                }
            } footer: {
                Text("account.loyalty.discount.footer \(status.earn.tierWindowMonths)", bundle: .module)
            }
            .accessibilityIdentifier("loyalty.discount")
        }
    }
}

// MARK: - LoyaltyReferralSection

/// "Freunde einladen": the friend saves on the first order with the customer's code, the
/// customer gets reward points. The code is created on the first tap (`onCreate`) and shared
/// with the system share sheet (message and the shop link that puts the code into the cart).
struct LoyaltyReferralSection: View {
    let status: LoyaltyStatus
    let format: LoyaltyFormat
    let isCreating: Bool
    let onCreate: () -> Void

    var body: some View {
        if let referral = status.referral, referral.active {
            KXListGroup(Text("account.loyalty.referral.title", bundle: .module)) {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    let points = format.points(referral.rewardPoints)
                    let euros = format.euro(cents: referral.rewardCents)
                    Text("account.loyalty.referral.body \(referral.friendPercent) \(points) \(euros)", bundle: .module)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let code = referral.code {
                        Text(verbatim: code)
                            .kxFont(.licenseKey)
                            .foregroundStyle(KXColor.keyCardText)
                            .frame(maxWidth: .infinity)
                            .padding(KXSpacing.m)
                            .background(KXColor.keyCardBackground, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("loyalty.referral.code")
                        if let link = referral.link {
                            ShareLink(
                                item: link,
                                subject: Text("account.loyalty.referral.share.subject", bundle: .module),
                                message: Text("account.loyalty.referral.share.message \(code) \(referral.friendPercent)", bundle: .module)
                            ) {
                                Label {
                                    Text("account.loyalty.referral.share", bundle: .module)
                                } icon: {
                                    Image(systemName: "square.and.arrow.up")
                                        .accessibilityHidden(true)
                                }
                            }
                            .buttonStyle(.kx(isFullWidth: true))
                            .accessibilityIdentifier("loyalty.referral.share")
                        }
                        KXButton(
                            String(localized: "account.loyalty.code.copy", bundle: .module),
                            systemImage: "doc.on.doc",
                            style: .secondary,
                            isFullWidth: true
                        ) {
                            KXClipboard.copySensitive(code)
                        }
                    } else {
                        KXButton(
                            String(localized: "account.loyalty.referral.create", bundle: .module),
                            systemImage: "person.badge.plus",
                            isFullWidth: true,
                            isLoading: isCreating
                        ) {
                            onCreate()
                        }
                        .accessibilityIdentifier("loyalty.referral.create")
                    }
                    if referral.rewarded > 0 || referral.pending > 0 {
                        Text("account.loyalty.referral.count \(referral.rewarded) \(referral.pending)", bundle: .module)
                            .kxFont(.subheadline)
                            .foregroundStyle(KXColor.textSecondary)
                    }
                }
                .padding(KXSpacing.m)
            } footer: {
                Text("account.loyalty.referral.footer \(referral.maxPerYear)", bundle: .module)
            }
            .accessibilityIdentifier("loyalty.referral")
        }
    }
}
