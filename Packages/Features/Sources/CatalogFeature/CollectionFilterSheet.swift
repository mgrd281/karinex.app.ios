import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - CollectionFilterSheet

/// The filters of a collection, built entirely from the filters the Storefront API returns
/// (Shopify Search & Discovery): one section per filter with its values and product counts, and
/// a price range with from and to fields for price filters.
///
/// The sheet edits a draft; "Ergebnisse anzeigen" applies it, "Zurücksetzen" clears it.
struct CollectionFilterSheet: View {
    let filters: [ProductFilter]
    let onApply: @MainActor (CollectionFilterSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CollectionFilterSelection
    @State private var minimumPrice: Decimal?
    @State private var maximumPrice: Decimal?

    /// Creates the sheet.
    ///
    /// - Parameters:
    ///   - filters: The filters of the collection.
    ///   - selection: The filters chosen so far.
    ///   - onApply: Called with the new selection.
    init(
        filters: [ProductFilter],
        selection: CollectionFilterSelection,
        onApply: @escaping @MainActor (CollectionFilterSelection) -> Void
    ) {
        self.filters = filters
        self.onApply = onApply
        _draft = State(initialValue: selection)
        _minimumPrice = State(initialValue: selection.priceRange?.minimum)
        _maximumPrice = State(initialValue: selection.priceRange?.maximum)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    if filters.isEmpty {
                        Text("catalog.filter.unavailable", bundle: .module)
                            .kxFont(.body)
                            .foregroundStyle(KXColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(filters) { filter in
                        filterSection(filter)
                    }
                }
                .padding(KXSpacing.gutter)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                applyBar
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("collection.filters")
            .kxScreenBackground()
            .navigationTitle(Text("catalog.filter.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("catalog.filter.cancel", bundle: .module)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        draft.removeAll()
                        minimumPrice = nil
                        maximumPrice = nil
                    } label: {
                        Text("catalog.filter.reset", bundle: .module)
                    }
                    .disabled(draft.isEmpty && minimumPrice == nil && maximumPrice == nil)
                    .accessibilityIdentifier("collection.filters.reset")
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Sections

    private func filterSection(_ filter: ProductFilter) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            Text(filter.label)
                .kxFont(.title3)
                .foregroundStyle(KXColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            KXCard(padding: 0) {
                if filter.isPriceRange {
                    priceFields(bounds: filter.values.first?.input.priceBounds)
                        .padding(KXSpacing.m)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filter.values) { value in
                            valueRow(value)
                            if value.id != filter.values.last?.id {
                                KXDivider()
                                    .padding(.leading, KXSpacing.m)
                            }
                        }
                    }
                }
            }
        }
    }

    private func valueRow(_ value: ProductFilterValue) -> some View {
        let isSelected = draft.contains(value)
        return Button {
            draft.toggle(value)
        } label: {
            HStack(spacing: KXSpacing.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .kxFont(.body)
                    .foregroundStyle(isSelected ? KXColor.brand : KXColor.iconSecondary)
                    .accessibilityHidden(true)
                Text(value.label)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value.count, format: .number)
                    .kxFont(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(KXColor.textSecondary)
            }
            .padding(.horizontal, KXSpacing.m)
            .padding(.vertical, KXSpacing.s)
            .frame(minHeight: KXSpacing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(value.count < 1 && !isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(value.label))
        .accessibilityValue(Text("catalog.filter.count \(value.count)", bundle: .module))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("collection.filter.\(value.id)")
    }

    private func priceFields(bounds: (minimum: Decimal?, maximum: Decimal?)?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: KXSpacing.m) {
                priceField(label: "catalog.filter.price.minimum", value: $minimumPrice, placeholder: bounds?.minimum)
                priceField(label: "catalog.filter.price.maximum", value: $maximumPrice, placeholder: bounds?.maximum)
            }
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                priceField(label: "catalog.filter.price.minimum", value: $minimumPrice, placeholder: bounds?.minimum)
                priceField(label: "catalog.filter.price.maximum", value: $maximumPrice, placeholder: bounds?.maximum)
            }
        }
    }

    private func priceField(label: LocalizedStringKey, value: Binding<Decimal?>, placeholder: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            Text(label, bundle: .module)
                .kxFont(.footnote)
                .foregroundStyle(KXColor.textSecondary)
            TextField(
                value: value,
                format: .number.precision(.fractionLength(0...2)),
                prompt: placeholder.map { Text($0, format: .number.precision(.fractionLength(0...2))) }
            ) {
                Text(label, bundle: .module)
            }
            .keyboardType(.decimalPad)
            .kxFont(.body)
            .padding(.horizontal, KXSpacing.s)
            .frame(minHeight: KXSpacing.minimumTapTarget)
            .background(KXColor.background, in: RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
                    .strokeBorder(KXColor.hairline, lineWidth: KXBorder.regular)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Apply

    private var applyBar: some View {
        VStack(spacing: 0) {
            KXDivider()
            KXButton(String(localized: "catalog.filter.apply", bundle: .module), isFullWidth: true) {
                var selection = draft
                selection.setPriceRange(minimum: minimumPrice, maximum: maximumPrice)
                onApply(selection)
                dismiss()
            }
            .accessibilityIdentifier("collection.filters.apply")
            .padding(.horizontal, KXSpacing.gutter)
            .padding(.vertical, KXSpacing.s)
        }
        .background(KXColor.background)
    }
}
