import Foundation

/// Reusable GraphQL fragments of the Storefront operations.
///
/// Operation documents append exactly the fragments they use (the server rejects unused
/// fragments). All fragments were validated against the live Storefront API 2026-07 on
/// 2026-09-26.
public enum StorefrontFragments {
    /// `ImageFields` on `Image`: the fields of `ShopifyImage`.
    public static let image = """
        fragment ImageFields on Image {
          url
          altText
          width
          height
        }
        """

    /// `MoneyFields` on `MoneyV2`: the fields of `MoneyV2`.
    public static let money = """
        fragment MoneyFields on MoneyV2 {
          amount
          currencyCode
        }
        """

    /// `LanguageFields` on `Language`.
    public static let language = """
        fragment LanguageFields on Language {
          isoCode
          name
          endonymName
        }
        """

    /// `CountryFields` on `Country`; uses `LanguageFields`.
    public static let country = """
        fragment CountryFields on Country {
          isoCode
          name
          currency {
            isoCode
            name
            symbol
          }
          availableLanguages {
            ...LanguageFields
          }
        }
        """

    /// `ProductSummaryFields` on `Product`: the fields of `ProductSummary`, including
    /// `requiresShipping` of the first variant. Uses `ImageFields` and `MoneyFields`.
    public static let productSummary = """
        fragment ProductSummaryFields on Product {
          id
          handle
          title
          vendor
          availableForSale
          featuredImage {
            ...ImageFields
          }
          priceRange {
            minVariantPrice {
              ...MoneyFields
            }
            maxVariantPrice {
              ...MoneyFields
            }
          }
          compareAtPriceRange {
            minVariantPrice {
              ...MoneyFields
            }
            maxVariantPrice {
              ...MoneyFields
            }
          }
          variants(first: 1) {
            nodes {
              requiresShipping
            }
          }
        }
        """

    /// `ProductDetail` on `Product`: everything the product screen needs. Metafields are
    /// only selected when `$includeMetafields` is true, because tokenless requests are denied
    /// access to them. Uses `ImageFields` and `MoneyFields` and the operation variables
    /// `$includeMetafields` and `$metafieldIdentifiers`.
    public static let productDetail = """
        fragment ProductDetail on Product {
          id
          handle
          title
          vendor
          productType
          tags
          availableForSale
          descriptionHtml
          onlineStoreUrl
          featuredImage {
            ...ImageFields
          }
          images(first: 8) {
            nodes {
              ...ImageFields
            }
          }
          options {
            id
            name
            optionValues {
              id
              name
            }
          }
          variants(first: 20) {
            nodes {
              id
              title
              sku
              availableForSale
              requiresShipping
              price {
                ...MoneyFields
              }
              compareAtPrice {
                ...MoneyFields
              }
              selectedOptions {
                name
                value
              }
              image {
                ...ImageFields
              }
            }
          }
          seo {
            title
            description
          }
          collections(first: 5) {
            nodes {
              id
              handle
              title
            }
          }
          priceRange {
            minVariantPrice {
              ...MoneyFields
            }
            maxVariantPrice {
              ...MoneyFields
            }
          }
          compareAtPriceRange {
            minVariantPrice {
              ...MoneyFields
            }
            maxVariantPrice {
              ...MoneyFields
            }
          }
          metafields(identifiers: $metafieldIdentifiers) @include(if: $includeMetafields) {
            namespace
            key
            type
            value
          }
        }
        """
}
