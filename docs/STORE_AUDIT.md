# Live store audit (karinex.de)

Recorded on 2026-09-26 with read-only queries against the Storefront API 2026-07 (tokenless)
and the Admin API (via the owner's Shopify connection, never from the app). PROMPT.md asks to
verify handles, metafields and markets on the live store; this is the result. Where the store
differs from PROMPT.md, the app follows the store and the difference is listed here with the
owner action it needs.

Nothing in the store was changed during the audit.

## Shop

| Fact | Value |
| --- | --- |
| Shop name | karinex |
| myshopify domain (`{{SHOP}}`) | `45dv93-bk.myshopify.com` |
| Shop ID (`{{SHOP_ID}}`) | `91753283851` |
| Primary domain | `https://www.karinex.de` |
| Customer account domain | `account.karinex.de` |
| Plan | Basic |
| Active products | 47, all with exactly one variant |

## Storefront access

- The Storefront API answers **without an access token** ("tokenless") for products,
  collections, localization, search, pages, blogs and cart. The app uses this mode until the
  owner provides a public Storefront token (`KX_STOREFRONT_ACCESS_TOKEN`).
- Tokenless requests cannot read **metafields** (`ACCESS_DENIED`, required scope
  `unauthenticated_read_metafields`). ShopifyKit therefore only requests metafields when a
  token is configured (`@include(if: $includeMetafields)`).
- Tokenless requests are limited to a query cost of 1000 per request, which the Phase 0
  queries stay well below (5 to 14).

## Markets and languages

| | PROMPT.md | Live store | App behaviour |
| --- | --- | --- | --- |
| Countries | 30 markets incl. NO and USA | 28 enabled: AT BE BG CH CY CZ DE DK EE ES FI FR GR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK. Norway exists but is **disabled**. There is **no USA market**. | Countries come from `localization.availableCountries` at runtime, so the app follows the store automatically. Region not sold (for example US or NO): falls back to DE and says so once. |
| Currencies | | EUR, CHF, CZK, DKK, HUF, PLN, RON, SEK | Prices are shown exactly as returned (`MoneyV2`). |
| Content languages | 11 | 13: the 11 app languages plus **EL** (Greek) and **RO** (Romanian) | The app UI ships in the 11 languages of PROMPT.md. A user whose device is Greek or Romanian gets the English UI and English content (nearest supported pair). Adding EL/RO later only needs two more String Catalog columns. |

## Collections (handles)

| PROMPT.md handle | Exists? | Live handle the app uses |
| --- | --- | --- |
| `windows` | yes | `windows` |
| `office` | **no** | `microsoft-office` |
| `server` | **no** | `windows-server` |
| `bestseller` | yes | `bestseller` |
| Developer row | | `visual-studio-entwicklungstools` |
| `blitzangebote` | **no** | none yet: create it, or the Home screen uses `sale` for the deals row |

Other live collections: `sale`, `microsoft-tools`, `microsoft-365-abonnement`,
`microsoft-office-fur-mac`, `microsoft-office-2024`, `microsoft-office-2021`,
`microsoft-office-2019`, `windows-11`, `windows-10`, `microsoft-project`, `microsoft-visio`,
`microsoft-sql-server`, `windows-server-2025` ... `windows-server-2008`, `all` and the helper
collection `digital-goods-vat-tax` (not shown in the app).

No `app_home` metaobject exists yet. Until the owner creates one, the Home screen uses a
fixed section order with the live handles above.

## Content

| PROMPT.md | Live store |
| --- | --- |
| Blog `news` | exists (`news`), plus `guides` ("Anleitungen & Guides") which fits the "Ratgeber" row and activation guides better |
| Page `impressum` | **does not exist**. Candidate: `rechtliche-hinweise` (to be confirmed by the owner) |
| Policies | `privacyPolicy`, `refundPolicy`, `shippingPolicy`, `termsOfService` all exist; pages `agb`, `widerrufsrecht`, `versand` also exist |

## Product metafields

| PROMPT.md key | Live state | Storefront visible? |
| --- | --- | --- |
| `karinex.faq` (JSON `[{question, answer}]`) | present on all 47 products | **no**: no metafield definition, so not exposed |
| `karinex.sprachen` | present | **no** (no definition) |
| `karinex.lizenztyp`, `karinex.architektur`, `karinex.geraeteanzahl`, `karinex.lieferform`, `karinex.aktivierungsart`, `karinex.support_status` | **missing** | no. A compact `custom.kx_spec` (for example `1pc|perpetual|download`) exists on 8 products only |
| `custom.details_content`, `custom.shipping_content`, `custom.warranty_content` | **missing**; the theme uses `custom.collapsible_row_heading_1..3` / `custom.collapsible_row_content_1..3` (rich text) | no (storefront access NONE) |
| `custom.mpn` | **missing**; `mm-google-shopping.mpn` exists | no (no definition) |
| `karinex.deal_ends_at` | **missing**; `custom.angebotsende` (date_time, storefront PUBLIC_READ) exists but every value is in July 2026, so all deals have expired | `custom.angebotsende`: yes |
| Reviews | `karinex.review_rating`, `karinex.review_count`, `reviews.rating_count`, `custom.card_rating*`, plus data from several review apps (`alireviews`, `vstar`, `ddreviews`, eBay import) | partly |
| Price history | `karinex.lowest_price_30d` (integer, minor units, EUR only) and `karinex.price_history` (JSON) | no (no definition) |
| Social proof | `custom.units_sold`, `custom.recently_sold_count`, `custom.recently_sold_city`, `custom.recently_sold_hours` | the app **never** displays these (PROMPT.md section 2: no "sold X times") |
| Comparison | `custom.siblings` (list of product references) on 2 products, `custom.wird_oft_zusammen_gekauft`, `custom.frequently_bought`, Shopify `related_products` | partly |

## Product content conflicts with the hard rules

The app renders product descriptions from Shopify as they are (PROMPT.md 2 and 3.1), so store
content that breaks a hard rule would appear in the app:

- The German and French `descriptionHtml` of `office-2024-professional-plus-key` (recorded in
  `Packages/ShopifyKit/Tests/ShopifyKitTests/Fixtures`) lists **PayPal** as a payment method and
  contains a **"Service-Hotline"** with a **`tel:` link and phone number** ("Telefon",
  "telefonisch"). PayPal is not offered and phone support does not exist (PROMPT.md 2 and hard
  rule 4). Other products are likely affected too.
- Several product titles and SEO descriptions say "Original-Lizenz" / "Original Lizenz". This is
  store content (allowed), but it is one of the known content risks in PROMPT.md 2.

Phase 1 mitigation in the app: the native HTML renderer drops `tel:` links (rendering their text
as plain text) and never turns phone numbers into actions. The text itself can only be fixed in
the store.

## Required owner actions (blocking Phase 1 product details)

1. **Create a Headless channel Storefront token** and put it into `Config/Secrets.xcconfig`
   (and the CI secret `KX_STOREFRONT_ACCESS_TOKEN`).
2. **Create metafield definitions with Storefront access "Read"** for every key the product
   screen uses (Settings > Custom data > Products): `karinex.faq` (JSON), `karinex.sprachen`,
   and the spec keys. Values that already exist become visible as soon as a definition exists.
3. **Decide the spec source**: either fill the `karinex.*` spec keys listed in PROMPT.md 5.1,
   or confirm that the app should map `custom.kx_spec` and the `shopify.*` standard taxonomy
   metafields (`shopify.license-type`, `shopify.operating-system`, `shopify.supported-language`,
   which are already Storefront-readable) instead.
4. **Confirm the Impressum page handle** (`rechtliche-hinweise`?) or create `impressum`.
5. **Deals**: create the `blitzangebote` collection and a `karinex.deal_ends_at` definition, or
   confirm that the app should use `sale` and `custom.angebotsende`.
6. **Reviews**: confirm in writing which review source contains only real, verified reviews.
   Until then the app shows no ratings at all (PROMPT.md section 2).
7. **Strike-through prices**: every product has a compare-at price (for example 29,90 € instead
   of 149,99 €). Under § 11 PAngV a price reduction must refer to the lowest price of the last
   30 days. The app shows compare-at prices only as Shopify returns them; please confirm with
   legal counsel that the compare-at values meet this rule, or expose `karinex.lowest_price_30d`
   so the app can show it alongside.
8. **Norway / USA**: PROMPT.md lists them as markets, the store does not sell there. No app
   change is needed either way.
9. **Product descriptions**: remove PayPal, the service hotline and phone numbers from the
   product descriptions (all languages), see "Product content conflicts" above.
