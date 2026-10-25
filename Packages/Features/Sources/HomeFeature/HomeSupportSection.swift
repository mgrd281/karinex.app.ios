import DesignSystem
import SwiftUI

// MARK: - HomeSupportSection

/// The support card of the Start tab: the three channels (WhatsApp, e-mail, live chat) and the
/// service hours, presented as information.
///
/// The card has no buttons in Phase 0: the channel actions arrive with the support hub in
/// Phase 2. The e-mail address can be selected and copied.
struct HomeSupportSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(
                String(localized: "home.support.title", bundle: .module),
                eyebrow: String(localized: "home.support.eyebrow", bundle: .module)
            )
            KXCard {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    Text("home.support.message", bundle: .module)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        ForEach(SupportChannel.allCases) { channel in
                            SupportChannelRow(channel: channel)
                        }
                    }
                    KXDivider()
                    KXSpecRow(
                        String(localized: "home.support.hours.label", bundle: .module),
                        value: String(localized: "home.support.hours.value", bundle: .module)
                    )
                }
                .padding(KXSpacing.xxs)
            }
            .accessibilityIdentifier("home.support")
        }
    }
}

// MARK: - Channel row

/// One support channel: its symbol on a white disc, its name and, for e-mail, the address.
private struct SupportChannelRow: View {
    let channel: SupportChannel

    @ScaledMetric(relativeTo: .headline) private var iconDiameter: CGFloat = 36

    var body: some View {
        HStack(alignment: .center, spacing: KXSpacing.s) {
            Image(systemName: channel.systemImage)
                .fontWeight(.medium)
                .kxFont(.callout)
                .foregroundStyle(KXColor.textPrimary)
                .frame(width: iconDiameter, height: iconDiameter)
                .background(KXColor.surfaceElevated, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(channel.name)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                if let detail = channel.detail {
                    Text(verbatim: detail)
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                        .textSelection(.enabled)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
