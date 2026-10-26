# KARINEX iOS App — Master Build Prompt (v1.0)

> Paste this whole file as the first message to your coding agent (Claude Code, Cursor, etc.) inside an empty repository, e.g. `karinex-ios/`. Also save it as `PROMPT.md` in the repo and reference it from `CLAUDE.md`. Fill the `{{PLACEHOLDERS}}` in section 15 before starting.

---

## 0. ROLE

You are acting as a combined **Principal iOS Engineer (SwiftUI, Swift 6)**, **Senior Product Designer (Apple HIG, luxury e-commerce)** and **Shopify Headless Architect (Storefront API, Customer Account API, Checkout Kit)** with 15+ years of shipping App Store apps for European retailers. You build production software, not demos. You verify every external API against current official documentation before you write code, you never invent product facts, and you deliver complete, compiling, tested files.

## 1. MISSION

Build the official native iOS app for **KARINEX** (https://karinex.de), a Hamburg-based Shopify store selling Microsoft software licenses (Windows, Office, Windows Server, Visual Studio, Visio, Project) to consumers across Europe. The app must feel like a premium first-party product: instant, elegant, trustworthy, fully localized, and built on Shopify's headless mobile stack so that catalog, prices, cart, checkout, orders and accounts are always in sync with the store.

Target outcome: an App Store–approved app that measurably increases repeat purchases and reduces support load by giving customers a beautiful place to browse, buy, and retrieve their license keys and invoices at any time.

---

## 2. BUSINESS CONTEXT (single source of truth for facts)

**Company:** KARINEX, sole proprietorship, Hamburg (22115), Germany. Shopify store `karinex.de`. Legal entity name may differ from brand name; the app only ever shows "KARINEX".

**Products:** Digital license keys (ESD) for Microsoft software. A small number of physical items (USB sticks / discs) exist and require shipping. Digital products have `requiresShipping = false`; the checkout shows a billing address only.

**Fulfillment model (critical):** License keys and PDF invoices are **not** stored in Shopify. They are issued by KARINEX's internal fulfillment service (a Node service hosted on Railway, called the "Rechnungs-Generator"). After payment it emails the customer a certificate-styled delivery email with the key and the invoice. The app must never expect keys inside Shopify line items. In-app key retrieval goes through a small authenticated backend endpoint (section 12).

**Markets and languages:** 30 active Shopify Markets: 17 individual EU countries plus DE, DK, FI, GR, NL, PL, PT, RO, SE, ES, CH, NO, USA (USA digital-only). Product content exists in 11 languages: **DE (primary), EN, PL, NL, PT-PT, SV, DA, ES, FR, IT, FI**. Roughly 63% of revenue comes from non-German EU countries, so localization is a core feature, not a nice-to-have.

**Payments (as configured in Shopify checkout, owner update of 2026-10-26, as in the web shop):** Apple Pay, Google Pay, credit/debit card (Visa, Mastercard, American Express, UnionPay), Klarna, Rechnung (purchase on invoice) and Vorkasse (payment in advance by bank transfer). **PayPal is NOT offered and must never appear anywhere in the app.** All payment handling happens inside Shopify checkout; the app never touches card data.

**Support channels:** WhatsApp, email (`kundenservice@karinex.de`), live chat. Hours: **Monday to Sunday, 06:00–23:00 Europe/Berlin**. **Phone support does not exist. Never show a phone number, "Hotline", call button or `tel:` link.**

**Refund policy (exact wording logic):** "14 Tage Geld-zurück" applies only to **activated** license keys and to physical goods. Delivered but **not activated** keys are not refunded voluntarily (the key could be used later). Statutory warranty rights for defective keys remain untouched. Wherever the app shows the 100-day promise, the condition must be visible next to it.

**Right of withdrawal:** For digital content the right of withdrawal expires once delivery begins with the customer's express consent (§ 356 Abs. 5 BGB). Shopify checkout collects that consent; the app shows the notice on product pages and in the cart.

**Activation:** Activation instructions differ per product and come from Shopify product content (metafields / description). Do not hardcode activation steps. Typical example: Office 2024 Pro Plus activates via "File > Account > Enter product key", not via office.com/setup.

**Brand identity ("KARINEX Clean", owner decision of 2026-10-25):** black `#111111`, white `#FFFFFF` and neutral greys, one sale red `#C20E2B`, bold SF Pro headlines, product photos edge to edge on light grey, as in modern fashion retail apps (reference: the OACE app). It replaces the earlier green, cream and gold "Editorial Luxe" identity, which the owner rejected after the first TestFlight build. The logo is the KARINEX logo of the web shop (`Tools/Brand/store-logo.png`), drawn as a tinted template image.

**Known content risks (must be respected in app copy):**
- Never claim that the license chain / license origin was "verified" or "documented".
- Never write "100% legal", "Original-Lizenz", "geprüfte Lizenzen" or similar strong claims in app-authored copy. Product marketing text is rendered from Shopify as-is; the app adds no claims of its own.
- Never invent ratings, review counts or "sold X times" numbers. Social-proof values may only be displayed when they come from real, verified store data. The product page shows "In den letzten 30 Tagen X-mal verkauft" from `custom.recently_sold_count` only from 5 units on, and only once the store's sales script writes real quantities (docs/STORE_AUDIT.md, "Recently sold numbers").

**Benchmarks (for UX research only, never copy):** systeme-software24.com, lizenzstar.de, lizenzguru.de, softwareindustrie24.de, ekeys.it, voelkner.de (deal carousel pattern).

---

## 3. HARD RULES (non-negotiable)

1. **Shopify is the only source of product truth.** Prices, availability, titles, descriptions, specs, FAQs, policies and images are fetched live from the Storefront API. Nothing product-related is hardcoded.
2. **No Apple In-App Purchase.** The app sells goods consumed outside the app (software installed on PCs/Macs) and physical goods. Purchases go exclusively through Shopify checkout (Checkout Kit). The app never unlocks any of its own features behind a payment.
3. **Native, not a web wrapper.** All screens are SwiftUI. The only web surfaces are Shopify checkout (via Checkout Kit) and the Customer Account login page (via `ASWebAuthenticationSession`). Legal texts and blog articles are rendered natively from HTML → `AttributedString`.
4. **Zero PayPal, zero phone.** See section 2.
5. **Tax display is Shopify's job.** Show `MoneyV2` amounts exactly as returned for the active market. Never compute VAT yourself. Use "inkl. MwSt." wording only where Shopify's market settings include tax (EU); keep it neutral for CH/NO/US.
6. **German UI copy**: formal "Sie", professional and calm, no filler phrases, no em dashes or en dashes (use normal punctuation). All 11 languages must read like native, professionally written retail copy.
7. **Deliver complete code.** Every file you output is complete and compiles. No `// ... unchanged`, no `TODO`, no placeholder implementations in shipped code.
8. **Verify before you build.** Check shopify.dev for the current stable Storefront API and Customer Account API versions and the latest Checkout Kit release on the day you start, and pin them explicitly.
9. **Read-only toward the store.** The app performs only cart mutations and customer-scoped queries. Never touch Admin API from the app.
10. **Privacy by default.** No analytics, crash reporting or push registration before explicit user consent. No advertising SDKs. No App Tracking Transparency prompt (nothing to track).

---

## 4. TECH STACK AND ARCHITECTURE

- **Language / tooling:** Swift 6 with strict concurrency, latest stable Xcode (26.x or newer), Swift Package Manager only (no CocoaPods).
- **Minimum deployment:** iOS 17.0. Build against the latest SDK so system chrome (tab bar, navigation bars, sheets) automatically adopts the current iOS design language; brand colors live in content, not in system chrome.
- **UI:** SwiftUI everywhere. `@Observable` view models, `NavigationStack` with typed routes, `TabView`, `.sheet`/`.fullScreenCover` for modals.
- **Architecture:** Modular SPM workspace:
  - `Core` (networking, GraphQL client, Keychain, logging, feature flags, environment)
  - `DesignSystem` (tokens, typography, components, previews, snapshot tests)
  - `ShopifyKit` (Storefront API + Customer Account API clients, models, repositories, fixtures)
  - `Features/Home`, `Features/Catalog`, `Features/Product`, `Features/Search`, `Features/Cart`, `Features/Checkout`, `Features/Account`, `Features/Licenses`, `Features/Support`, `Features/Legal`, `Features/Settings`
  - `App` (composition root, DI container, deep links, app lifecycle)
  - Pattern: MVVM + Repository, protocol-based dependencies injected via a lightweight container, unidirectional data flow, `async/await` and structured concurrency throughout.
- **Networking:** `URLSession` with a small typed GraphQL client of your own (Codable models, operation name, variables, `@inContext` injection, error mapping for `userErrors`, retry with exponential backoff, request de-duplication). Do not add Apollo unless you can justify codegen benefits; keep the toolchain simple.
- **Checkout:** `ShopifyCheckoutSheetKit` (Swift package `checkout-sheet-kit-swift`, version ≥ 3.0.0).
- **Auth:** Shopify **Customer Account API** (public client, OAuth 2.0 Authorization Code + PKCE, scopes `openid email customer-account-api:full`) via `ASWebAuthenticationSession`. Tokens stored in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), silent refresh, logout through the discovered `end_session_endpoint`.
- **Images:** Nuke (or a thin `URLCache`-backed loader) with Shopify CDN width/format parameters and prefetching.
- **Persistence:** Cart ID and lightweight preferences in `UserDefaults`; tokens and cached license keys in Keychain; catalog cache via `URLCache` + in-memory store; "recently viewed" and wishlist via SwiftData.
- **Push:** APNs registered through the KARINEX backend (section 12). No third-party push SDK in v1.
- **Observability:** MetricKit for performance/crash diagnostics by default; optional Sentry only after consent, initialized lazily.
- **Localization:** String Catalogs (`.xcstrings`), 11 languages, ICU plural rules, locale-aware number/currency/date formatting.
- **Testing:** Swift Testing for unit tests, snapshot tests for `DesignSystem`, XCUITest for the critical path (browse → add to cart → checkout sheet presented; login; copy key), a pseudo-locale run for layout overflow.
- **CI/CD:** GitHub Actions (build + test on every PR) and fastlane lanes for TestFlight; or Xcode Cloud if the owner prefers. Secrets only in CI secrets / `.xcconfig` files that are git-ignored.

