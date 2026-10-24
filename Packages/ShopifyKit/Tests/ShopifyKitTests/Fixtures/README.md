# ShopifyKit test fixtures

Raw response bodies of the live KARINEX Storefront API, used by `ShopifyKitTests` to decode
real data through the real `GraphQLClient` (with a stub transport).

| Property | Value |
| --- | --- |
| Store | `45dv93-bk.myshopify.com` (web: `www.karinex.de`) |
| API | Storefront API `2026-10`, `https://45dv93-bk.myshopify.com/api/2026-10/graphql.json` |
| Access | tokenless (no `X-Shopify-Storefront-Access-Token`) |
| Recorded | 2026-10-24 (exact timestamp per file in `manifest.json`) |
| Recorder | `Tools/FixtureRecorder` (`swift run fixture-recorder`) |
| Consent | every live call carried `visitorConsent: {analytics: false, preferences: true, marketing: false, saleOfData: false}` |

Every file is the exact body Shopify returned for the final HTTP attempt, re-serialized
deterministically: two-space indentation, keys sorted, `[]`/`{}` for empty containers,
slashes and non-ASCII characters unescaped, trailing newline.

## Anonymization

The recorder runs `FixtureAnonymizer` over every body and over the variables in
`manifest.json` before anything is written. It keeps the shape of every value and replaces
only secrets with `REDACTED`:

- cart IDs: `gid://shopify/Cart/REDACTED?key=REDACTED` (also as warning targets and inside
  messages),
- cart line IDs keep their line UUID, the cart token in their query is replaced:
  `gid://shopify/CartLine/<uuid>?cart=REDACTED`,
- checkout URLs: `https://www.karinex.de/cart/c/REDACTED?key=REDACTED&_cs=REDACTED`,
- checkout, customer and address GIDs and personal fields (`email`, names, address
  lines, `phone`, ...) the same way. The fixtures contain no customer data.

`anonymizedPaths` in `manifest.json` lists every changed value per fixture.

## Files

| File | Operation | Context | What it shows |
| --- | --- | --- | --- |
| `localization_DE_DE.json` | `Localization` (query) | DE / DE | 28 countries with currency (EUR, CHF, CZK, DKK, HUF, PLN, RON, SEK) and content languages; 13 languages for DE; the Netherlands only offer `NL`. |
| `product_office-2024-professional-plus-key_DE_DE.json` | `ProductByHandle` (query), `includeMetafields: false` | DE / DE | The full `ProductDetail` fragment: 29.90 EUR, compare-at 149.99 EUR, one digital variant (`requiresShipping: false`), 1 image, 5 collections. Its `descriptionHtml` (about 45 KB, no table) is the main input of the HTML parser tests. |
| `product_office-2024-professional-plus-key_CH_FR.json` | `ProductByHandle` (query), `includeMetafields: false` | CH / FR | The same product with French content and CHF prices (29.00 CHF, compare-at 142.00 CHF). |
| `product_not_found_DE_DE.json` | `ProductByHandle` (query), handle `kx-fixture-no-such-product` | DE / DE | `data.product` is `null` for an unknown handle. |
| `collection_bestseller_DE_DE.json` | `CollectionProducts` (query), `first: 8`, `sortKey: COLLECTION_DEFAULT` | DE / DE | The first 8 bestsellers with `ProductSummaryFields`, `pageInfo` (`hasNextPage: true`) and the store's filters (availability `LIST`, price `PRICE_RANGE` 0 to 239.9). |
| `collection_windows_price_filtered_DE_DE.json` | `CollectionProducts` (query), `first: 8`, `sortKey: PRICE`, `filters: [{price: {min: 10, max: 30}}]` | DE / DE | 8 Windows products from 11.90 EUR ascending; the price filter value echoes the applied range. |
| `collections_DE_DE.json` | `Collections` (query), `first: 50` | DE / DE | All 29 collections by title (including `all` and `digital-goods-vat-tax`), none with an image. |
| `product_recommendations_related_DE_DE.json` | `ProductRecommendations` (query), Office 2024 Professional Plus, `RELATED` | DE / DE | 10 related products. |
| `product_recommendations_complementary_DE_DE.json` | `ProductRecommendations` (query), `COMPLEMENTARY` | DE / DE | `[]`: the store configures no complementary products. |
| `predictive_search_win_DE_DE.json` | `PredictiveSearch` (query), `query: "win"`, `limit: 6` | DE / DE | 6 products, 6 collections, 6 articles from the `news` and `guides` blogs, no query suggestions. |
| `search_office-2024_DE_DE.json` | `SearchProducts` (query), `query: "office 2024"`, `first: 8`, `RELEVANCE` | DE / DE | `totalCount: 15`, 8 products, availability and price filters, `hasNextPage: true`. |
| `blog_guides_articles_DE_DE.json` | `BlogArticles` (query), `guides`, `first: 6` | DE / DE | The 6 newest guides (newest first) with excerpt, date, image (some without) and web URL. |
| `article_guides_windows-11-kompatibilitaet-pruefen_DE_DE.json` | `Article` (query) | DE / DE | One guide with author name and a `contentHtml` that contains a style sheet, a JSON-LD script, an image, two tables (with `colgroup`, `thead`, `th`), `details` and inline `code`. The HTML parser tests use it for tables and dropped content. |
| `cart_create_invalid_merchandise_DE_DE.json` | `CartCreate` (mutation), merchandise `gid://shopify/ProductVariant/1` | DE / DE | A user error (`code: INVALID`, field `input.lines.0.merchandiseId`), `cart: null`. No cart was created. |
| `cart_create_DE_DE.json` | `CartCreate` (mutation), 1x the cheapest digital variant (Office 2019 Professional Plus, 9.90 EUR) | DE / DE | The full `CartFields` of a new cart: one line, attributes `app_platform` and `kx_fixture_recording`, buyer country DE. |
| `cart_lines_add_DE_DE.json` | `CartLinesAdd` (mutation), 1x the second cheapest digital variant | DE / DE | Two lines; the store's automatic quantity discount ("ab 2 Lizenzen -10%") as a `CartAutomaticDiscountApplication` with a percentage value; total 17.82 EUR. |
| `cart_lines_update_DE_DE.json` | `CartLinesUpdate` (mutation), first line to quantity 2 | DE / DE | Three items, 15 % quantity discount, total 25.25 EUR. |
| `cart_discount_codes_invalid_DE_DE.json` | `CartDiscountCodesUpdate` (mutation), code `KX-FIXTURE-NOT-A-CODE` | DE / DE | The code stays on the cart with `applicable: false`; warning `DISCOUNT_NOT_FOUND` with Shopify's German message. |
| `cart_lines_remove_DE_DE.json` | `CartLinesRemove` (mutation), the second line | DE / DE | One line (quantity 2) left. |
| `cart_query_DE_DE.json` | `Cart` (query) | DE / DE | The same cart read back after the lifecycle. |
| `product_metafields_access_denied_DE_DE.json` | `ProductByHandle` (query), `includeMetafields: true`, tokenless | DE / DE | The real `ACCESS_DENIED` error (`requiredAccess`: `unauthenticated_read_metafields`) with `data.product: null`. |
| `synthetic_throttled.json` | none (synthetic) | none | See below. |
| `manifest.json` | | | Machine-readable list of every file: operation, kind, variables (anonymized), context (with the rendered `@inContext` directive), token mode, HTTP status, attempts, anonymized paths, API version, date. |

