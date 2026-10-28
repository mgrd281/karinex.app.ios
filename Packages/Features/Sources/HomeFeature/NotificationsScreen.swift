import BackendKit
import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - NotificationsScreen

/// "Neuigkeiten", opened from the bell of the Start tab, laid out like About You: on a light grey
/// page one white card per message, with a small header row (symbol, label, day) above the
/// product photo and the bold title with its text. New messages come first under "Neu", the
/// rest under "Gesehen"; at the end a note says that messages disappear after 30 days.
///
/// Messages of the store owner show their own title and text. Automatic messages (back in
/// stock, order paid, keys delivered) are written here in the customer's language from their
/// parameters. A tap opens the product, the order or the license vault. Leaving the screen marks
/// everything as read.
public struct NotificationsScreen: View {
    private let showsPushHint: Bool
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @Environment(InboxStore.self) private var inbox: InboxStore?

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - showsPushHint: Whether to suggest turning on notifications (the customer has not
    ///     agreed to any push category yet).
    ///   - onRoute: Opens a product, an order, the license vault or the settings.
    public init(showsPushHint: Bool, onRoute: @escaping @MainActor (CommerceRoute) -> Void) {
        self.showsPushHint = showsPushHint
        self.onRoute = onRoute
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                if showsPushHint {
                    pushHint
                }
                content
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
        }
        .background(KXColor.surface.ignoresSafeArea())
        .refreshable {
            await inbox?.refresh()
        }
        .task {
            await inbox?.refresh()
        }
        .onDisappear {
            inbox?.markAllSeen()
        }
        .navigationTitle(Text("home.notifications.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: KXSpacing.xs) {
                    Image(systemName: "bell")
                        .accessibilityHidden(true)
                    Text("home.notifications.title", bundle: .module)
                }
                .kxFont(.headline)
                .foregroundStyle(KXColor.textPrimary)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
        }
        .accessibilityIdentifier("screen.notifications")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch inbox?.state ?? .empty {
        case .idle, .loading:
            ForEach(0..<3, id: \.self) { _ in
                KXSkeleton(cornerRadius: KXRadius.card)
                    .frame(height: 150)
            }
        case .empty:
            emptyState
        case let .failed(error):
            KXEmptyState(systemImage: error.systemImage, title: error.title, message: error.message)
                .frame(maxWidth: .infinity)
                .padding(.top, KXSpacing.xl)
        case let .loaded(messages):
            let unread = messages.filter { inbox?.isUnread($0) ?? false }
            let read = messages.filter { !(inbox?.isUnread($0) ?? false) }
            if !unread.isEmpty {
                section(titleKey: "home.notifications.new", messages: unread, isUnread: true)
            }
            if !read.isEmpty {
                section(titleKey: "home.notifications.seen", messages: read, isUnread: false)
            }
            Text("home.notifications.end", bundle: .module)
                .kxFont(.subheadline)
                .foregroundStyle(KXColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, KXSpacing.xl)
        }
    }