---

## 5. SHOPIFY INTEGRATION SPEC

### 5.1 Storefront API
- Endpoint `https://{{SHOP}}.myshopify.com/api/{{STOREFRONT_VERSION}}/graphql.json`, header `X-Shopify-Storefront-Access-Token: {{STOREFRONT_PUBLIC_TOKEN}}` (public token only).
- Every query carries `@inContext(language: <LanguageCode>, country: <CountryCode>)` derived from the user's active app language and market. On first launch, resolve device region and language against `localization { availableCountries { isoCode currency { isoCode } } availableLanguages { isoCode } }`; fall back to `DE` / `EN`. Persist the choice; allow manual override in Settings.
- Product fragment (extend as needed): `id handle title vendor productType tags availableForSale descriptionHtml featuredImage images(first:8) options variants(first:20){ id title sku availableForSale requiresShipping price{amount currencyCode} compareAtPrice{amount currencyCode} selectedOptions } seo{ title description } collections(first:5){ handle title }` plus **metafields** via `metafields(identifiers: [...])`:
  - `karinex.faq` (JSON array of `{question, answer}`) → FAQ accordion
  - `karinex.lizenztyp`, `karinex.architektur`, `karinex.geraeteanzahl`, `karinex.lieferform`, `karinex.aktivierungsart`, `karinex.sprachen`, `karinex.support_status` → spec table
  - `custom.details_content`, `custom.shipping_content`, `custom.warranty_content` (rich text) → detail sections
  - `custom.mpn` → shown in specs
  - `karinex.deal_ends_at` (datetime, create if missing) → deal countdown
  - Review data: only display an aggregate if the owner confirms the source is real verified reviews; otherwise omit the module entirely.
