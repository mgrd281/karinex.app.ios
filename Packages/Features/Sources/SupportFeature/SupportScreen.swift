import BackendKit
import CommerceUI
import DesignSystem
import Foundation
import Observation
import ShopifyKit
import SwiftUI

// MARK: - SupportViewModel

/// Loads the support contact data from the backend (falling back to the built-in hours and
/// e-mail address) and the activation guides from the `guides` blog.
@MainActor
@Observable
final class SupportViewModel {
    /// The blog with the activation guides and help articles (docs/STORE_AUDIT.md).
    static let guidesBlogHandle = "guides"
    /// The number of guides shown.
    static let guideLimit = 6

    /// The order the customer asks about, e.g. `#1042`.
    let orderName: String?
    /// The remote config; the fallback until the backend answers.
    private(set) var config: RemoteAppConfig = .fallback
    /// The guides.
    private(set) var guides: LoadState<[ArticleSummary]> = .idle

    @ObservationIgnored private let backend: any BackendClient
    @ObservationIgnored private let content: any ContentRepository

    init(orderName: String?, backend: any BackendClient, content: any ContentRepository) {
        self.orderName = orderName
        self.backend = backend
        self.content = content
    }

    /// The contact options for the current config.
    var contact: SupportContact {
        SupportContact(config: config, orderName: orderName)
    }

    /// Loads the config and the guides concurrently. A failing backend keeps the fallback.
    func load() async {
        async let configResult = loadConfig()
        async let guidesResult: Void = loadGuides()
        if let loaded = await configResult {
            config = loaded
        }
        await guidesResult
    }

    private func loadConfig() async -> RemoteAppConfig? {
        try? await backend.appConfig()
    }

    private func loadGuides() async {
        if guides.value == nil {
            guides = .loading
        }
        do {
            let articles = try await content.articles(blogHandle: Self.guidesBlogHandle, first: Self.guideLimit)
            guides = LoadState(articles, isEmpty: \.isEmpty)
        } catch {
            if let failure = UserFacingError(error), guides.value == nil {
                guides = .failed(failure)
            }
        }
    }
}

// MARK: - SupportScreen

