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
