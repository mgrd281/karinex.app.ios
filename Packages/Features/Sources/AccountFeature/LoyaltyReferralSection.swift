import BackendKit
import DesignSystem
import SwiftUI

// MARK: - LoyaltyReferralSection

/// The content of "Freunde einladen": a dark invitation card with both benefits side by side (the friend's
/// discount, the customer's reward), the customer's code as a ticket that copies on a tap and
/// the share button, then three short steps. The code is created on the first tap
/// (`onCreate`) and shared with the system share sheet (message and the shop link that puts
/// the code into the cart).
struct LoyaltyReferralSection: View {
    let status: LoyaltyStatus
    let format: LoyaltyFormat
    let isCreating: Bool
    let onCreate: () -> Void

    var body: some View {
        if let referral = status.referral, referral.active {
            VStack(alignment: .leading, spacing: KXSpacing.l) {
                ReferralInviteCard(referral: referral, format: format, isCreating: isCreating, onCreate: onCreate)
                steps(referral)
            }
            .accessibilityIdentifier("loyalty.referral")
        }
    }

    private func steps(_ referral: LoyaltyStatus.Referral) -> some View {
        KXListGroup(Text("account.loyalty.referral.steps.title", bundle: .module)) {
            KXListRow(systemImage: "square.and.arrow.up", title: Text("account.loyalty.referral.step.share", bundle: .module))
            KXListDivider()
            KXListRow(
                systemImage: "bag",
                title: Text("account.loyalty.referral.step.order \(referral.friendPercent)", bundle: .module)
            )
            KXListDivider()
            KXListRow(
                systemImage: "gift",
                title: Text("account.loyalty.referral.step.reward \(format.points(referral.rewardPoints))", bundle: .module)
            )
        } footer: {
            Text("account.loyalty.referral.limit \(referral.maxPerYear)", bundle: .module)
        }
        .accessibilityIdentifier("loyalty.referral.steps")
    }
}

// MARK: - ReferralInviteCard

/// The dark card of "Freunde einladen" in the colors of the license key card.
private struct ReferralInviteCard: View {
    let referral: LoyaltyStatus.Referral
    let format: LoyaltyFormat
    let isCreating: Bool
    let onCreate: () -> Void

    /// Shows "Kopiert" for a moment after the code was copied.
    @State private var didCopy = false

    @ScaledMetric(relativeTo: .headline) private var badgeSide = 44.0
    @ScaledMetric(relativeTo: .headline) private var buttonHeight = 52.0

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            heading
            benefits
            if let code = referral.code {
                VStack(spacing: KXSpacing.s) {
                    ticket(code)
                    if let link = referral.link {
                        shareButton(code: code, link: link)
                    }
                }
            } else {
                createButton
            }
            if referral.rewarded > 0 || referral.pending > 0 {
                Text("account.loyalty.referral.count \(referral.rewarded) \(referral.pending)", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.keyCardMuted)
                    .accessibilityIdentifier("loyalty.referral.count")
            }
        }
        .padding(KXSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.keyCardBackground, in: RoundedRectangle(cornerRadius: KXRadius.large, style: .continuous))
    }

    // MARK: Parts

    private var heading: some View {
        HStack(alignment: .top, spacing: KXSpacing.s) {
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text("account.loyalty.referral.headline", bundle: .module)
                    .kxFont(.title2)
                    .foregroundStyle(KXColor.keyCardText)
                    .accessibilityAddTraits(.isHeader)
                Text("account.loyalty.referral.lead", bundle: .module)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.keyCardMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "person.2.fill")
                .kxFont(.headline)
                .foregroundStyle(KXColor.keyCardText)
                .frame(width: badgeSide, height: badgeSide)
                .background(KXColor.keyCardText.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
        }
    }

    private var benefits: some View {
        HStack(alignment: .top, spacing: KXSpacing.s) {
            benefit(
                value: Text("account.loyalty.referral.friend.value \(referral.friendPercent)", bundle: .module),
                label: Text("account.loyalty.referral.friend.label", bundle: .module)
            )
            benefit(
                value: Text(verbatim: format.euro(cents: referral.rewardCents)),
                label: Text("account.loyalty.referral.you.label \(format.points(referral.rewardPoints))", bundle: .module)
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func benefit(value: Text, label: Text) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            value
                .kxFont(.numeral)
                .foregroundStyle(KXColor.keyCardText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            label
                .kxFont(.footnote)
                .foregroundStyle(KXColor.keyCardMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(KXSpacing.m)
        .background(KXColor.keyCardText.opacity(0.08), in: tileShape)
        .accessibilityElement(children: .combine)
    }

    /// The code as a ticket with a dashed border; a tap anywhere on it copies the code.
    private func ticket(_ code: String) -> some View {
        Button {
            KXClipboard.copySensitive(code)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                didCopy = false
            }
        } label: {
            HStack(spacing: KXSpacing.s) {
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text("account.loyalty.referral.code.label", bundle: .module)
                        .kxFont(.eyebrow)
                        .foregroundStyle(KXColor.keyCardMuted)
                    Text(verbatim: code)
                        .kxFont(.licenseKey)
                        .foregroundStyle(KXColor.keyCardText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("loyalty.referral.code")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Label {
                    if didCopy {
                        Text("account.loyalty.code.copied", bundle: .module)
                    } else {
                        Text("account.loyalty.code.copy", bundle: .module)
                    }
                } icon: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .kxFont(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(KXColor.keyCardBackground)
                .padding(.horizontal, KXSpacing.s)
                .padding(.vertical, KXSpacing.xs)
                .background(KXColor.keyCardText, in: Capsule())
            }
            .padding(KXSpacing.m)
            .overlay(
                tileShape.strokeBorder(
                    KXColor.keyCardText.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
            )
            .contentShape(tileShape)
            .kxAnimation(value: didCopy)
        }
        .buttonStyle(.kxPress)
        .sensoryFeedback(.success, trigger: didCopy) { _, copied in copied }
        .accessibilityIdentifier("loyalty.referral.copy")
    }

    private func shareButton(code: String, link: URL) -> some View {
        ShareLink(
            item: link,
            subject: Text("account.loyalty.referral.share.subject", bundle: .module),
            message: Text("account.loyalty.referral.share.message \(code) \(referral.friendPercent)", bundle: .module)
        ) {
            invertedLabel(Text("account.loyalty.referral.share", bundle: .module), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.kxPress)
        .accessibilityIdentifier("loyalty.referral.share")
    }

    private var createButton: some View {
        Button {
            onCreate()
        } label: {
            ZStack {
                invertedLabel(Text("account.loyalty.referral.create", bundle: .module), systemImage: "person.badge.plus")
                    .opacity(isCreating ? 0 : 1)
                if isCreating {
                    ProgressView()
                        .tint(KXColor.keyCardBackground)
                }
            }
        }
        .buttonStyle(.kxPress)
        .disabled(isCreating)
        .accessibilityIdentifier("loyalty.referral.create")
    }

    /// A white capsule with dark text, the main action on the dark card.
    private func invertedLabel(_ title: Text, systemImage: String) -> some View {
        Label {
            title
        } icon: {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
        .kxFont(.headline)
        .foregroundStyle(KXColor.keyCardBackground)
        .frame(maxWidth: .infinity, minHeight: buttonHeight)
        .background(KXColor.keyCardText, in: Capsule())
        .contentShape(Capsule())
    }
}
