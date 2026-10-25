import Foundation

// MARK: - SEO

/// Search engine title and description of a resource (Storefront `SEO`).
public struct SEO: Sendable, Hashable, Codable {
    /// The SEO title, if set.
    public let title: String?
    /// The SEO description, if set.
    public let description: String?

    /// Creates an SEO value.
    public init(title: String?, description: String?) {
        self.title = title
        self.description = description
    }
}

// MARK: - Options

/// A product option such as "Edition" with its values (Storefront `ProductOption`).
///
/// Products without real options have a single option `Title` with the value `Default Title`.
public struct ProductOption: Sendable, Hashable, Codable {
    /// The option's GID, if requested.
    public let id: ShopifyID?
    /// The option name, e.g. `Title`.
    public let name: String
    /// The option's values in merchant order.
    public let optionValues: [ProductOptionValue]

    /// Creates an option.
    public init(id: ShopifyID?, name: String, optionValues: [ProductOptionValue]) {
        self.id = id
        self.name = name
        self.optionValues = optionValues
    }

    /// Whether this is Shopify's placeholder option of products without variants to choose
    /// from (`Title` / `Default Title`), which the UI hides.
    public var isDefaultPlaceholder: Bool {
        name == "Title" && optionValues.count == 1 && optionValues.first?.name == "Default Title"
    }
}

/// One value of a product option (Storefront `ProductOptionValue`).
public struct ProductOptionValue: Sendable, Hashable, Codable {
    /// The value's GID, if requested.
    public let id: ShopifyID?
    /// The value, e.g. `Default Title`.
    public let name: String

    /// Creates an option value.
    public init(id: ShopifyID?, name: String) {
        self.id = id
        self.name = name
    }
}

/// The option value a variant has for one option (Storefront `SelectedOption`).
public struct SelectedOption: Sendable, Hashable, Codable {
    /// The option name, e.g. `Title`.
    public let name: String
    /// The value, e.g. `Default Title`.
    public let value: String

    /// Creates a selected option.
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

// MARK: - ProductVariant

/// A purchasable variant of a product (Storefront `ProductVariant`).
public struct ProductVariant: Sendable, Hashable, Codable, Identifiable {
    /// The variant GID, used as `merchandiseId` in cart lines.
    public let id: ShopifyID
    /// The variant title, `Default Title` for single-variant products.
    public let title: String
    /// The SKU, if set.
    public let sku: String?
    /// Whether the variant can be bought.
    public let availableForSale: Bool
    /// Whether the variant is a physical good. License keys (ESD) are `false`.
    public let requiresShipping: Bool
    /// The price in the context's market.
    public let price: MoneyV2
    /// The compare-at price, if the merchant set one.
    public let compareAtPrice: MoneyV2?
    /// The option values of this variant.
    public let selectedOptions: [SelectedOption]
    /// The variant image, if any.
    public let image: ShopifyImage?

    /// Creates a variant.
    public init(
        id: ShopifyID,
        title: String,
        sku: String?,
        availableForSale: Bool,
        requiresShipping: Bool,
        price: MoneyV2,
        compareAtPrice: MoneyV2?,
        selectedOptions: [SelectedOption],
        image: ShopifyImage?
    ) {
        self.id = id
        self.title = title
        self.sku = sku
        self.availableForSale = availableForSale
        self.requiresShipping = requiresShipping
        self.price = price
        self.compareAtPrice = compareAtPrice
        self.selectedOptions = selectedOptions
        self.image = image
    }

    /// Whether the compare-at price is higher than the price, so a reduction can be shown.
    public var isDiscounted: Bool {
        guard let compareAtPrice, compareAtPrice.currencyCode == price.currencyCode else { return false }
        return compareAtPrice.amount > price.amount
    }
}

// MARK: - PriceRange

/// The lowest and highest variant price (Storefront `ProductPriceRange`).
///
/// For `compareAtPriceRange`, Shopify reports `0.0` amounts when no variant has a compare-at
/// price.
public struct PriceRange: Sendable, Hashable, Codable {
    /// The lowest variant price.
    public let minVariantPrice: MoneyV2
    /// The highest variant price.
    public let maxVariantPrice: MoneyV2

