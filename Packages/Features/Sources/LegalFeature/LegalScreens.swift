import CommerceUI
import DesignSystem
import Foundation
import Observation
import ShopifyKit
import SwiftUI

// MARK: - LegalListScreen

/// "Rechtliches": Impressum, AGB, Datenschutz, Widerrufsbelehrung and Versand, each loaded from
/// Shopify and rendered natively. Reachable from the Konto tab and the settings, so every text
/// is at most two taps away (PROMPT.md 9).
public struct LegalListScreen: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void

    /// Creates the list.
    public init(onRoute: @escaping @MainActor (CommerceRoute) -> Void) {
        self.onRoute = onRoute
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.l) {
                KXCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(LegalDocumentKind.allCases) { kind in
                            Button {
                                onRoute(.account(.legalDocument(kind)))
                            } label: {
                                LegalRow(kind: kind)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("legal.list.hint", bundle: .module))
                            .accessibilityIdentifier("legal.document.\(kind.rawValue)")
                            if kind != LegalDocumentKind.allCases.last {
                                KXDivider()
                                    .padding(.leading, KXSpacing.m)
                            }
                        }
                    }
                }
                Text("legal.footnote", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.m)
            .kxReadableWidth()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.legal")
        .kxScreenBackground()
        .navigationTitle(Text("legal.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
    }
}

/// One row of the list.
private struct LegalRow: View {
    let kind: LegalDocumentKind

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: KXSpacing.m) {
            Image(systemName: kind.systemImage)
                .kxFont(.body)
                .foregroundStyle(KXColor.brand)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(kind.title)
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .kxFont(.footnote)
                .foregroundStyle(KXColor.iconSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, KXSpacing.m)
        .frame(minHeight: KXSpacing.minimumTapTarget + KXSpacing.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - LegalDocumentViewModel

/// Loads one legal text in the buyer's language.
@MainActor
@Observable
final class LegalDocumentViewModel {
    /// A loaded text with its parsed body.
    struct LoadedText: Sendable, Hashable {
        let text: LegalText
        let document: HTMLDocument
    }

    /// The text.
    let kind: LegalDocumentKind
    /// The load state.
    private(set) var state: LoadState<LoadedText> = .idle

    @ObservationIgnored private let repository: any LegalContentRepository

    init(kind: LegalDocumentKind, repository: any LegalContentRepository) {
        self.kind = kind
        self.repository = repository
    }

    /// Loads the text; a reload that fails keeps the text on screen.
    func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            guard let text = try await Self.text(for: kind, from: repository) else {
                state = .empty
                return
            }
            let html = text.body
            let document = await Task.detached(priority: .userInitiated) { HTMLDocument(html: html) }.value
            state = document.isEmpty ? .empty : .loaded(LoadedText(text: text, document: document))
        } catch {
            if let failure = UserFacingError(error), state.value == nil {
                state = .failed(failure)
            }
        }
    }

    /// Where each text lives in the store (docs/STORE_AUDIT.md): the Impressum is the shop's
    /// legal notice policy, else the page `rechtliche-hinweise`, else `impressum`; the
    /// Widerrufsbelehrung is a page that falls back to the refund policy; the others are shop
    /// policies.
    static func text(for kind: LegalDocumentKind, from repository: any LegalContentRepository) async throws -> LegalText? {
        switch kind {
        case .imprint:
            if let notice = try await repository.policies().legalNotice, !notice.body.isEmpty {
                return notice
            }
            for handle in [kind.pageHandle, "impressum"].compactMap(\.self) {
                if let page = try await repository.page(handle: handle) {
                    return page
                }
            }
            return nil
        case .withdrawal:
            if let handle = kind.pageHandle, let page = try await repository.page(handle: handle) {
                return page
            }
            return try await repository.policies().refundPolicy
        case .terms:
            return try await repository.policies().termsOfService
        case .privacy:
            return try await repository.policies().privacyPolicy
        case .shipping:
            return try await repository.policies().shippingPolicy
        }
    }
}

// MARK: - LegalDocumentScreen

/// One legal text, rendered natively with its "Stand" date when Shopify has one.
public struct LegalDocumentScreen: View {
    @State private var model: LegalDocumentViewModel

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var heroSide: CGFloat = 56