/// "Hilfe und Support": WhatsApp, e-mail and live chat with the order in the message, the
/// opening hours with a live "Jetzt erreichbar" indicator computed in Europe/Berlin, and the
/// activation guides (PROMPT.md 6.8).
public struct SupportScreen: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: SupportViewModel

    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - orderName: The order the customer asks about, e.g. `#1042`.
    ///   - backend: Provides the WhatsApp number, live chat link and hours.
    ///   - content: Loads the guides.
    ///   - onRoute: Opens a guide.
    public init(
        orderName: String?,
        backend: any BackendClient,
        content: any ContentRepository,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        _model = State(initialValue: SupportViewModel(orderName: orderName, backend: backend, content: content))
        self.onRoute = onRoute
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                hoursCard
                channels
                guides
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.support")
        .kxScreenBackground()
        .navigationTitle(Text("support.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.load() }
        .task {
            if model.guides.value == nil {
                await model.load()
            }
        }
    }

    // MARK: Hours

    private var hoursCard: some View {
        KXCard(showsInsetRing: true) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    Text("support.intro.eyebrow", bundle: .module)
                        .kxFont(.eyebrow)
                        .foregroundStyle(KXColor.accentText)
                    Text("support.intro.title", bundle: .module)
                        .kxFont(.title2)
                        .foregroundStyle(KXColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    availability(isOpen: model.config.supportHours.isOpen(at: context.date))
                    Text(SupportHoursText.text(for: model.config.supportHours, on: context.date, locale: locale))
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("support.hours")
                }
                .padding(KXSpacing.xs)
            }
        }
    }

    private func availability(isOpen: Bool) -> some View {
        HStack(spacing: KXSpacing.xs) {
            Circle()
                .fill(isOpen ? KXColor.success : KXColor.textTertiary)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(isOpen ? Self.openText : Self.closedText)
                .kxFont(.headline)
                .foregroundStyle(isOpen ? KXColor.success : KXColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("support.status")
    }

    private static var openText: String {
        String(localized: "support.status.open", bundle: .module)
    }

    private static var closedText: String {
        String(localized: "support.status.closed", bundle: .module)
    }

    // MARK: Channels

    private var channels: some View {
        let contact = model.contact
        return VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "support.channels.title", bundle: .module))
            if let orderName = model.orderName {
                Text("support.order.note \(orderName)", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: KXSpacing.s) {
                if let whatsApp = contact.whatsApp {
                    KXButton(
                        String(localized: "support.channel.whatsapp", bundle: .module),
                        systemImage: "message",
                        isFullWidth: true
                    ) {
                        openURL(whatsApp)
                    }
                    .accessibilityIdentifier("support.whatsapp")
                }
                if let email = contact.email {
                    KXButton(
                        String(localized: "support.channel.email", bundle: .module),
                        systemImage: "envelope",
                        style: contact.whatsApp == nil ? .primary : .secondary,
                        isFullWidth: true
                    ) {
                        openURL(email)
                    }
                    .accessibilityIdentifier("support.email")
                }
                if let liveChat = contact.liveChat {
                    KXButton(
                        String(localized: "support.channel.chat", bundle: .module),
                        systemImage: "bubble.left.and.bubble.right",
                        style: .secondary,
                        isFullWidth: true
                    ) {
                        openURL(liveChat)
                    }
                    .accessibilityIdentifier("support.chat")
                }
            }
            Text("support.email.address \(contact.emailAddress)", bundle: .module)
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textSecondary)
                .textSelection(.enabled)
        }
    }

    // MARK: Guides

    @ViewBuilder private var guides: some View {
        switch model.guides {
        case let .loaded(articles):
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                KXSectionHeader(
                    String(localized: "support.guides.title", bundle: .module),
                    eyebrow: String(localized: "support.guides.eyebrow", bundle: .module)
                )
                KXCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(articles) { article in
                            Button {
                                onRoute(.article(blogHandle: article.blogHandle, articleHandle: article.handle))
                            } label: {
                                SupportGuideRow(title: article.title)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("support.guide.\(article.handle)")
                            if article.id != articles.last?.id {
                                KXDivider()
                                    .padding(.leading, KXSpacing.m)
                            }
                        }
                    }
                }
            }
        case .idle, .loading:
            KXSkeleton(cornerRadius: KXRadius.card)
                .frame(height: 160)
        case .empty, .failed:
            EmptyView()
        }
    }
}

/// One guide in the list.
private struct SupportGuideRow: View {
    let title: String

    var body: some View {
        HStack(spacing: KXSpacing.m) {
            Image(systemName: "book")
                .kxFont(.body)
                .foregroundStyle(KXColor.brand)
                .accessibilityHidden(true)
            Text(title)
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .kxFont(.footnote)
                .foregroundStyle(KXColor.iconSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, KXSpacing.m)
        .padding(.vertical, KXSpacing.s)
        .frame(minHeight: KXSpacing.minimumTapTarget + KXSpacing.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

private struct PreviewGuides: ContentRepository {
    func articles(blogHandle: String, first: Int) async throws -> [ArticleSummary] {
        [
            ArticleSummary(
                id: ShopifyID("gid://shopify/Article/1"),
                handle: "office-2024-aktivieren",
                blogHandle: blogHandle,
                title: "Office 2024 aktivieren",
                excerpt: nil,
                publishedAt: Date(timeIntervalSince1970: 1_790_000_000),
                image: nil,
                onlineStoreUrl: nil
            ),
        ]
    }

    func article(blogHandle: String, handle: String) async throws -> Article? {
        nil
    }
}

#Preview("SupportScreen") {
    NavigationStack {
        SupportScreen(orderName: "#1042", backend: UnavailableBackendClient(), content: PreviewGuides(), onRoute: { _ in })
    }
}
