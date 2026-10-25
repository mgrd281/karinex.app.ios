import Foundation
import ShopifyKit

// MARK: - CollectionFilterSelection

/// The filter values a customer chose for a collection, kept as Shopify's own filter inputs so
/// they go back to the Storefront API unchanged.
///
/// List and boolean values are toggled one by one. A price range is a single input built with
/// `ProductFilterInput.price(minimum:maximum:)`; setting a new range replaces the old one.
struct CollectionFilterSelection: Sendable, Hashable {
    /// The chosen inputs, in the order they were chosen.
    private(set) var inputs: [ProductFilterInput]

    /// Creates a selection.
    init(inputs: [ProductFilterInput] = []) {
        var unique: [ProductFilterInput] = []
        for input in inputs where !unique.contains(input) {
            unique.append(input)
        }
        self.inputs = unique
    }

    /// No filter chosen.
    static let none = CollectionFilterSelection()

    /// The number of active filters, shown on the filter button.
    var count: Int {
        inputs.count
    }

    /// Whether no filter is chosen.
    var isEmpty: Bool {
        inputs.isEmpty
    }

    /// Whether `value` is chosen.
    func contains(_ value: ProductFilterValue) -> Bool {
        inputs.contains(value.input)
    }

    /// Chooses `value`, or removes it when it is already chosen.
    mutating func toggle(_ value: ProductFilterValue) {
        if let index = inputs.firstIndex(of: value.input) {
            inputs.remove(at: index)
        } else {
            inputs.append(value.input)
        }
    }

    /// The chosen price range, or `nil` without one.
    var priceRange: (minimum: Decimal?, maximum: Decimal?)? {
        inputs.lazy.compactMap(\.priceBounds).first
    }

    /// Sets the price range. Without any bound the price filter is removed. Bounds in the wrong
    /// order are swapped; negative bounds are ignored.
    mutating func setPriceRange(minimum: Decimal?, maximum: Decimal?) {
        inputs.removeAll { $0.priceBounds != nil }
        var lower = minimum.flatMap { $0 >= 0 ? $0 : nil }
        var upper = maximum.flatMap { $0 >= 0 ? $0 : nil }
        if let low = lower, let high = upper, low > high {
            lower = high
            upper = low
        }
        guard lower != nil || upper != nil else { return }
        inputs.append(.price(minimum: lower, maximum: upper))
    }

    /// Removes every filter.
    mutating func removeAll() {
        inputs.removeAll()
    }
}