- Collections: fetch by handle. Known handles to verify on the live store: `windows`, `office`, `server`, `bestseller`. Home layout falls back to these if no `app_home` metaobject exists (recommend creating a metaobject `app_home` with ordered sections so the home screen can be re-arranged without an app release).
- Search: `predictiveSearch(query:)` for type-ahead plus `products(query:, sortKey:)` for results with pagination (`after` cursors).
- Blog: `blog(handle:"news")` (verify handle) for activation guides and articles.
- Policies: `shop { privacyPolicy refundPolicy shippingPolicy termsOfService }` and `page(handle:"impressum")` (verify handle) for the Impressum.

### 5.2 Cart
- Create a cart on first add (`cartCreate`), persist `cart.id`, refresh via `cart(id:)` on launch, recreate if it returns null.
- Mutations: `cartLinesAdd`, `cartLinesUpdate`, `cartLinesRemove`, `cartDiscountCodesUpdate`, `cartBuyerIdentityUpdate` (countryCode, email, `customerAccessToken` when logged in so checkout is pre-authenticated), `cartAttributesUpdate` (`app_platform=ios`, `app_version`).
- Always surface `userErrors` to the user with clear localized messages.
- Request a fresh `checkoutUrl` at the moment the user taps "Zur Kasse"; if the sheet reports a stale URL, re-query the cart and retry once.

### 5.3 Checkout Kit
- `ShopifyCheckoutSheetKit.preload(checkout:)` when the cart screen appears and after every cart change (debounced).
- `present(checkout:from:delegate:)` on "Zur Kasse". Implement `CheckoutDelegate`: on completion clear the local cart, store the order summary from the completed event, show a success screen ("Bestellung eingegangen. Ihr Lizenzschlüssel wird per E-Mail zugestellt.") with a button to the Orders tab; on cancel keep the cart; on failure show a recoverable error with retry.
- Configure branding options to match the design system (black and white, sheet corner radius, title).
- Pass the user's privacy consent state to the kit so Shopify applies the right tracking rules during checkout.
- Handle external links (e.g., Klarna) and `returnTo`/deep links back into the app.

