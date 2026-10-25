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

    /// Where each text lives in the store (docs/STORE_AUDIT.md): the Impressum and the
    /// Widerrufsbelehrung are pages, the others shop policies. Without the page the
    /// Widerrufsbelehrung falls back to the refund policy.
    static func text(for kind: LegalDocumentKind, from repository: any LegalContentRepository) async throws -> LegalText? {
        switch kind {
        case .imprint:
            guard let handle = kind.pageHandle else { return nil }
            return try await repository.page(handle: handle)
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
                ScrollView {
                    content(loaded)
                }
                .refreshable { await model.load() }
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

    private func content(_ loaded: LegalDocumentViewModel.LoadedText) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                Text(loaded.text.title)
                    .kxFont(.title1)
                    .foregroundStyle(KXColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let updatedAt = loaded.text.updatedAt {
                    let date = updatedAt.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))
                    Text("legal.updated \(date)", bundle: .module)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                }
            }
            KXDivider(.accent)
            RichTextView(document: loaded.document)
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.vertical, KXSpacing.m)
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
