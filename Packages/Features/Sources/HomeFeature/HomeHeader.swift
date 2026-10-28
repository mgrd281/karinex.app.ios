import CommerceUI
import DesignSystem
import SwiftUI

// MARK: - HomeBrandBar

/// The top of the Start screen above the search field: the KARINEX logo and the heart that opens
/// the Merkliste, with the number of saved products beside it. It scrolls away while the search
/// field stays pinned.
struct HomeBrandBar: View {
    /// Opens "Neuigkeiten".
    let onNotifications: @MainActor () -> Void
    /// Opens the Merkliste.
    let onWishlist: @MainActor () -> Void

    @Environment(SavedProductsStore.self) private var savedProducts: SavedProductsStore?
    @Environment(InboxStore.self) private var inbox: InboxStore?

    var body: some View {
        HStack(spacing: KXSpacing.m) {
            KXWordmark(size: .regular)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if inbox != nil {
                    notificationsButton
                }
                wishlistButton
            }
        }
        .padding(.leading, KXSpacing.gutter)
        .padding(.trailing, KXSpacing.xs)
        .padding(.top, KXSpacing.xxs)
    }

    /// The bell, as at About You: a red dot while there are new messages.
    private var notificationsButton: some View {
        let unread = inbox?.unreadCount ?? 0
        return Button {
            onNotifications()
        } label: {
            Image(systemName: "bell")
                .kxFont(.title3)
                .foregroundStyle(KXColor.textPrimary)
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        Circle()
                            .fill(KXColor.urgency)
                            .frame(width: 9, height: 9)
                            .offset(x: 2, y: -1)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(minWidth: KXSpacing.minimumTapTarget, minHeight: KXSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("home.notifications.title", bundle: .module))
        .accessibilityValue(unread > 0 ? Text("home.notifications.unread", bundle: .module) : Text(verbatim: ""))
        .accessibilityIdentifier("home.notifications")
        .task {
            await inbox?.refresh()
        }
    }

    private var wishlistButton: some View {
        let saved = savedProducts?.wishlist ?? []
        return Button {
            onWishlist()
        } label: {
            HStack(spacing: KXSpacing.xxs) {
                Image(systemName: "heart")
                    .kxFont(.title3)
                if !saved.isEmpty {
                    Text(saved.count, format: .number)
                        .kxFont(.subheadline)
                }
            }
            .foregroundStyle(KXColor.textPrimary)
            .padding(.horizontal, KXSpacing.xs)
            .frame(minWidth: KXSpacing.minimumTapTarget, minHeight: KXSpacing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("home.brand.wishlist", bundle: .module))
        .accessibilityValue(saved.isEmpty ? "" : saved.count.formatted())
        .accessibilityIdentifier("home.wishlist")
    }
}

// MARK: - HomeSearchField

/// The search field of the Start screen, pinned to the top while the page scrolls, as in fashion
/// retail apps. It is a button: a tap opens the Suche tab, where typing starts. Once pinned, a
/// hairline separates it from the content scrolling below.
struct HomeSearchField: View {
    /// Whether the field is pinned to the top of the screen.
    let isPinned: Bool
    /// Opens the search.
    let action: @MainActor () -> Void

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 48

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: KXSpacing.s) {
                Image(systemName: "magnifyingglass")
                    .fontWeight(.medium)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityHidden(true)
                Text("home.search.prompt", bundle: .module)
                    .foregroundStyle(KXColor.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .kxFont(.body)
            .padding(.horizontal, KXSpacing.m)
            .frame(minHeight: height)
            .background(KXColor.surface, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("home.search.hint", bundle: .module))
        .accessibilityIdentifier("home.search")
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.vertical, KXSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(KXColor.background)
        .overlay(alignment: .bottom) {
            if isPinned {
                KXDivider()
            }
        }
    }
}
