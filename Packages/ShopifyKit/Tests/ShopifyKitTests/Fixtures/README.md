# ShopifyKit test fixtures

Raw response bodies of the live KARINEX Storefront API, used by `ShopifyKitTests` to decode
real data through the real `GraphQLClient` (with a stub transport).

| Property | Value |
| --- | --- |
| Store | `45dv93-bk.myshopify.com` (web: `www.karinex.de`) |
| API | Storefront API `2026-07`, `https://45dv93-bk.myshopify.com/api/2026-07/graphql.json` |
| Access | tokenless (no `X-Shopify-Storefront-Access-Token`) |
| Recorded | 2026-09-26 (exact timestamp per file in `manifest.json`) |
| Recorder | `Tools/FixtureRecorder` (`swift run fixture-recorder`) |
| Consent | every live call carried `visitorConsent: {analytics: false, preferences: true, marketing: false, saleOfData: false}` |

Every file is the exact body Shopify returned for the final HTTP attempt, re-serialized
deterministically: two-space indentation, keys sorted, `[]`/`{}` for empty containers,
slashes and non-ASCII characters unescaped, trailing newline. The recorder runs an
anonymizer over every body (cart, checkout, customer and address IDs, checkout URLs and
personal fields); none of these fixtures contains customer data, so nothing was changed
(`anonymizedPaths` is empty for every entry of `manifest.json`).

## Files

| File | Operation | Context | What it shows |
| --- | --- | --- | --- |
| `localization_DE_DE.json` | `Localization` (query) | DE / DE | 28 countries with currency (EUR, CHF, CZK, DKK, HUF, PLN, RON, SEK) and content languages; 13 languages for DE; the Netherlands only offer `NL`. |
| `product_office-2024-professional-plus-key_DE_DE.json` | `ProductByHandle` (query), `includeMetafields: false` | DE / DE | The full `ProductDetail` fragment: 29.90 EUR, compare-at 149.99 EUR, one digital variant (`requiresShipping: false`), 1 image, 5 collections. |
| `product_office-2024-professional-plus-key_CH_FR.json` | `ProductByHandle` (query), `includeMetafields: false` | CH / FR | The same product with French content and CHF prices (29.00 CHF, compare-at 145.00 CHF). |
| `product_not_found_DE_DE.json` | `ProductByHandle` (query), handle `kx-fixture-no-such-product` | DE / DE | `data.product` is `null` for an unknown handle. |
| `collection_bestseller_DE_DE.json` | `CollectionProducts` (query), `first: 8`, `sortKey: COLLECTION_DEFAULT` | DE / DE | The first 8 bestsellers with `ProductSummaryFields` and `pageInfo` (`hasNextPage: true`). |
| `cart_create_invalid_merchandise_DE_DE.json` | `CartCreate` (mutation), merchandise `gid://shopify/ProductVariant/1` | DE / DE | A user error (`code: INVALID`, field `input.lines.0.merchandiseId`), `cart: null`. No cart was created. |
| `product_metafields_access_denied_DE_DE.json` | `ProductByHandle` (query), `includeMetafields: true`, tokenless | DE / DE | The real `ACCESS_DENIED` error (`requiredAccess`: `unauthenticated_read_metafields`) with `data.product: null`. |
| `synthetic_throttled.json` | none (synthetic) | none | See below. |
| `manifest.json` | | | Machine-readable list of every file: operation, kind, variables, context (with the rendered `@inContext` directive), token mode, HTTP status, attempts, API version, date. |

### Synthetic fixtures

Files named `synthetic_*.json` were **not** recorded. They are hand-written error envelopes
for situations that cannot be provoked safely against the production store, and they follow
the format Shopify documents under "Status and error codes" of the Storefront API reference
(<https://shopify.dev/docs/api/storefront/2026-07>):

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
- It only sends read queries plus the one `cartCreate` with the non-existent merchandise ID
  `gid://shopify/ProductVariant/1`, which creates nothing. It never sends any other mutation.
- With a token, the two product fixtures include metafields; the access-denied fixture is
  always recorded without a token.
- The recorder validates every response with the real client (for example, it fails if the
  bestseller collection no longer returns 8 products or if the cart call unexpectedly
  succeeds). After re-recording, update the concrete values asserted in the tests (titles,
  prices, cursors) when the store content changed.

## Store content notice

The product descriptions (`descriptionHtml`) are store content and are kept verbatim. On
2026-09-26 they contained payment method and support channel wording that contradicts the
business facts of PROMPT section 2 and that app-authored text must never use. This needs to
be fixed in the store by the owner (the app renders descriptions as returned). The
forbidden-word check of the CI must skip this directory, because the fixtures are recorded
data, not app copy.