### 5.4 Customer Account API
- Discover endpoints from the store domain's discovery URL (authorization, token, end-session, GraphQL API). Cache them.
- Login: build the authorization URL (client ID `{{CUSTOMER_ACCOUNT_CLIENT_ID}}`, redirect `{{CUSTOMER_ACCOUNT_REDIRECT_URI}}`, `state`, `nonce`, PKCE S256, optional `locale` and `region_country` for market-aware login). Shopify's hosted page handles passwordless email codes; the app never sees a password.
- Exchange the code for tokens, validate `state`/`nonce`, store tokens in Keychain, refresh silently, logout via `end_session_endpoint` with `id_token_hint`.
- Queries: `customer { id displayName emailAddress { emailAddress } defaultAddress addresses }`, `orders(first:, reverse:true) { id name processedAt financialStatus fulfillments totalPrice lineItems { id title quantity image variantTitle price } }`, order detail by ID, address mutations.
- Do not add Google/Facebook/other third-party social login (that would trigger the Sign in with Apple requirement). Passwordless Shopify login only.

### 5.5 Error handling and resilience
- Map GraphQL errors, HTTP errors, throttling (retry with backoff and jitter) and offline state to typed errors and to consistent UI states (skeleton → content / empty / error with retry / offline banner).
- Log without PII. Never log tokens, emails or keys.

---

## 6. FEATURE SPEC BY SCREEN

Tab bar: the system tab bar **Start · Shop · Suche · Warenkorb · Konto**. The Warenkorb tab shows a shopping bag with the number of items as a small figure beside it instead of a red badge (owner request of 2026-10-25, reference: the About You app); the bag is the About You tote with its tall handle (owner request of 2026-10-26); VoiceOver reads the number as the tab's value.

Opening (owner request): the launch screen shows the store logo centered on the page background; the app then zooms into the logo and reveals the Start tab in under one second (only a fade with Reduce Motion).

### 6.1 Start (Home)
Laid out like the home screen of the About You app (owner request of 2026-10-25), with KARINEX's own products; every product, photo and price comes from Shopify.
- Top: the logo with the Merkliste heart (number of saved products beside it) scrolls away; the search field stays pinned and opens Suche with the cursor in the field.
- Story carousel: one large rounded panel in the store color `#0E4343`, the stories paging sideways inside it (Bestseller, Windows, Office, Office für Mac, Server, Entwicklung; Mac added on owner request of 2026-10-26), each with the photo of the collection's first product, a tag, four product tiles and "Kategorie entdecken"; fixed page dots.
- Trust strip: "Lieferung per E-Mail in Minuten" · "Apple Pay, Kreditkarte, Klarna" · "14 Tage Geld-zurück*" (with the condition in a tappable footnote) · "Support Mo. bis So., 06:00 bis 23:00 Uhr".
- "Unsere Kategorien": category tiles (Windows · Office · Server · Office für Mac · Entwicklung · Microsoft 365 · Alle Kategorien) above a store color panel with the products of the chosen category in large portrait cards and "Alle anzeigen". The tiles show KARINEX's own SVG category icons (one line style with a soft fill, no third-party logos). Like the brand strip of About You (owner request of 2026-10-26) the showcase moves on by itself: the chosen tile fills with a lighter store color for five seconds, then the next category follows with a soft cross-fade. It holds still off screen, with VoiceOver, Switch Control or Reduce Motion, and once the customer taps a tile or scrolls; the panel keeps one height for every category.
- Bestseller row; the dark sale panel with the products of the sale collection (compare-at price, savings badge and the title in sale red).
- "Zuletzt angesehen", "Nach Version finden" (Windows 11, Windows 10, Office 2024, Office 2021 as photo tiles), service tiles into Konto (Hilfe und Support, Meine Lizenzen, Meine Bestellungen), "Ratgeber" as tall story tiles (blog articles), support card (WhatsApp + email).

### 6.2 Shop (Catalog)
- Laid out like the category pages of fashion retail apps (owner request of 2026-10-25): the bestsellers and the sale as two large cards (ink and sale red) with a product photo; the product families (Windows, Microsoft Office, Office für Mac, Microsoft 365, Windows Server, Visual Studio, Microsoft Tools) as rows with a short line and the photo of their first product; the single versions (Windows 11, Microsoft Office 2024, Windows Server 2025, ...) as a shelf of square photo cards with the short version name; every other collection as a list. Short names replace the store's search engine titles; cards shrink a little while pressed.
- Product list with sort (relevance, price, newest) and filters derived from product options/metafields: edition, device count, delivery form (download/USB), platform (Windows/Mac).
- Infinite scroll with cursor pagination, pull-to-refresh, skeleton states.

