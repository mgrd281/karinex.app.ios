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
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            Text("account.loyalty.referral.steps.title", bundle: .module)
                .kxFont(.subheadline)
                .foregroundStyle(KXColor.textSecondary)
                .padding(.horizontal, KXSpacing.m)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ReferralStepRow(
                    number: 1,
                    systemImage: "square.and.arrow.up",
                    title: Text("account.loyalty.referral.step.share", bundle: .module),
                    isLast: false
                )
                ReferralStepRow(
                    number: 2,
                    systemImage: "bag",
                    title: Text("account.loyalty.referral.step.order \(referral.friendPercent)", bundle: .module),
                    isLast: false
                )
                ReferralStepRow(
                    number: 3,
                    systemImage: "gift",
                    title: Text("account.loyalty.referral.step.reward \(format.points(referral.rewardPoints))", bundle: .module),
                    isLast: true
                )
            }
            .padding(KXSpacing.m)
            .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
            Text("account.loyalty.referral.limit \(referral.maxPerYear)", bundle: .module)
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textSecondary)
                .padding(.horizontal, KXSpacing.m)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("loyalty.referral.steps")
    }
}

// MARK: - ReferralStepRow

/// One step of "So funktioniert es": a numbered dot on a thin line that joins the steps, the
/// text, and a small symbol at the trailing edge.
private struct ReferralStepRow: View {
    let number: Int
    let systemImage: String
    let title: Text
    let isLast: Bool

    @ScaledMetric(relativeTo: .subheadline) private var dotSide = 30.0

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.m) {
            VStack(spacing: KXSpacing.xxs) {
                Text(number, format: .number)
                    .kxFont(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(KXColor.keyCardText)
                    .frame(width: dotSide, height: dotSide)
                    .background(KXColor.keyCardBackground, in: Circle())
                if !isLast {
                    Capsule()
                        .fill(KXColor.divider)
                        .frame(width: KXBorder.emphasis)
                        .frame(maxHeight: .infinity)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
                title
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: systemImage)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.iconSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.top, KXSpacing.xxs)
            .padding(.bottom, isLast ? 0 : KXSpacing.l)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ReferralInviteCard

/// The dark card of "Freunde einladen" in the colors of the license key card: the heading,
/// both benefits as tiles with a symbol, the code as a voucher and the white share button.
private struct ReferralInviteCard: View {
    let referral: LoyaltyStatus.Referral
    let format: LoyaltyFormat
    let isCreating: Bool
    let onCreate: () -> Void

    /// Shows "Kopiert" for a moment after the code was copied.
    @State private var didCopy = false

    @ScaledMetric(relativeTo: .headline) private var badgeSide = 44.0
    @ScaledMetric(relativeTo: .headline) private var buttonHeight = 52.0
    @ScaledMetric(relativeTo: .footnote) private var iconSide = 28.0
    @ScaledMetric(relativeTo: .headline) private var copySide = 44.0

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
                systemImage: "tag.fill",
                value: Text("account.loyalty.referral.friend.value \(referral.friendPercent)", bundle: .module),
                label: Text("account.loyalty.referral.friend.label", bundle: .module)
            )
            benefit(
                systemImage: "gift.fill",
                value: Text(verbatim: format.euro(cents: referral.rewardCents)),
                label: Text("account.loyalty.referral.you.label \(format.points(referral.rewardPoints))", bundle: .module)
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func benefit(systemImage: String, value: Text, label: Text) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            Image(systemName: systemImage)
                .kxFont(.footnote)
                .foregroundStyle(KXColor.keyCardText)
                .frame(width: iconSide, height: iconSide)
                .background(KXColor.keyCardText.opacity(0.14), in: Circle())
                .padding(.bottom, KXSpacing.xs)
                .accessibilityHidden(true)
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

    /// The code as a ticket with a notch on either side and a perforation line; a tap anywhere
    /// on it copies the code, and the round button shows a check mark for a moment.
    private func ticket(_ code: String) -> some View {
        Button {
            KXClipboard.copySensitive(code)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                didCopy = false
            }
        } label: {
            HStack(spacing: KXSpacing.m) {
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Group {
                        if didCopy {
                            Text("account.loyalty.code.copied", bundle: .module)
                        } else {
                            Text("account.loyalty.referral.code.label", bundle: .module)
                        }
                    }
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.keyCardMuted)
                    .contentTransition(.opacity)
                    Text(verbatim: code)
                        .kxFont(.licenseKey)
                        .foregroundStyle(KXColor.keyCardText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityIdentifier("loyalty.referral.code")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PerforationLine()
                    .stroke(KXColor.keyCardText.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .frame(width: 1, height: copySide)
                    .accessibilityHidden(true)
                Image(systemName: didCopy ? "checkmark" : "square.on.square")
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.keyCardBackground)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: copySide, height: copySide)
                    .background(KXColor.keyCardText, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.vertical, KXSpacing.m)
            .padding(.leading, KXSpacing.l)
            .padding(.trailing, KXSpacing.m)
            .background(KXColor.keyCardText.opacity(0.08), in: TicketShape())
            .contentShape(TicketShape())
            .kxAnimation(value: didCopy)
        }
        .buttonStyle(.kxPress)
        .sensoryFeedback(.success, trigger: didCopy) { _, copied in copied }
        .accessibilityLabel(Text(verbatim: code))
        .accessibilityHint(Text("account.loyalty.code.copy", bundle: .module))
        .accessibilityValue(didCopy ? Text("account.loyalty.code.copied", bundle: .module) : Text(verbatim: ""))
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

// MARK: - Ticket shapes

/// A rounded rectangle with a half circle cut out of the left and right edges, like a voucher.
private struct TicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notch = min(10, rect.height / 4)
        let body = Path(roundedRect: rect, cornerRadius: KXRadius.medium, style: .continuous)
        var cuts = Path()
        cuts.addEllipse(in: CGRect(x: rect.minX - notch, y: rect.midY - notch, width: notch * 2, height: notch * 2))
        cuts.addEllipse(in: CGRect(x: rect.maxX - notch, y: rect.midY - notch, width: notch * 2, height: notch * 2))
        return body.subtracting(cuts)
    }
}

/// A vertical line through the middle of its frame, drawn dashed as the ticket's perforation.
private struct PerforationLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
