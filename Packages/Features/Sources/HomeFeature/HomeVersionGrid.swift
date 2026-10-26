import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - HomeVersionGrid

/// "Nach Version finden": a two by two grid of product versions (Windows 11, Windows 10,
/// Office 2024, Office 2021), each tile with the photo of its collection's first product and
/// the version name, like the guide grids of fashion retail apps; one row of four on a wide
/// screen. A tile opens its collection; a version whose collection is empty drops out.
struct HomeVersionGrid: View {
    let versions: [HomeCategory]
    let state: @MainActor (HomeCategory) -> LoadState<[ProductSummary]>
    let onOpen: @MainActor (HomeCategory) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: KXSpacing.xs), count: count)
    }

    private var visible: [HomeCategory] {
        versions.filter { version in
            if case .empty = state(version) {
                return false
            }
            return true
        }
    }

    var body: some View {
        let shown = visible
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                KXSectionHeader(
                    String(localized: "home.versions.title", bundle: .module),
                    eyebrow: String(localized: "home.versions.eyebrow", bundle: .module)
                )
                LazyVGrid(columns: columns, spacing: KXSpacing.xs) {
                    ForEach(shown) { version in
                        tile(version)
                    }
                }
            }
            .padding(.horizontal, KXSpacing.gutter)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.versions")
        }
    }

    private func tile(_ version: HomeCategory) -> some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
        let image = state(version).value?.first?.featuredImage
        return Button {
            onOpen(version)
        } label: {
            ZStack(alignment: .bottomLeading) {
                ProductImage(image, isDecorative: true)
                    .padding(.horizontal, KXSpacing.l)
                    .padding(.top, KXSpacing.l)
                    .padding(.bottom, KXSpacing.xxl)
                    .kxPhotoTile()
                Text(version.title.resolved)
                    .fontWeight(.semibold)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                    .lineLimit(2)
                    .padding(KXSpacing.s)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(shape)
            .contentShape(shape)
            // The tile is a light photo tile in both appearances, so its text stays dark.
            .environment(\.colorScheme, .light)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(version.title.resolved))
        .accessibilityIdentifier("home.version.\(version.handle)")
    }
}

// MARK: - HomeServiceTiles

/// "Rund um Ihren Kauf": tiles into the account area (help and support, the license keys, the
/// orders), each with its name and a symbol on an ink disc, like the inspiration tiles of
/// fashion retail apps.
struct HomeServiceTiles: View {
    let onRoute: @MainActor (CommerceRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(
                String(localized: "home.service.title", bundle: .module),
                eyebrow: String(localized: "home.service.eyebrow", bundle: .module)
            )
            HStack(alignment: .top, spacing: KXSpacing.xs) {
                tile(.support)
                tile(.licenses)
            }
            tile(.orders)
        }
        .padding(.horizontal, KXSpacing.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.service")
    }

    private func tile(_ link: HomeServiceLink) -> some View {
        HomeServiceTile(link: link) {
            onRoute(link.route)
        }
    }
}

// MARK: - HomeServiceLink

/// A destination of the service tiles.
enum HomeServiceLink: String, CaseIterable, Sendable {
    /// Hilfe und Support.
    case support
    /// The license keys of the customer's orders.
    case licenses
    /// The customer's orders.
    case orders

    /// The tile name in the user's language.
    var title: String {
        switch self {
        case .support: String(localized: "home.service.support", bundle: .module)
        case .licenses: String(localized: "home.service.licenses", bundle: .module)
        case .orders: String(localized: "home.service.orders", bundle: .module)
        }
    }

    /// The SF Symbol on the tile's disc.
    var systemImage: String {
        switch self {
        case .support: "questionmark.bubble"
        case .licenses: "key"
        case .orders: "shippingbox"
        }
    }

    /// Where the tile leads.
    var route: CommerceRoute {
        switch self {
        case .support: .account(.support(orderName: nil))
        case .licenses: .account(.licenses(orderID: nil))
        case .orders: .account(.orders)
        }
    }
}

// MARK: - HomeServiceTile

/// One service tile on a light grey panel: the bold name and the symbol on an ink disc.
private struct HomeServiceTile: View {
    let link: HomeServiceLink
    let action: @MainActor () -> Void

    @ScaledMetric(relativeTo: .headline) private var discDiameter: CGFloat = 40
    @ScaledMetric(relativeTo: .headline) private var minimumHeight: CGFloat = 76

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous)
        Button {
            action()
        } label: {
            HStack(alignment: .center, spacing: KXSpacing.s) {
                Text(link.title)
                    .fontWeight(.semibold)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: link.systemImage)
                    .kxFont(.callout)
                    .foregroundStyle(KXColor.textOnAccent)
                    .frame(width: discDiameter, height: discDiameter)
                    .background(KXColor.accent, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(KXSpacing.m)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .background(KXColor.surface, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.service.\(link.rawValue)")
    }
}