### 6.3 Product detail (the most important screen)
- Gallery edge to edge on the light grey photo tile (zoom, page dots, wishlist heart), bold title, price with "inkl. MwSt." logic per market, compare-at price, availability.
- **Sale look** (owner request, reference: the About You app): a reduced price is sale red next to the struck-through compare-at price, the reduction badge ("-80 %") sits above it, and the store's lowest price of the last 30 days (`karinex.lowest_price_30d`) follows below when Shopify provides it. Product cards show the reduction badge and the red price.
- **Linked products** (owner request): the products the owner linked in the web shop (list metafield `custom.siblings`) as photo thumbnails below the price, the current one outlined; tapping another opens it. A "Passend dazu" row shows Shopify's `COMPLEMENTARY` recommendations (set up in Search & Discovery).
- Variant selector (segmented or chips) with live price update.
- **Key facts** table with dot-leader rows (label ...... value) from `karinex.*` metafields: Lizenztyp, Architektur, Geräteanzahl, Lieferform, Aktivierungsart, Sprachen, Support-Status, MPN.
- **"So läuft es ab"** 3-step timeline: Bestellen → Bezahlen → Schlüssel per E-Mail (Minuten). For physical variants: shipping timeline instead.
- Description (`descriptionHtml`) rendered natively with brand typography; tables must render as real tables. It is the first collapsible row ("Beschreibung", as "Produktdetails" in fashion retail apps); an opened row shows the full text.
- **Activation** section from `custom.details_content` or linked blog guide.
- **Comparison** module: sibling products from the same collection (e.g., Office 2024 Home vs Standard vs Pro Plus) with thumbnails, key specs and price.
- **FAQ accordion** from `karinex.faq` with chevron toggles.
- Refund conditions block (exact policy logic from section 2) and digital-content notice (§ 356 Abs. 5 BGB).
- Sticky bottom bar: price + "In den Warenkorb" (haptic on success) + secondary "Jetzt kaufen" (adds and opens checkout). Share sheet, wishlist heart.

### 6.4 Suche (Search)
- Predictive search as you type (products, collections, articles), recent searches, suggested queries ("Office 2024", "Windows 11 Pro"), empty state with category shortcuts.
- Opened from the search field of Start, the field is ready for typing.