    /// Creates a price range.
    public init(minVariantPrice: MoneyV2, maxVariantPrice: MoneyV2) {
        self.minVariantPrice = minVariantPrice
        self.maxVariantPrice = maxVariantPrice
    }

    /// Whether all variants cost the same.
    public var isSinglePrice: Bool {
        minVariantPrice == maxVariantPrice
    }

    /// Whether both bounds are zero (no compare-at price at all).
    public var isZero: Bool {
        minVariantPrice.isZero && maxVariantPrice.isZero
    }
}

// MARK: - CollectionReference

/// A collection a product belongs to, as listed on the product.
public struct CollectionReference: Sendable, Hashable, Codable, Identifiable {
    /// The collection GID.
    public let id: ShopifyID
    /// The collection handle, e.g. `bestseller`.
    public let handle: String
    /// The collection title in the context language.
    public let title: String

    /// Creates a collection reference.
    public init(id: ShopifyID, handle: String, title: String) {
        self.id = id
        self.handle = handle
        self.title = title
    }
}

// MARK: - Product

/// Everything the product screen shows (Storefront `Product` via the `ProductDetail` fragment).
///
/// All values are store content in the context's language and market and are displayed as
/// returned. Nothing product-related is hardcoded in the app.
public struct Product: Sendable, Hashable, Codable, Identifiable {
    /// The product GID.
    public let id: ShopifyID
    /// The URL handle, e.g. `office-2024-professional-plus-key`.
    public let handle: String
    /// The title in the context language.
    public let title: String
    /// The vendor, e.g. `Microsoft`.
    public let vendor: String
    /// The product type.
    public let productType: String
    /// The merchant's tags (not localized).
    public let tags: [String]
    /// Whether at least one variant can be bought.
    public let availableForSale: Bool
    /// The description as HTML, rendered natively by the product screen.
    public let descriptionHtml: String
    /// The main image, if any.
    public let featuredImage: ShopifyImage?
    /// Up to 8 images.
    public let images: [ShopifyImage]
    /// The product options.
    public let options: [ProductOption]
    /// Up to 20 variants.
    public let variants: [ProductVariant]
    /// SEO title and description.
    public let seo: SEO
    /// Up to 5 collections the product belongs to.
    public let collections: [CollectionReference]
    /// The variant price range.
    public let priceRange: PriceRange
    /// The variant compare-at price range (zero when there is none).
    public let compareAtPriceRange: PriceRange
    /// The product page on the web shop, if published there.
    public let onlineStoreUrl: URL?
    /// The requested metafields that exist on the product. Empty in tokenless mode, where
    /// metafields are not requested.
    public let metafields: [Metafield]

    /// Creates a product.
    public init(
        id: ShopifyID,
        handle: String,
        title: String,
        vendor: String,
        productType: String,
        tags: [String],
        availableForSale: Bool,
        descriptionHtml: String,
        featuredImage: ShopifyImage?,
        images: [ShopifyImage],
        options: [ProductOption],
        variants: [ProductVariant],
        seo: SEO,
        collections: [CollectionReference],
        priceRange: PriceRange,
        compareAtPriceRange: PriceRange,
        onlineStoreUrl: URL?,
        metafields: [Metafield]
    ) {
        self.id = id
        self.handle = handle
        self.title = title
        self.vendor = vendor
        self.productType = productType
        self.tags = tags
        self.availableForSale = availableForSale
        self.descriptionHtml = descriptionHtml
        self.featuredImage = featuredImage
        self.images = images
        self.options = options
        self.variants = variants
        self.seo = seo
        self.collections = collections
        self.priceRange = priceRange
        self.compareAtPriceRange = compareAtPriceRange
        self.onlineStoreUrl = onlineStoreUrl
        self.metafields = metafields
    }

