import SwiftUI

// MARK: - KXListGroup

/// A grouped list in the style of iOS settings: rows with a small ink icon tile, a title, an
/// optional value and an accessory, on one light grey panel with inset dividers. Values sit
/// at the trailing edge with open space before them, never behind a dotted leader.
///
/// ```swift
/// KXListGroup(Text("Darstellung")) {
///     Button { open() } label: {
///         KXListRow(systemImage: "globe.europe.africa", title: Text("Land"), value: "Deutschland", accessory: .chevron)
///     }
///     KXListDivider()
///     KXListToggleRow(systemImage: "faceid", title: Text("Sperren"), detail: Text("…"), isOn: $locks)
/// }
/// ```
///
/// A grouped panel of rows: an optional small header above, the
/// rows on one light grey panel with inset dividers, and an optional footer below.
public struct KXListGroup<Content: View, Footer: View>: View {
    private let header: Text?
    private let content: Content
    private let footer: Footer

    /// Creates a group.
    ///
    /// - Parameters:
    ///   - header: The small title above the panel, `nil` for none.
    ///   - content: The rows, separated by ``KXListDivider``.
    ///   - footer: The explanation below the panel.
    public init(_ header: Text? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.header = header
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
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

extension KXListGroup where Footer == EmptyView {
    /// Creates a group without a footer.
    public init(_ header: Text? = nil, @ViewBuilder content: () -> Content) {
        self.init(header, content: content) { EmptyView() }
    }
}

// MARK: - KXListDivider

/// The divider between two rows, inset to start below the title like in iOS.
public struct KXListDivider: View {
    @ScaledMetric(relativeTo: .body) private var iconSide = KXListIcon.defaultSide

    /// Creates the divider.
    public init() {}

    public var body: some View {
        KXDivider()
            .padding(.leading, KXSpacing.m + iconSide + KXSpacing.m)
    }
}

// MARK: - KXListIcon

/// The symbol of a row on a small ink tile.
public struct KXListIcon: View {
    static let defaultSide: CGFloat = 30

    private let systemImage: String

    @ScaledMetric(relativeTo: .body) private var side = KXListIcon.defaultSide

    /// Creates the icon tile for an SF Symbol.
    public init(systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        Image(systemName: systemImage)
            .kxFont(.subheadline)
            .foregroundStyle(KXColor.background)
            .frame(width: side, height: side)
            .background(KXColor.textPrimary, in: RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - KXListRow

/// One row: the icon, the title (with an optional explanation below), an optional value on the
/// trailing side and an accessory. Put it in a `Button` to make it tappable.
public struct KXListRow: View {
    /// What the row shows at its trailing edge.
    public enum Accessory: Sendable {
        /// Nothing.
        case none
        /// Opens a screen or a sheet.
        case chevron
        /// Leaves the app (iOS settings).
        case external
        /// The chosen option of a list.
        case checkmark
        /// Opens a menu to choose a value.
        case menu
    }

    private let systemImage: String
    private let title: Text
    private let detail: Text?
    private let value: String?
    private let accessory: Accessory

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - systemImage: The SF Symbol on the ink tile.
    ///   - title: The title.
    ///   - detail: An explanation below the title.
    ///   - value: The current value on the trailing side, e.g. "Deutschland".
    ///   - accessory: What the row shows at its trailing edge.
    public init(systemImage: String, title: Text, detail: Text? = nil, value: String? = nil, accessory: Accessory = .none) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.value = value
        self.accessory = accessory
    }

    public var body: some View {
        HStack(spacing: KXSpacing.m) {
            KXListIcon(systemImage: systemImage)
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
        case .menu:
            symbol("chevron.up.chevron.down", color: KXColor.iconSecondary)
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

// MARK: - KXListToggleRow

/// A row with a switch: the icon, the title with its explanation and the toggle.
public struct KXListToggleRow: View {
    private let systemImage: String
    private let title: Text
    private let detail: Text
    @Binding private var isOn: Bool

    /// Creates a row with a switch.
    ///
    /// - Parameters:
    ///   - systemImage: The SF Symbol on the ink tile.
    ///   - title: The title.
    ///   - detail: The explanation below the title.
    ///   - isOn: The value of the switch.
    public init(systemImage: String, title: Text, detail: Text, isOn: Binding<Bool>) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: KXSpacing.m) {
                KXListIcon(systemImage: systemImage)
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

// MARK: - Previews

private struct KXListPreviewGallery: View {
    @State private var locks = true

    var body: some View {
        ScrollView {
            VStack(spacing: KXSpacing.xl) {
                KXListGroup(Text(verbatim: "Shop-Land und Inhalte")) {
                    KXListRow(systemImage: "globe.europe.africa", title: Text(verbatim: "Land"), value: "Deutschland", accessory: .menu)
                    KXListDivider()
                    KXListRow(
                        systemImage: "text.bubble",
                        title: Text(verbatim: "Sprache der Inhalte"),
                        value: "Deutsch",
                        accessory: .chevron
                    )
                    KXListDivider()
                    KXListRow(systemImage: "eurosign", title: Text(verbatim: "Währung"), value: "Euro (EUR)")
                } footer: {
                    Text(verbatim: "Die Sprache der App richtet sich nach den Einstellungen Ihres iPhone.")
                }
                KXListGroup {
                    KXListToggleRow(
                        systemImage: "faceid",
                        title: Text(verbatim: "Lizenzschlüssel sperren"),
                        detail: Text(verbatim: "Vor dem Anzeigen fragt die App nach Face ID."),
                        isOn: $locks
                    )
                }
            }
            .padding(KXSpacing.gutter)
        }
        .kxScreenBackground()
    }
}

#Preview("KXList, light") {
    KXListPreviewGallery()
}

#Preview("KXList, dark, accessibility size") {
    KXListPreviewGallery()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