### 6.5 Warenkorb (Cart)
- Line items with quantity stepper, remove by swiping the line to the left or with its "x" (owner request of 2026-10-26, reference: the About You app: a red "Entfernen" behind the line; a long swipe turns the line red with "Produkt wird entfernt…" and "Abbrechen", whose fill runs down for 3 seconds, 10 with VoiceOver, before the line leaves the cart), subtotal/discount/total, discount code field, digital-content notice, payment-method acceptance marks, centered below the buttons as in the web shop (real Apple Pay, Google Pay, card brand, UnionPay and Klarna logos, plus plain marks with the names Rechnung and Vorkasse; card brands, Apple Pay and Google Pay as reported by Shopify's `shop.paymentSettings`, UnionPay, Klarna, Rechnung and Vorkasse from section 2; never any other method), "Zur Kasse" (Checkout Kit), cross-sell row. The product page shows the same marks below its buy buttons.

### 6.6 Checkout
- Checkout Kit sheet; success screen with order number, delivery expectation, buttons "Bestellungen ansehen" and "Weiter einkaufen".

### 6.7 Konto (Account)
- Logged-out: benefits list + "Anmelden" (passwordless), then "Meine Bestellungen" (owner request of 2026-10-26, reference: the About You app), which opens the login and then the orders in one go; screens that need the account show "Anmelden" in place when reached signed out. Every menu row has a short line under its title. Logged-in: profile, orders, licenses, addresses, notifications, language and market, legal, help, account deletion, logout.
- **Bestellungen:** list with status pills; detail with a vertical timeline (Bestellt → Bezahlt → Lizenz versendet / Versendet), line items, totals, "Rechnung (PDF)" and "Lizenzschlüssel anzeigen".
- **Meine Lizenzen (License vault):** black key cards (`#111111` card, bold product name, monospaced key, "Kopieren" with haptic and expiring clipboard, "Anleitung" link, "Support zu dieser Lizenz"). Optional Face ID gate (setting). Keys cached in Keychain for offline viewing, hidden behind a privacy overlay in the app switcher.
- **Konto löschen:** in-app flow that submits a GDPR erasure request to the backend, confirms by email, and logs the user out (App Store requirement).

### 6.8 Hilfe & Support
- WhatsApp deep link (`https://wa.me/{{WHATSAPP_NUMBER}}` with prefilled order context), email composer (`kundenservice@karinex.de`, prefilled subject with order number), live chat link `{{LIVE_CHAT_URL}}`, opening hours with an "Jetzt erreichbar / Derzeit nicht erreichbar" indicator computed in Europe/Berlin time, FAQ hub, activation guides.

### 6.9 Rechtliches (Legal)
- Impressum, AGB, Datenschutz, Widerrufsbelehrung, Versand & Lieferung — all fetched from Shopify and rendered natively; reachable within two taps from anywhere (Settings/Account). Show "Stand: <date>" if the page provides it.

### 6.10 Einstellungen (Settings)
- Language (11), country/market (from `availableCountries`), appearance (system/light/dark), notifications, privacy consents (analytics / crash reports), Face ID for licenses, about/version.

### 6.11 Cross-cutting
- **Deep links / Universal Links** for `karinex.de/products/{handle}`, `/collections/{handle}`, `/blogs/{blog}/{article}`, `/account/orders/...`, plus custom scheme `karinex://`.
- **Widgets (Phase 3):** "Blitzangebot" small/medium widget; **Live Activity** "Lizenz wird zugestellt" after checkout (ends when the backend confirms delivery via push).
- **Empty, loading, error, offline** states for every list and detail screen. Cached catalog and license vault must be readable offline.
- **Onboarding:** none beyond a one-time market/language confirmation sheet.

---

## 7. DESIGN SYSTEM — "KARINEX Clean for iOS"

**Direction (owner decision of 2026-10-25, replaces "Editorial Luxe"):** clean, photo-first retail in the style of modern fashion apps. White pages, black type and buttons, neutral grey panels, product photos square and edge to edge on a light grey tile, bold sans serif headlines, capsule buttons and pills, collapsible detail rows, no ornaments. One sale red for savings and deals. It must still feel unmistakably native iOS: system navigation chrome, standard gestures, Dynamic Type, SF Symbols.

**Color tokens (in code, `DesignTokens`, with light/dark variants):**
- `kx.ink` #111111 (primary text, filled buttons), `kx.inkPressed` #3A3A3A, `kx.graphite` #4D4D4D (secondary text), `kx.slate` #6B6B6B (tertiary text), `kx.steel` #8A8A8A (icons only)
- `kx.white` #FFFFFF (page background), `kx.fog` #F5F5F5 (panels, purchase bar), `kx.cloud` #F3F3F3 (behind product photos), `kx.mist` #E8E8E8 (hairlines), `kx.silver` #D9D9D9 (dividers, inactive page dots)
- `kx.sale` #C20E2B (savings and sale badges, countdown; sparingly). No other hue apart from the status colors.
- Semantic: success, warning, error, info with accessible contrast.
- Dark mode: background #000000, panels #1C1C1C and #2C2C2C, text #F5F5F5, white buttons with black labels, dividers #3A3A3A; the photo tile stays light. Test every screen in both modes.

**Typography:**
- All text in SF Pro via Dynamic Type text styles: bold, slightly tighter tracked headlines (display 34, title 28, section title 22), regular body text. License keys: SF Mono.
- Minimum contrast 4.5:1 for text.

**Components (each with previews and snapshot tests):** `KXButton` (capsules: primary black, secondary thin ink outline, tertiary text), `KXCard` (flat light grey panel, radius 12; outlined variant for the money-back promise), `KXBadge`, `KXPriceTag`, `KXSpecRow` (dot leaders), `KXStepTimeline`, `KXAccordion` (chevrons), `KXCountdown` (flip digits), `KXTrustStrip`, `KXProductCard` (square photo tile without card or border), `KXKeyCard` (black card), `KXSkeleton`, `KXEmptyState`, `KXBanner` (offline/error), `KXSectionHeader` (bold title, optional eyebrow).

**Motion and feel:** springs 0.25–0.35s, matched geometry for product card → detail, haptics for add-to-cart / copy key / successful checkout. Respect Reduce Motion and Reduce Transparency.

**Layout:** 8pt grid, 16pt gutters, safe areas, large titles where appropriate, iPhone first, iPad-compatible adaptive layouts (Phase 3 polish).

**Imagery:** Shopify CDN with `width` and `format=webp`; consistent aspect ratios; no third-party icon packs; SF Symbols only.

---

## 8. LOCALIZATION AND MARKETS

- 11 languages via String Catalogs; German is the source language. Translations must be native-quality retail copy (no literal machine phrasing). Provide a `LOCALIZATION.md` with tone rules per language.
- Language ↔ Storefront `LanguageCode` mapping, country ↔ `CountryCode` mapping; if the device combination is unsupported, pick the nearest supported pair and explain once in the confirmation sheet.
- Currency and prices from `MoneyV2` formatted with `Locale` (e.g., "11,90 €", "119 kr", "CHF 12.90").
- Tax wording per market as described in section 3.5. Legal references only to EU/German law where applicable; keep non-DE markets neutral.
- Dates and support hours displayed in the user's locale but computed in Europe/Berlin.
- Pseudo-localization pass to catch truncation; longest languages (FI, PT, DE) must not break layouts.

---

## 9. LEGAL AND COMPLIANCE (DE/EU)

- Impressum and privacy policy reachable within two taps at all times.
- Price display compliant with the German Preisangabenverordnung: total price including VAT for EU consumers; "zzgl. Versand" only for physical items.
- Order button wording and consent checkboxes (digital content, AGB) are handled by Shopify checkout; the app must not obscure or pre-tick anything.
- Consent management: no analytics/crash/push initialization before explicit opt-in; consent revocable in Settings; consent state passed to Checkout Kit.
- Data minimization: only the customer token, cart ID, preferences and consented diagnostics are stored. Everything sensitive is in Keychain.
- Account deletion available in-app.
- Provide `PRIVACY_NUTRITION_LABEL.md` listing exactly what is collected, for App Store Connect.

---

## 10. APP STORE COMPLIANCE

- **Payments:** goods are consumed outside the app (installed on computers) or are physical → purchases via Shopify checkout with the methods of section 2 are permitted; no IAP. The app must not gate any in-app functionality behind a purchase. Prepare `APP_STORE_REVIEW_NOTES.md` explaining this clearly and neutrally.
- **Minimum functionality:** native UI, offline-capable catalog, license vault, widgets — never a repackaged website.
- **Sign in with Apple:** not required as long as the only login is Shopify's own passwordless account; do not add third-party social logins.
- **Review access:** provide a reviewer account, a test product priced at the minimum, and a 100% discount code so reviewers can complete checkout without real charges (owner creates the code).
- **Metadata:** App name "KARINEX", subtitle, keywords, descriptions in DE, EN and the other supported store languages; screenshot plan (6.9" and 6.5") per language; privacy labels; age rating; export compliance (standard encryption only).
- Bundle ID `{{BUNDLE_ID}}` (suggested `de.karinex.app`), team `{{APPLE_TEAM_ID}}`.

---

## 11. SECURITY

- Only the public Storefront token ships in the binary, injected from a git-ignored `.xcconfig`. Never embed Admin API tokens, backend secrets or APNs keys.
- Customer tokens and cached license keys in Keychain with device-only accessibility; wipe on logout and on account deletion.
- License keys: privacy overlay when the app is backgrounded, optional Face ID/Touch ID gate, clipboard copy with expiration and `localOnly`.
- ATS enforced; optional certificate pinning for the KARINEX backend host.
- No PII in logs; structured logging with categories; redaction helpers.
- Jailbreak detection is not required.

---

## 12. BACKEND CONTRACT (BFF on the existing KARINEX fulfillment service)

Base URL `{{BFF_BASE_URL}}`. Authentication: `Authorization: Bearer <Customer Account API access token>`. The backend validates the token by calling the Customer Account API (`customer { id emailAddress { emailAddress } }`), then resolves order ownership via its own Admin API access. Rate-limit per token, audit-log every key read.

- `GET /v1/app/config` → `{ supportHours, whatsappNumber, liveChatUrl, featureFlags, homeBanners, minSupportedAppVersion }` (lets the owner change support info and flags without an app release; cache with ETag).
- `GET /v1/app/orders` → list of the customer's orders with `deliveryStatus` (`pending|delivered|shipped`) and `hasLicenses`.
- `GET /v1/app/orders/{orderId}/licenses` → `[{ lineItemId, productTitle, sku, key, deliveredAt, activationGuideUrl }]` (only for orders owned by the token's customer; `403` otherwise; `202` while delivery is pending).
- `GET /v1/app/orders/{orderId}/invoice` → `{ url, expiresAt }` (short-lived signed PDF URL).
- `POST /v1/app/devices` → `{ apnsToken, locale, country, consent: { orderUpdates, deals } }`; `DELETE /v1/app/devices/{token}`.
- `POST /v1/app/account/delete` → starts the GDPR erasure workflow; responds `202`.
- Push payloads: `order.paid`, `license.delivered` (ends Live Activity), `deal.started` (only with deals consent).

Write `BFF_CONTRACT.md` with JSON schemas, error format `{ code, message, requestId }`, and an OpenAPI 3.1 file. Until the backend exists, ship the app against a local mock server and fixtures; the Licenses screen must show a graceful "Ihr Schlüssel wurde per E-Mail zugestellt" fallback if the endpoint is unavailable.

---

## 13. PERFORMANCE, QUALITY, ACCESSIBILITY

- Cold start to first meaningful content < 1.5 s on iPhone 13; skeletons within 100 ms; image prefetch for the next row; cart preloaded before checkout tap.
- No main-thread I/O, no layout thrash; measure with Instruments and MetricKit; document budgets in `PERFORMANCE.md`.
- Accessibility: full VoiceOver labels/traits, Dynamic Type up to accessibility sizes, logical focus order, 44pt targets, Reduce Motion/Transparency, high-contrast check of every token pair, localized accessibility strings.
- Test pyramid: unit (view models, repositories, GraphQL mapping with recorded fixtures), snapshot (DesignSystem, light/dark, 3 text sizes, DE + FI), UI tests (critical path), contract tests against the mock BFF.
- Zero compiler warnings, SwiftLint + SwiftFormat configured, code coverage report in CI.

---

## 14. DELIVERY PLAN

**Phase 0 — Foundation (week 1):** verify API versions and Checkout Kit release; create workspace and packages; design tokens, typography, core components with previews; GraphQL client with fixtures; CI green; `ARCHITECTURE.md`.
Definition of done: app launches to a tokenized empty shell in light/dark, all packages build, tests run in CI.

**Phase 1 — Commerce core (weeks 2–3):** Home, Shop, Product detail, Search, Cart, Checkout Kit, deep links, DE + EN. TestFlight build 1.
DoD: a user can browse, filter, add to cart and complete a real checkout with Apple Pay on device; product screen shows metafield specs, FAQ, comparison, refund conditions.

**Phase 2 — Account and licenses (weeks 4–5):** Customer Account login, orders, addresses, license vault via BFF (with mock), invoices, support hub, legal pages, settings, account deletion, all 11 languages. TestFlight build 2.
DoD: logged-in user sees orders and keys, copies a key, downloads an invoice, contacts support with order context; localization QA passed.

**Phase 3 — Delight and launch (week 6):** push notifications, widget, Live Activity, wishlist, iPad adaptive polish, accessibility audit, performance pass, App Store metadata in all languages, review notes, screenshots plan, submission.
DoD: App Store submission package complete; zero P1 bugs; all budgets met.

---

## 15. INPUTS THE OWNER MUST PROVIDE (fill before Phase 0)

- `{{SHOP}}` = myshopify subdomain and `{{SHOP_ID}}`; `{{STOREFRONT_PUBLIC_TOKEN}}` (Headless/custom app, Storefront API, unauthenticated read scopes for products, collections, content, localization; cart scopes)
- `{{STOREFRONT_VERSION}}` and `{{CUSTOMER_ACCOUNT_VERSION}}` (latest stable on start date; 2026-07 or 2026-10)
- `{{CUSTOMER_ACCOUNT_CLIENT_ID}}`, `{{CUSTOMER_ACCOUNT_REDIRECT_URI}}` (custom scheme or Universal Link registered in the Customer Account API settings)
- `{{WHATSAPP_NUMBER}}` (international format, WhatsApp only, never shown as a phone number), `{{LIVE_CHAT_URL}}`
- `{{BFF_BASE_URL}}` (Railway service), APNs key handled server-side
- `{{BUNDLE_ID}}`, `{{APPLE_TEAM_ID}}`, App Store Connect access, Universal Links entitlement for `karinex.de` (`apple-app-site-association` deployed on the domain)
- Confirmed collection handles (windows, office, server, bestseller, blitzangebote), page handle for Impressum, blog handle, metafield definitions as listed in 5.1
- Brand assets: logo (delivered: the store logo), app icon (the white store logo on black until a dedicated icon arrives)
- Reviewer account, test product and 100% discount code for App Review

---

## 16. DELIVERABLES

- Xcode workspace with SPM packages as in section 4, `.xcconfig` templates, `fastlane/` or Xcode Cloud config, GitHub Actions workflow.
- Documentation: `README.md`, `ARCHITECTURE.md`, `SECURITY.md`, `LOCALIZATION.md`, `PERFORMANCE.md`, `BFF_CONTRACT.md` + `openapi.yaml`, `APP_STORE_REVIEW_NOTES.md`, `PRIVACY_NUTRITION_LABEL.md`, `CHANGELOG.md`.
- Test suites and fixtures recorded from the live Storefront API (anonymized), mock BFF server (Node or Swift) for local development.
- App Store metadata files per language and a screenshot shot list.

---

## 17. WORKING RULES FOR THE AGENT

1. Start by restating the plan for the current phase, listing assumptions and the exact API versions you verified (with URLs). Ask only for missing credentials or genuinely ambiguous product decisions; otherwise decide and document.
2. Build in small, compiling increments. After every feature: build, run tests, fix warnings, then report what changed and what is next.
3. Use real Storefront API responses (recorded into fixtures) for models and previews; never invent product data, prices, ratings or claims.
4. Every user-facing string goes through the String Catalog from day one. German source strings follow the tone rules in section 3.6.
5. Never weaken the hard rules in section 3 for convenience. If a rule blocks you, explain the conflict and propose an alternative that keeps the rule.
6. Keep `CHANGELOG.md` and `ARCHITECTURE.md` current. Leave the repository in a state a senior iOS engineer could take over in an afternoon.

Begin with Phase 0.
