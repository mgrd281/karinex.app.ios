import DesignSystem
import SwiftUI

// MARK: - MarketChoice

/// One option of a ``MarketChoiceSheet``: a country with its flag and currency, or a language.
struct MarketChoice<ID: Hashable>: Identifiable {
    let id: ID
    /// The flag emoji, `nil` for languages.
    let flag: String?
    /// The localized name, e.g. "Deutschland".
    let name: String
    /// A quiet detail on the trailing side, e.g. "EUR".
    let detail: String?
}

// MARK: - MarketChoiceSheet

/// The list that opens from a row of "Ihr Shop-Land": a sheet from the bottom with a bold title,
/// a close button, full-width rows with hairline dividers and a checkmark on the chosen one, in
/// the style of fashion retail apps. Long lists get a search field. A tap chooses and closes.
struct MarketChoiceSheet<ID: Hashable>: View {
    let title: Text
    let choices: [MarketChoice<ID>]
    @Binding var selection: ID

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// Lists with more entries than this get a search field.
    static var searchThreshold: Int {
        8
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if choices.count > Self.searchThreshold {
                searchField
            }
            KXDivider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { choice in
                        row(choice)
                        KXDivider()
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(KXColor.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(KXRadius.large)
    }

    private var filtered: [MarketChoice<ID>] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return choices }
        return choices.filter { $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: KXSpacing.m) {
            title
                .kxFont(.title3)
                .foregroundStyle(KXColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                    .frame(width: KXSpacing.minimumTapTarget, height: KXSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("commerce.market.close", bundle: .module))
        }
        .padding(.leading, KXSpacing.gutter)
        .padding(.trailing, KXSpacing.s)
        .padding(.top, KXSpacing.l)
        .padding(.bottom, KXSpacing.s)
    }

    private var searchField: some View {
        HStack(spacing: KXSpacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(KXColor.iconSecondary)
                .accessibilityHidden(true)
            TextField(text: $query) {
                Text("commerce.market.search", bundle: .module)
            }
            .kxFont(.body)
            .autocorrectionDisabled()
            .submitLabel(.search)
        }
        .padding(.horizontal, KXSpacing.m)
        .frame(minHeight: KXSpacing.minimumTapTarget)
        .background(KXColor.surface, in: Capsule())
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.bottom, KXSpacing.m)
    }

    private func row(_ choice: MarketChoice<ID>) -> some View {
        let isSelected = choice.id == selection
        return Button {
            selection = choice.id
            KXHaptics.selection()
            dismiss()
        } label: {
            HStack(spacing: KXSpacing.m) {
                if let flag = choice.flag {
                    Text(verbatim: flag)
                        .kxFont(.title3)
                        .accessibilityHidden(true)
                }
                Text(verbatim: choice.name)
                    .kxFont(isSelected ? .headline : .body)
                    .foregroundStyle(KXColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail = choice.detail {
                    Text(verbatim: detail)
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                }
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textPrimary)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, KXSpacing.gutter)
            .frame(minHeight: KXSpacing.minimumTapTarget + KXSpacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
