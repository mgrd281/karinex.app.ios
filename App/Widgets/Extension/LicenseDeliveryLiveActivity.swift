import ActivityKit
import DesignTokens
import SwiftUI
import WidgetKit

// MARK: - LicenseDeliveryLiveActivity

/// "Lizenz wird zugestellt": on the Lock Screen and in the Dynamic Island while the key of a
/// paid order is on its way, and briefly "Zugestellt" afterwards. Tapping opens the license
/// vault. It shows no key and no amount.
struct LicenseDeliveryLiveActivity: Widget {
    static let vaultURL = URL(string: "karinex://account/licenses")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LicenseDeliveryAttributes.self) { context in
            LockScreenView(phase: context.state.phase)
                .activityBackgroundTint(WidgetPalette.color(.brand))
                .activitySystemActionForegroundColor(WidgetPalette.color(.textOnBrand))
                .widgetURL(Self.vaultURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseIcon(phase: context.state.phase)
                }
                DynamicIslandExpandedRegion(.center) {
                    PhaseTitle(phase: context.state.phase)
                        .font(WidgetPalette.font(.headline))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PhaseDetail(phase: context.state.phase)
                        .font(WidgetPalette.font(.footnote))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                PhaseIcon(phase: context.state.phase)
            } compactTrailing: {
                PhaseTitle(phase: context.state.phase)
                    .font(WidgetPalette.font(.caption))
                    .lineLimit(1)
            } minimal: {
                PhaseIcon(phase: context.state.phase)
            }
            .widgetURL(Self.vaultURL)
            .keylineTint(WidgetPalette.color(.accent))
        }
    }
}

// MARK: - Parts

private struct LockScreenView: View {
    let phase: LicenseDeliveryAttributes.Phase

    var body: some View {
        HStack(alignment: .center, spacing: SpacingToken.m) {
            PhaseIcon(phase: phase)
                .font(.title2)
            VStack(alignment: .leading, spacing: SpacingToken.xxs) {
                Text(verbatim: "KARINEX")
                    .font(WidgetPalette.font(.eyebrow))
                    .foregroundStyle(WidgetPalette.color(.accent))
                PhaseTitle(phase: phase)
                    .font(WidgetPalette.font(.title3))
                    .foregroundStyle(WidgetPalette.color(.textOnBrand))
                PhaseDetail(phase: phase)
                    .font(WidgetPalette.font(.footnote))
                    .foregroundStyle(WidgetPalette.color(.textOnBrand).opacity(0.8))
            }
            Spacer(minLength: 0)
        }
        .padding(SpacingToken.m)
    }
}

private struct PhaseIcon: View {
    let phase: LicenseDeliveryAttributes.Phase

    var body: some View {
        Image(systemName: phase == .delivered ? "checkmark.seal.fill" : "key.horizontal.fill")
            .foregroundStyle(WidgetPalette.color(.accent))
            .accessibilityHidden(true)
    }
}

private struct PhaseTitle: View {
    let phase: LicenseDeliveryAttributes.Phase

    var body: some View {
        switch phase {
        case .preparing: Text("activity.license.preparing.title")
        case .delivered: Text("activity.license.delivered.title")
        }
    }
}

private struct PhaseDetail: View {
    let phase: LicenseDeliveryAttributes.Phase

    var body: some View {
        switch phase {
        case .preparing: Text("activity.license.preparing.detail")
        case .delivered: Text("activity.license.delivered.detail")
        }
    }
}