    private func section(titleKey: LocalizedStringKey, messages: [InboxMessage], isUnread: Bool) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            HStack(spacing: KXSpacing.xs) {
                Text(titleKey, bundle: .module)
                    .kxFont(.title3)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(messages.count, format: .number)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .padding(.horizontal, KXSpacing.xs)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(KXColor.divider, in: Capsule())
            }
            .padding(.top, KXSpacing.xs)
            ForEach(messages) { message in
                NotificationCard(message: message, isUnread: isUnread) {
                    open(message)
                }
            }
        }
    }

    private var emptyState: some View {
        KXEmptyState(
            systemImage: "bell",
            title: String(localized: "home.notifications.empty.title", bundle: .module),
            message: String(localized: "home.notifications.empty.message", bundle: .module)
        )
        .frame(maxWidth: .infinity)
        .padding(.top, KXSpacing.xxl)
    }

    private var pushHint: some View {
        Button {
            onRoute(.account(.settings))
        } label: {
            HStack(alignment: .center, spacing: KXSpacing.s) {
                Image(systemName: "bell.badge")
                    .kxFont(.title3)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text("home.notifications.push.title", bundle: .module)
                        .kxFont(.headline)
                    Text("home.notifications.push.message", bundle: .module)
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KXColor.iconSecondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(KXColor.textPrimary)
            .padding(KXSpacing.m)
            .background(KXColor.background, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notifications.pushHint")
    }

    private func open(_ message: InboxMessage) {
        switch message.kind {
        case .orderPaid:
            if let id = message.params["orderId"], let gid = Self.orderID(id) {
                onRoute(.account(.order(id: gid)))
            } else {
                onRoute(.account(.orders))
            }
        case .licenseDelivered:
            onRoute(.account(.licenses(orderID: nil)))
        case .broadcast, .restock, .unknown:
            if let handle = message.productHandle {
                onRoute(.product(handle: handle))
            }
        }
    }

    private static func orderID(_ number: String) -> ShopifyID? {
        guard !number.isEmpty, number.count <= 20, number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return ShopifyID("gid://shopify/Order/\(number)")
    }
}

// MARK: - NotificationCard

/// One message: header row with symbol, label and day; below the photo (or a symbol tile) and
/// the bold title with the text.
struct NotificationCard: View {
    let message: InboxMessage
    let isUnread: Bool
    let action: @MainActor () -> Void

    @ScaledMetric(relativeTo: .body) private var photoWidth: CGFloat = 88

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                header
                KXDivider()
                HStack(alignment: .top, spacing: KXSpacing.m) {
                    photo
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(verbatim: NotificationText.title(for: message))
                            .kxFont(.headline)
                            .foregroundStyle(KXColor.textPrimary)
                        Text(verbatim: NotificationText.body(for: message))
                            .kxFont(.subheadline)
                            .foregroundStyle(KXColor.textPrimary)
                            .lineSpacing(KXSpacing.xxs / 2)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(KXSpacing.m)
            }
            .background(KXColor.background, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notification.\(message.id)")
    }

    private var header: some View {
        HStack(spacing: KXSpacing.xs) {
            Image(systemName: NotificationText.symbol(for: message))
                .foregroundStyle(KXColor.textPrimary)
                .accessibilityHidden(true)
            Text(verbatim: NotificationText.label(for: message))
                .foregroundStyle(KXColor.textPrimary)
                .lineLimit(1)
            if isUnread {
                Circle()
                    .fill(KXColor.urgency)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(Text("home.notifications.unread", bundle: .module))
            }
            Spacer(minLength: KXSpacing.xs)
            Text(verbatim: NotificationText.day(for: message.createdAt))
                .foregroundStyle(KXColor.textSecondary)
        }
        .kxFont(.footnote)
        .padding(.horizontal, KXSpacing.m)
        .padding(.vertical, KXSpacing.s)
    }

    @ViewBuilder
    private var photo: some View {
        if let url = message.imageURL {
            ProductImage(url: url, altText: nil)
                .aspectRatio(contentMode: .fit)
                .frame(width: photoWidth, height: photoWidth * 1.15)
        } else {
            Image(systemName: NotificationText.tileSymbol(for: message))
                .kxFont(.title2)
                .foregroundStyle(KXColor.textPrimary)
                .frame(width: photoWidth, height: photoWidth)
                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - NotificationText

/// The texts of a message in the customer's language.
enum NotificationText {
    static func label(for message: InboxMessage) -> String {
        switch message.kind {
        case .broadcast:
            if let label = message.label, !label.isEmpty {
                return label
            }
            return String(localized: "home.notifications.label.news", bundle: .module)
        case .restock:
            return String(localized: "home.notifications.label.restock", bundle: .module)
        case .orderPaid, .licenseDelivered:
            return String(localized: "home.notifications.label.order", bundle: .module)
        case .unknown:
            return ""
        }
    }

    static func title(for message: InboxMessage) -> String {
        switch message.kind {
        case .broadcast, .unknown:
            message.title
        case .restock:
            String(localized: "home.notifications.restock.title", bundle: .module)
        case .orderPaid:
            String(localized: "home.notifications.paid.title", bundle: .module)
        case .licenseDelivered:
            String(localized: "home.notifications.delivered.title", bundle: .module)
        }
    }

    static func body(for message: InboxMessage) -> String {
        let product = message.params["productTitle"] ?? ""
        let order = message.params["orderName"] ?? ""
        return switch message.kind {
        case .broadcast, .unknown:
            message.body
        case .restock:
            String(localized: "home.notifications.restock.body \(product)", bundle: .module)
        case .orderPaid:
            String(localized: "home.notifications.paid.body \(order)", bundle: .module)
        case .licenseDelivered:
            String(localized: "home.notifications.delivered.body \(order)", bundle: .module)
        }
    }

    /// The symbol of the header row.
    static func symbol(for message: InboxMessage) -> String {
        switch message.kind {
        case .restock: "bell.badge"
        case .orderPaid, .licenseDelivered: "shippingbox"
        case .broadcast, .unknown: "info.circle"
        }
    }

    /// The symbol on the tile when the message has no photo.
    static func tileSymbol(for message: InboxMessage) -> String {
        switch message.kind {
        case .orderPaid: "creditcard"
        case .licenseDelivered: "key"
        case .restock: "bell.badge"
        case .broadcast, .unknown: "sparkles"
        }
    }

    /// "Heute", "Gestern" or the date.
    static func day(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "home.notifications.today", bundle: .module)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "home.notifications.yesterday", bundle: .module)
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
