import Foundation

/// Reusable GraphQL fragments of the Storefront operations.
///
/// Operation documents append exactly the fragments they use (the server rejects unused
/// fragments). All fragments were validated against the live Storefront API 2026-10 on
/// 2026-10-24.
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

    /// `FilterFields` on `Filter`: the fields of `ProductFilter`. `input` is Shopify's JSON
    /// text, sent back unchanged as `ProductFilterInput`.
    public static let filter = """
        fragment FilterFields on Filter {
          id
          label
          type
          values {
            id
            label
            count
            input
          }
        }
        """

    /// `CollectionSummaryFields` on `Collection`: the fields of `CollectionSummary`. Uses
    /// `ImageFields`.
    public static let collectionSummary = """
        fragment CollectionSummaryFields on Collection {
          id
          handle
          title
          description
          image {
            ...ImageFields
          }
        }
        """

    /// `ArticleSummaryFields` on `Article`: the fields of `ArticleSummary`. Uses `ImageFields`.
    public static let articleSummary = """
        fragment ArticleSummaryFields on Article {
          id
          handle
          title
          excerpt
          publishedAt
          onlineStoreUrl
          image {
            ...ImageFields
          }
          blog {
            handle
          }
        }
        """

    /// `CartDiscountApplicationFields` on `BaseCartDiscountApplication`: the fields of
    /// `CartDiscountApplication` (API 2026-10). Uses `MoneyFields`.
    public static let cartDiscountApplication = """
        fragment CartDiscountApplicationFields on BaseCartDiscountApplication {
          __typename
          targetType
          allocationMethod
          totalAllocatedAmount {
            ...MoneyFields
          }
          value {
            __typename
            ... on MoneyV2 {
              ...MoneyFields
            }
            ... on PricingPercentageValue {
              percentage
            }
          }
          ... on CartCodeDiscountApplication {
            code
          }
          ... on CartAutomaticDiscountApplication {
            title
          }
          ... on CartCustomDiscountApplication {
            title
          }
        }
        """

    /// `CartFields` on `Cart`: the fields of `Cart`, shared by the cart query and every cart
    /// mutation. Requests up to 100 lines, line-level discount allocations and the 2026-10
    /// `discountApplications`; the deprecated `cart.discountAllocations` and tax amounts are
    /// not requested. Uses `CartDiscountApplicationFields`, `ImageFields` and `MoneyFields`.
    public static let cart = """
        fragment CartFields on Cart {
          id
          checkoutUrl
          totalQuantity
          note
          buyerIdentity {
            countryCode
            email
          }
          attributes {
            key
            value
          }
          discountCodes {
            code
            applicable
          }
          discountApplications {
            ...CartDiscountApplicationFields
          }
          cost {
            subtotalAmount {
              ...MoneyFields
            }
            totalAmount {
              ...MoneyFields
            }
            checkoutChargeAmount {
              ...MoneyFields
            }
          }
          lines(first: 100) {
            nodes {
              id
              quantity
              merchandise {
                ... on ProductVariant {
                  id
                  title
                  sku
                  requiresShipping
                  availableForSale
                  image {
                    ...ImageFields
                  }
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
                  product {
                    id
                    handle
                    title
                    vendor
                  }
                }
              }
              cost {
                amountPerQuantity {
                  ...MoneyFields
                }
                compareAtAmountPerQuantity {
                  ...MoneyFields
                }
                subtotalAmount {
                  ...MoneyFields
                }
                totalAmount {
                  ...MoneyFields
                }
              }
              discountAllocations {
                discountedAmount {
                  ...MoneyFields
                }
              }
            }
          }
        }
        """

    /// The fragments a document using `CartFields` must append, in order.
    public static let cartDependencies = [cart, cartDiscountApplication, image, money]

    /// Assembles a complete document: the operation, a blank line, then every fragment
    /// separated by blank lines, ending with a newline.
    static func document(_ operation: String, fragments: [String]) -> String {
        ([operation] + fragments).joined(separator: "\n\n") + "\n"
    }
}