    /// Creates the screen.
    public init(kind: LegalDocumentKind, repository: any LegalContentRepository) {
        _model = State(initialValue: LegalDocumentViewModel(kind: kind, repository: repository))
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            empty: AsyncContentEmptyState(
                systemImage: "doc.text.magnifyingglass",
                title: String(localized: "legal.empty.title", bundle: .module),
                message: String(localized: "legal.empty.message", bundle: .module)
            ),
            retry: { await model.load() },
            content: { loaded in
                ScrollViewReader { proxy in
                    ScrollView {
                        content(loaded, proxy: proxy)
                    }
                    .refreshable { await model.load() }
                }
            },
            placeholder: {
                AsyncContentSkeleton()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.legalDocument")
        .kxScreenBackground()
        .navigationTitle(model.state.value?.text.title ?? model.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
    }

    /// The text like on karinex.de: a header with the title and "Zuletzt aktualisiert", a table
    /// of contents that scrolls to each section, and one panel per section.
    private func content(_ loaded: LegalDocumentViewModel.LoadedText, proxy: ScrollViewProxy) -> some View {
        let outline = LegalOutline.split(loaded.document.blocks, title: loaded.text.title)
        return VStack(alignment: .leading, spacing: KXSpacing.l) {
            header(loaded)
            if outline.sections.count >= 3 {
                tableOfContents(outline.sections, proxy: proxy)
            }
            if !outline.intro.isEmpty {
                RichTextView(document: HTMLDocument(blocks: outline.intro))
            }
            ForEach(outline.sections) { section in
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    Text(verbatim: section.title)
                        .kxFont(.title3)
                        .foregroundStyle(KXColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if !section.blocks.isEmpty {
                        RichTextView(document: HTMLDocument(blocks: section.blocks))
                    }
                }
                .padding(KXSpacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                .id(section.id)
            }
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.vertical, KXSpacing.m)
        .kxReadableWidth()
    }

    private func header(_ loaded: LegalDocumentViewModel.LoadedText) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            Image(systemName: model.kind.systemImage)
                .kxFont(.title2)
                .foregroundStyle(KXColor.background)
                .frame(width: heroSide, height: heroSide)
                .background(KXColor.textPrimary, in: Circle())
                .accessibilityHidden(true)
            Text(loaded.text.title)
                .kxFont(.title1)
                .foregroundStyle(KXColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let updatedAt = loaded.text.updatedAt {
                let date = updatedAt.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))
                Label {
                    Text("legal.updated \(date)", bundle: .module)
                } icon: {
                    Image(systemName: "clock")
                }
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textSecondary)
            }
            KXDivider()
        }
    }

    private func tableOfContents(_ sections: [LegalSection], proxy: ScrollViewProxy) -> some View {
        KXListGroup(Text("legal.toc", bundle: .module)) {
            ForEach(sections) { section in
                if section.id > 0 {
                    KXDivider()
                        .padding(.leading, KXSpacing.m)
                }
                Button {
                    withAnimation(KXMotion.animation(.snappy, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(section.id, anchor: .top)
                    }
                } label: {
                    HStack(spacing: KXSpacing.m) {
                        Text(verbatim: section.title)
                            .kxFont(.body)
                            .foregroundStyle(KXColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.down")
                            .kxFont(.footnote)
                            .foregroundStyle(KXColor.iconSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, KXSpacing.m)
                    .padding(.vertical, KXSpacing.s)
                    .frame(minHeight: KXSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Previews

private struct PreviewLegalRepository: LegalContentRepository {
    func policies() async throws -> ShopPolicies {
        ShopPolicies(privacyPolicy: nil, refundPolicy: nil, shippingPolicy: nil, termsOfService: nil)
    }

    func page(handle: String) async throws -> LegalText? {
        LegalText(
            id: ShopifyID("gid://shopify/Page/1"),
            title: "Impressum",
            handle: handle,
            body: "<p>KARINEX, Hamburg</p>",
            updatedAt: Date(timeIntervalSince1970: 1_790_000_000),
            url: nil
        )
    }
}

#Preview("LegalListScreen") {
    NavigationStack {
        LegalListScreen(onRoute: { _ in })
    }
}

#Preview("LegalDocumentScreen") {
    NavigationStack {
        LegalDocumentScreen(kind: .imprint, repository: PreviewLegalRepository())
    }
}
