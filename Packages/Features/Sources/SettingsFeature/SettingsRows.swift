import DesignSystem
import SwiftUI

// MARK: - SettingsGroup

/// A grouped panel of settings rows in the style of iOS: an optional small header above, the
/// rows on one light grey panel with inset dividers, and an optional footer below.
struct SettingsGroup<Content: View, Footer: View>: View {
    private let header: Text?
    private let content: Content
    private let footer: Footer

    init(_ header: Text? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.header = header
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            if let header {
                header
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textSecondary)
                    .padding(.horizontal, KXSpacing.m)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                content
            }
            .background(
                KXColor.surface,
                in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous)
            )
            footer
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, KXSpacing.m)
        }
    }
}

extension SettingsGroup where Footer == EmptyView {
    init(_ header: Text? = nil, @ViewBuilder content: () -> Content) {
        self.init(header, content: content) { EmptyView() }
    }
}

// MARK: - SettingsRowDivider

/// The divider between two rows, inset to start below the title like in iOS.
struct SettingsRowDivider: View {
    @ScaledMetric(relativeTo: .body) private var iconSide = SettingsIcon.defaultSide

    var body: some View {
        KXDivider()
            .padding(.leading, KXSpacing.m + iconSide + KXSpacing.m)
    }
}

// MARK: - SettingsIcon

/// The symbol of a row on a small ink tile.
struct SettingsIcon: View {
    static let defaultSide: CGFloat = 30

    let systemImage: String

    @ScaledMetric(relativeTo: .body) private var side = SettingsIcon.defaultSide

    var body: some View {
        Image(systemName: systemImage)
            .kxFont(.subheadline)
            .foregroundStyle(KXColor.background)
            .frame(width: side, height: side)
            .background(KXColor.textPrimary, in: RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - SettingsRow

/// One row: the icon, the title (with an optional explanation below), an optional value on the
/// trailing side and an accessory. Put it in a `Button` to make it tappable.
struct SettingsRow: View {
    /// What the row shows at its trailing edge.
    enum Accessory {
        case none
        /// Opens a screen or a sheet.
        case chevron
        /// Leaves the app (iOS settings).
        case external
        /// The chosen option of a list.
        case checkmark
    }

    let systemImage: String
    let title: Text
    var detail: Text?
    var value: String?
    var accessory: Accessory = .none

    var body: some View {
        HStack(spacing: KXSpacing.m) {
            SettingsIcon(systemImage: systemImage)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                title
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textPrimary)
                if let detail {
                    detail
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            accessoryView
        }
        .padding(.horizontal, KXSpacing.m)
        .padding(.vertical, KXSpacing.s)
        .frame(minHeight: KXSpacing.minimumTapTarget + KXSpacing.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            symbol("chevron.right", color: KXColor.iconSecondary)
        case .external:
            symbol("arrow.up.forward", color: KXColor.iconSecondary)
        case .checkmark:
            symbol("checkmark", color: KXColor.textPrimary)
        }
    }

    private func symbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .fontWeight(.semibold)
            .kxFont(.footnote)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

// MARK: - SettingsToggleRow

/// A row with a switch: the icon, the title with its explanation and the toggle.
struct SettingsToggleRow: View {
    let systemImage: String
    let title: Text
    let detail: Text
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: KXSpacing.m) {
                SettingsIcon(systemImage: systemImage)
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    title
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                    detail
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(KXColor.brand)
        .padding(.horizontal, KXSpacing.m)
        .padding(.vertical, KXSpacing.s)
        .frame(minHeight: KXSpacing.minimumTapTarget + KXSpacing.s)
    }
}
