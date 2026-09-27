import Foundation

// MARK: - ProductSummary

/// The compact product shown in lists and cards (Storefront `Product` via the
/// `ProductSummaryFields` fragment).
public struct ProductSummary: Sendable, Hashable, Codable, Identifiable {
    /// The product GID.
    public let id: ShopifyID
    /// The URL handle, used to open the product screen.
    public let handle: String
    /// The title in the context language.
    public let title: String
    /// The vendor.
    public let vendor: String
    /// Whether at least one variant can be bought.
    public let availableForSale: Bool
    /// The main image, if any.
    public let featuredImage: ShopifyImage?
    /// The variant price range.
    public let priceRange: PriceRange
    /// The variant compare-at price range (zero when there is none).
    public let compareAtPriceRange: PriceRange
    /// Whether the first variant needs shipping (`false` for license keys), or `nil` if the
    /// product has no variant.
    public let requiresShipping: Bool?

    /// Creates a product summary.
    public init(
        id: ShopifyID,
        handle: String,
        title: String,
        vendor: String,
        availableForSale: Bool,
        featuredImage: ShopifyImage?,
        priceRange: PriceRange,
        compareAtPriceRange: PriceRange,
        requiresShipping: Bool?
    ) {
        self.id = id
        self.handle = handle
        self.title = title
        self.vendor = vendor
        self.availableForSale = availableForSale
        self.featuredImage = featuredImage
        self.priceRange = priceRange
        self.compareAtPriceRange = compareAtPriceRange
        self.requiresShipping = requiresShipping
    }

    /// The lowest price, shown as "ab" price for multi-variant products.
    public var price: MoneyV2 {
        priceRange.minVariantPrice
    }

    /// The lowest compare-at price when it is higher than the lowest price, else `nil`.
    /// Exact for single-variant products, which is every license key product.
    public var compareAtPrice: MoneyV2? {
        let compareAt = compareAtPriceRange.minVariantPrice
        guard compareAt.currencyCode == price.currencyCode, compareAt.amount > price.amount else { return nil }
        return compareAt
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, handle, title, vendor, availableForSale, featuredImage, priceRange, compareAtPriceRange, variants
    }

    private struct VariantShipping: Codable {
        let requiresShipping: Bool
    }

    /// Decodes the Storefront shape, reading `requiresShipping` from `variants(first: 1)`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        handle = try container.decode(String.self, forKey: .handle)
        title = try container.decode(String.self, forKey: .title)
        vendor = try container.decode(String.self, forKey: .vendor)
        availableForSale = try container.decode(Bool.self, forKey: .availableForSale)
        featuredImage = try container.decodeIfPresent(ShopifyImage.self, forKey: .featuredImage)
        priceRange = try container.decode(PriceRange.self, forKey: .priceRange)
        compareAtPriceRange = try container.decode(PriceRange.self, forKey: .compareAtPriceRange)
        requiresShipping = try container
            .decodeIfPresent(Connection<VariantShipping>.self, forKey: .variants)?
            .nodes.first?.requiresShipping
    }

    /// Encodes the same shape `init(from:)` reads.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(handle, forKey: .handle)
        try container.encode(title, forKey: .title)
        try container.encode(vendor, forKey: .vendor)
        try container.encode(availableForSale, forKey: .availableForSale)
        try container.encodeIfPresent(featuredImage, forKey: .featuredImage)
        try container.encode(priceRange, forKey: .priceRange)
        try container.encode(compareAtPriceRange, forKey: .compareAtPriceRange)
        let variants = requiresShipping.map { [VariantShipping(requiresShipping: $0)] } ?? []
        try container.encode(Connection(nodes: variants), forKey: .variants)
    }
}

// MARK: - CollectionSummary

/// The descriptive part of a collection: identity, texts and image.
public struct CollectionSummary: Sendable, Hashable, Codable, Identifiable {
    /// The collection GID.
    public let id: ShopifyID
    /// The URL handle, e.g. `bestseller`.
    public let handle: String
    /// The title in the context language.
    public let title: String
    /// The plain text description.
    public let description: String
    /// The collection image, if any.
    public let image: ShopifyImage?

    /// Creates a collection summary.
    public init(id: ShopifyID, handle: String, title: String, description: String, image: ShopifyImage?) {
        self.id = id
        self.handle = handle
        self.title = title
        self.description = description
        self.image = image
    }
}

// MARK: - ProductCollection

/// A collection with one page of its products (Storefront `Collection`).
///
/// Named `ProductCollection` rather than `Collection` so it never shadows the standard
/// library's `Collection` protocol in modules that import ShopifyKit.
public struct ProductCollection: Sendable, Hashable, Codable, Identifiable {
    /// The collection GID.
    public let id: ShopifyID
    /// The URL handle, e.g. `bestseller`.
    public let handle: String
    /// The title in the context language.
    public let title: String
    /// The plain text description.
    public let description: String
    /// The collection image, if any.
    public let image: ShopifyImage?
    /// One page of products with its pagination state.
    public let products: Connection<ProductSummary>

    /// Creates a collection.
    public init(
        id: ShopifyID,
        handle: String,
        title: String,
        description: String,
        image: ShopifyImage?,
        products: Connection<ProductSummary>
    ) {
        self.id = id
        self.handle = handle
        self.title = title
        self.description = description
        self.image = image
        self.products = products
    }

    /// The collection without its products.
    public var summary: CollectionSummary {
        CollectionSummary(id: id, handle: handle, title: title, description: description, image: image)
    }
}