    // MARK: Derived values

    /// Typed access to the product's metafields.
    public var productMetafields: ProductMetafields {
        ProductMetafields(metafields)
    }

    /// The variant to preselect: the first one available for sale, else the first one.
    public var defaultVariant: ProductVariant? {
        variants.first(where: \.availableForSale) ?? variants.first
    }

    /// Whether every variant is digital (no shipping), as for license keys.
    public var isDigitalOnly: Bool {
        !variants.isEmpty && variants.allSatisfy { !$0.requiresShipping }
    }

    /// The options a customer actually chooses from (without Shopify's `Default Title` placeholder).
    public var selectableOptions: [ProductOption] {
        options.filter { !$0.isDefaultPlaceholder }
    }

    /// Returns the variant whose selected options match `selection` (option name to value).
    public func variant(matching selection: [String: String]) -> ProductVariant? {
        variants.first { variant in
            variant.selectedOptions.allSatisfy { option in selection[option.name].map { $0 == option.value } ?? true }
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, handle, title, vendor, productType, tags, availableForSale, descriptionHtml, featuredImage
        case images, options, variants, seo, collections, priceRange, compareAtPriceRange, onlineStoreUrl, metafields
    }

    /// Decodes the Storefront shape: `images`, `variants` and `collections` as `{nodes: [...]}`,
    /// `metafields` as a nullable array whose `null` entries (missing metafields) are dropped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        handle = try container.decode(String.self, forKey: .handle)
        title = try container.decode(String.self, forKey: .title)
        vendor = try container.decode(String.self, forKey: .vendor)
        productType = try container.decode(String.self, forKey: .productType)
        tags = try container.decode([String].self, forKey: .tags)
        availableForSale = try container.decode(Bool.self, forKey: .availableForSale)
        descriptionHtml = try container.decode(String.self, forKey: .descriptionHtml)
        featuredImage = try container.decodeIfPresent(ShopifyImage.self, forKey: .featuredImage)
        images = try container.decode(Connection<ShopifyImage>.self, forKey: .images).nodes
        options = try container.decode([ProductOption].self, forKey: .options)
        variants = try container.decode(Connection<ProductVariant>.self, forKey: .variants).nodes
        seo = try container.decode(SEO.self, forKey: .seo)
        collections = try container.decode(Connection<CollectionReference>.self, forKey: .collections).nodes
        priceRange = try container.decode(PriceRange.self, forKey: .priceRange)
        compareAtPriceRange = try container.decode(PriceRange.self, forKey: .compareAtPriceRange)
        onlineStoreUrl = try container.decodeIfPresent(URL.self, forKey: .onlineStoreUrl)
        metafields = try container.decodeIfPresent([Metafield?].self, forKey: .metafields)?.compactMap(\.self) ?? []
    }

    /// Encodes the same shape `init(from:)` reads, so cached products decode again.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(handle, forKey: .handle)
        try container.encode(title, forKey: .title)
        try container.encode(vendor, forKey: .vendor)
        try container.encode(productType, forKey: .productType)
        try container.encode(tags, forKey: .tags)
        try container.encode(availableForSale, forKey: .availableForSale)
        try container.encode(descriptionHtml, forKey: .descriptionHtml)
        try container.encodeIfPresent(featuredImage, forKey: .featuredImage)
        try container.encode(Connection(nodes: images), forKey: .images)
        try container.encode(options, forKey: .options)
        try container.encode(Connection(nodes: variants), forKey: .variants)
        try container.encode(seo, forKey: .seo)
        try container.encode(Connection(nodes: collections), forKey: .collections)
        try container.encode(priceRange, forKey: .priceRange)
        try container.encode(compareAtPriceRange, forKey: .compareAtPriceRange)
        try container.encodeIfPresent(onlineStoreUrl, forKey: .onlineStoreUrl)
        try container.encode(metafields, forKey: .metafields)
    }
}