The repository tests for `cartBuyerIdentityUpdate` and `cartAttributesUpdate` reuse the
recorded cart of `cart_query_DE_DE.json` as their payload; both documents were validated
against the live API on 2026-10-24 but are not part of the recording, so the recorder sends
no more mutations than needed.

### Synthetic fixtures

Files named `synthetic_*.json` were **not** recorded. They are hand-written error envelopes
for situations that cannot be provoked safely against the production store, and they follow
the format Shopify documents under "Status and error codes" of the Storefront API reference
(<https://shopify.dev/docs/api/storefront/2026-10>):

- `synthetic_throttled.json`: HTTP 200 with a top-level error
  `{"message": "Throttled", "extensions": {"code": "THROTTLED", "documentation": "https://shopify.dev/api/usage/rate-limits"}}`
  and no `data`.

The recorder writes them from constants in `Tools/FixtureRecorder/Sources/FixtureRecording/FixturePlan.swift`.

## Re-recording

```sh
cd Tools/FixtureRecorder
swift run fixture-recorder --output ../../Packages/ShopifyKit/Tests/ShopifyKitTests/Fixtures
# optional: --shop-domain <domain> --api-version <version>
# optional token: KX_STOREFRONT_TOKEN=<public token> swift run fixture-recorder --output ...
cd ../../Packages/ShopifyKit && swift test
```

- The recorder runs on macOS and Linux and overwrites the files listed above plus
  `manifest.json`; this README is maintained by hand.
- It sends read queries, the `cartCreate` with the non-existent merchandise ID
  `gid://shopify/ProductVariant/1` (creates nothing), and one cart lifecycle on a cart it
  creates itself with the two cheapest digital variants: create, add, update, invalid
  discount code, remove, read. It never opens or posts to the checkout URL, so the cart
  never becomes an order and expires on its own; the attribute `kx_fixture_recording=true`
  marks it among abandoned carts. Cart mutations only ever target the cart the recorder
  created in the same run. No other mutation is ever sent.
- With a token, the two product fixtures include metafields; the access-denied fixture is
  always recorded without a token.
- The recorder validates every response with the real client (for example, it fails if the
  bestseller collection no longer returns 8 products, if the cart lifecycle does not produce
  the expected lines or if the invalid cart call unexpectedly succeeds). After re-recording,
  update the concrete values asserted in the tests (titles, prices, cursors, the cheapest
  variants) when the store content changed.

## Store content notice

The product descriptions (`descriptionHtml`) and articles (`contentHtml`) are store content
and are kept verbatim. On 2026-10-24 they still contained payment method and support channel
wording, including a link with a dialing URL scheme, that contradicts the business facts of
PROMPT section 2 and that app-authored text must never use. `HTMLDocument` turns every link
that is not `http(s)` into plain text, so the app never offers such an action, but the
wording itself needs to be fixed in the store by the owner. The forbidden-word check of the
CI skips this directory, because the fixtures are recorded data, not app copy.
