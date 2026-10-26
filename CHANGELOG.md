# Changelog

All notable changes to the KARINEX iOS app are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The version is
`MARKETING_VERSION` in `Config/Base.xcconfig`; TestFlight build numbers are assigned by the
fastlane `beta` lane. Update this file and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) with every
change.

## [Unreleased]

### Added

- **Recently sold on the product page:** "In den letzten 30 Tagen 109-mal verkauft" as an icon
  row below availability and delivery, from the store's `custom.recently_sold_count` and
  `custom.recently_sold_hours` (`ProductMetafields.recentSales`), from 5 units on, in all 11
  languages. `Tools/AppsScript/RecentlySold.gs` is the corrected store script: real quantities
  instead of the former ×10.5 display multiplier, the Admin token in the script properties, and
  stale values deleted. The row appears once the definitions get Storefront access.

### Changed

- **New look, "KARINEX Clean"** (owner decision after the first TestFlight build): the green,
  cream and gold "Editorial Luxe" design is replaced by a monochrome, photo-first design in the
  style of fashion retail apps. White pages, black type and capsule buttons, flat light grey
  panels, one sale red for savings and deals, every text in SF Pro (no serif). Dark mode is black
  with white buttons. App icon: the white KARINEX store logo on black.
- **Product photos edge to edge:** `.kxPhotoTile()` shows a photo on a light grey tile with a
  multiply blend, so white studio backgrounds disappear into the tile. Product cards are square
  photo tiles without card, border or shadow, with a regular two-line title.
- **Product page:** full-width gallery with page dots and the wishlist heart on the photo, bold
  title, availability and delivery as icon rows, ink pills for variants, "Jetzt kaufen" as an
  outlined button below them, "So läuft es ab" and the activation instructions as collapsible
  rows, and a calm bottom bar with the price and one black "In den Warenkorb" button.
- The tab bar keeps the system design with its titles (Start, Shop, Suche, Warenkorb, Konto),
  now tinted black. The Warenkorb tab shows a shopping bag with the number of items as a small
  figure beside it, in the tab's color, instead of a red badge (`CartTabIcon`, owner request,
  as in the About You app); VoiceOver still reads the number as the tab's value.
- **Opening like a fashion retail app:** the launch screen shows the store logo (`LaunchLogo`)
  and `KXLaunchIntro` zooms into it and reveals the Start tab in under one second (only a fade
  with Reduce Motion, skipped in UI test runs).
- **Start tab like About You, with our products** (owner request): the KARINEX logo with the
  Merkliste heart (number of saved products beside it) scrolls away, the search field stays
  pinned at the top and opens the Suche tab with the cursor in the field (`SearchView`
  `fieldActivation`, `AppRouter.searchFieldRequests`). Below it a story carousel of featured
  collections (bestsellers, Windows, Office, Server, Entwicklung): one large rounded panel in
  which the stories page sideways, each with the photo of the collection's first product, a tag,
  four product tiles and "Kategorie entdecken", and fixed page dots. The panel is the KARINEX store
  color `#0E4343` (`TintToken.store`, `KXColor.storePanel`, owner request), with light text
  that meets WCAG AA. Then the trust facts as icon rows, "Unsere Kategorien"
  (category tiles above a product panel in the store color), the bestsellers,
  the sale panel in the store color, "Zuletzt angesehen", "Nach Version finden" (Windows 11, Windows 10,
  Office 2024, Office 2021), service tiles into the account area (help, licenses, orders), the
  Ratgeber as tall story tiles and the support card. The modules and their store collections are
  described by `HomeModules`; the hero with "Zum Sortiment" is gone, and so is the chip bar
  above the tab bar (owner request).
- **Removing a cart line like About You** (owner request): swiping a line to the left uncovers
  a red "Entfernen"; a long swipe, a tap on it or on the "x" turns the line red with "Produkt
  wird entfernt…" and an outlined "Abbrechen" whose fill runs down for 3 seconds (10 with
  VoiceOver) before the line leaves the cart. This replaces the undo bar at the bottom; the
  line also offers "Entfernen" as a VoiceOver action.
- **Office für Mac in the story carousel** (owner request): the Start tab's story panel pages
  through Bestseller, Windows, Office, Office für Mac (`microsoft-office-fur-mac`), Server and
  Entwicklung.
- **Saving with the heart like About You** (owner request): the heart on the product photo
  sits on a white disc; saving fills it from the center, springs it a little larger and lets
  four small hearts burst to the upper left and lower right (`ProductWishlistButton`,
  `ProductHeartBurst`, timings in `MotionToken.heart*`). With Reduce Motion it only switches.
- **Cart bag like About You** (owner request): the Warenkorb tab and the product page bar show
  the outline tote of the About You cart, a straight top edge, sides that widen slightly toward
  the rounded bottom and a tall round handle in one even 1.67 pt line, 22 points high
  (`CartBagShape`, its proportions measured from the About You app), with the number of items
  beside it in the new `figure` type style (11 pt semibold, tabular digits; `CartBagIcon` in
  CommerceUI, used by the tab icon); the other tab symbols stay as they are.
- **Cart lines like the lists of About You** (owner request): each line shows the photo on its
  light tile with the reduction in sale red at its lower edge, the vendor in capitals, the
  title, the price in sale red with "Ursprünglich" and the former price below it, the quantity
  control and an "x" at the top right that removes the line (with undo). The lines form a list
  with hairlines instead of a grey card. The photo, the title and the price now all open the
  product (before, only the title did).
- **Product page bar like About You** (owner request): the share arrow and a shopping bag with
  the number of items (it opens the cart, `CartBagIcon` in CommerceUI) sit in the navigation
  bar as plain symbols; on iOS 26 without the glass circle (`ProductToolbar`,
  `sharedBackgroundVisibility(.hidden)`).
- **Storefront token configured** (owner, 2026-10-26): the public token of the "Karinex Headless"
  channel is the default of `KX_STOREFRONT_ACCESS_TOKEN`, so the app now reads the metafields
  (product specs, FAQ, linked products). An empty CI secret no longer overwrites it
  (`write-secrets-xcconfig.sh` writes no line for empty values).
- **Konto tab without grey boxes** (owner request): the promise and the benefits stand on the
  page with their symbols on light grey discs, the menu is a plain list with hairlines and thin
  symbols, and the version moves from the dotted "Über die App" row to a small centered line
  with the store logo at the end of the page.
- **All payment methods of the web shop, centered** (owner request): the product page and the
  cart now show UnionPay and Google Pay (Shopify's MIT-licensed marks, Google Pay only when Shopify
  lists the wallet) and plain marks with the names "Rechnung"
  and "Vorkasse" (localized in all 11 languages) next to Apple Pay, the card brands and Klarna.
  The title and the marks are centered in rows that wrap, as below the buy button of the web
  shop (`KXFlowLayout`), instead of sitting at the left edge. PROMPT.md section 2 lists the new
  methods; PayPal stays excluded.
- **Own category icons** (owner request): the tiles of "Unsere Kategorien" show KARINEX icons
  drawn for the app as SVG instead of system symbols: a display with a snap layout (Windows), a
  page with a bar chart (Office), rack units (Server), a notebook (Office für Mac), an editor
  with the code sign (Entwicklung), a cloud with renewal arrows (Microsoft 365) and tiles with a
  disc (Alle Kategorien), plus a medal (Bestseller) and a price tag (Sale). One style for all:
  24 point grid, 1.5 point lines with round ends and one soft 20 % fill, tinted like text, so
  they turn white on the chosen tile and in dark mode. No third-party logos.
- **Return period is 14 days, not 100** (owner correction): the trust fact on the Start tab, the
  money-back sheet and the product page now say "14 Tage Geld-zurück" in all 11 languages; the
  conditions are unchanged.
- **"Unsere Kategorien" moves on by itself, like the brand strip of About You** (owner
  request): the chosen tile fills with a lighter store color for five seconds
  (`MotionToken.cycleDwellDuration`, `KXColor.storePanelLifted`), then the next category takes
  over with a soft, blurred cross-fade (`KXMotion.Curve.swap`) and the row of tiles glides
  along; after the last category the first one follows. The showcase holds still while it is
  off screen or the app is not active, with VoiceOver, Switch Control or Reduce Motion, in UI
  test runs, and as soon as the customer taps a tile or scrolls the tiles or the products; once
  it has been off screen it moves on again. The panel is about a fifth taller: large cards 184
  points wide with portrait photos (3:4, `ProductRowCardSize.large`) instead of 164 point
  squares. The panels of all categories lie on top of each other, so the height never jumps
  from category to category and every switch shows photos that are already loaded. Row
  skeletons now have the exact shape of the cards (`KXProductCardSkeleton`,
  `ProductRowSkeleton`), so rows keep their height when the products arrive.
- **Shop tab like a top retail app** (owner request): the bestsellers and the sale open the
  tab as two large cards (ink and sale red) with a product photo, the product families follow
  as rows with a short line and the photo of their first product, the single versions as a shelf
  of square photo cards with the short version name ("Office 2024", "Windows Server 2025"),
  every other collection as a list. All photos arrive in the one collections request
  (`CollectionsQuery` now asks each collection for its first three products and keeps the first
  image, `CollectionSummary.previewImage`); a collection without any shows a neutral box. Short names (`CollectionNames`) replace the store's search
  engine titles on the Shop tab, the collection screen and in the search suggestions ("Sale"
  instead of "SALE – Stark reduzierte Angebote", "Visual Studio" instead of "Visual Studio –
  Entwicklungstools"). Cards and rows shrink a little while pressed
  (`.buttonStyle(.kxPress)`, a dim with Reduce Motion).
- **Real payment logos** (owner request): the cart and the product page show the acceptance
  marks of Apple Pay, the card brands and Klarna (the icons of Shopify's MIT-licensed
  `payment_icons` set, as in the web shop footer, PDF assets in CommerceUI) instead of text
  badges. Which ones appear comes from Shopify (`shop.paymentSettings`: accepted card brands and
  Apple Pay as a supported wallet, new `PaymentSettingsQuery` and
  `CatalogRepository.paymentSettings()`), loaded once per launch by `PaymentMethodsStore`;
  until Shopify answers the business facts show (Apple Pay, a neutral card symbol, Klarna).
- **Product details like About You:** the full description from the store is now the first
  collapsible row ("Beschreibung") next to "So läuft es ab" and "Aktivierung", and an opened row
  shows the whole text. Product cards show up to three lines of the product name with the
  space reserved, so names are no longer cut after two lines. The bottom bar of the product
  page shows a small photo of the product next to the price. The tab bar uses outline symbols,
  matching the shopping bag.
- **Sale look like About You** (owner request): reduced prices are sale red next to the
  struck-through former price; product cards show the reduction ("-80 %") as their badge
  instead of "Angebot"; on the product page the reduction badge sits above the price and the
  store's lowest price of the last 30 days (`karinex.lowest_price_30d`, euro cents) follows
  below when Shopify provides it. The sale collection is sale red in the Shop tab.
- **Linked products on the product page** (owner request): the products linked in the web shop
  (list metafield `custom.siblings`, new `Product.linkedProducts`) appear as photo thumbnails
  below the price, the current one outlined in ink; a new "Passend dazu" row shows Shopify's
  `COMPLEMENTARY` recommendations next to "Ähnliche Produkte". Linked products need the
  Storefront token and Storefront access for the metafield (see docs/OWNER_INPUTS.md).
- **Store logo:** `KXWordmark` now draws the KARINEX logo of the web shop (template asset
  `KarinexLogo` in the DesignSystem resources, tinted like text, scaled with Dynamic Type) instead
  of typeset letters. The source file is kept in `Tools/Brand/store-logo.png`, and the app icon
  uses the same logo in white on black.
- **Suche like a fashion retail app:** recent searches as removable grey chips in a scrolling
  row, suggestions as chips, and the categories as grey tiles with the bold name and a real
  product photo of the collection (the first product, loaded from Shopify), with light grey
  bands between the sections and an inline title above the search field.
- Product card prices use the regular weight of the card title.
- Dark-mode greys are exactly neutral (`#1C1C1C`, `#2C2C2C`, `#3A3A3A`).
- Components: chevron accordion, step timeline with ink discs, section headers without the gold
  rule, black license key card, empty states and icons without gold rings, tighter product grids.
- `DesignTokensTests` now also fails when a token other than the status colors and the sale red
  gets a hue. The unused `keyCardAccent` and hero parallax tokens are gone.

### Fixed

- The TestFlight export step no longer fails with `option '-authenticationKeyPath' may only be
  provided once`: fastlane already adds the App Store Connect key flags to the export, so the
  lane stops passing them a second time (`export_xcargs`).
- TestFlight builds now carry `App/KARINEX.entitlements` (Push Notifications and Associated
  Domains for Universal Links): the `beta` lane sets `KX_CODE_SIGN_ENTITLEMENTS` itself and
  `scripts/write-secrets-xcconfig.sh` accepts exactly that value or an empty one. Unsigned CI and
  simulator builds are unchanged.
- `ASC_KEY_CONTENT` accepts the text of the `.p8` file pasted as is (no Terminal needed); the
  base64 form still works. A wrong value fails with a message that does not contain the key.

Phase 3: delight and launch preparation. Written and checked by compilation and unit tests in
CI; push, the widget and the Live Activity need a device, the owner's Apple Team ID and APNs on
the BFF for an end-to-end test.

### Added (Phase 3)

- **Wishlist and recently viewed:** `SavedProductsStore` keeps only product IDs on the device
  (no account needed, nothing leaves the device); `ProductsByIDQuery` (Storefront `nodes`) and
  `ProductLookupRepository` load the products fresh in the current market. Heart button on the
  product page, "Merkliste" in the Konto tab, "Zuletzt angesehen" on Start.
- **Push notifications, strictly opt-in:** `PushRegistrationCoordinator` asks for permission
  and registers with APNs only after the customer turns on "Bestellstatus" or "Angebote" in the
  settings, sends the token and consents to `POST /v1/app/devices`, unregisters when both are
  off, and turns taps into deep links. A hint links to the iOS settings when iOS refused.
- **Widget extension `KARINEXWidgets`:** the bestseller widget (small and medium) from the
  Storefront API, and the "Lizenz wird zugestellt" Live Activity, started after checkout only
  with order update consent and ended by the `license.delivered` push or the BFF delivery state.
- **App Store:** metadata in 11 languages under `fastlane/metadata` with
  `scripts/check_metadata.py` (limits and copy rules, part of `make check` and CI),
  [docs/APP_STORE_REVIEW_NOTES.md](docs/APP_STORE_REVIEW_NOTES.md) and
  [docs/SCREENSHOTS.md](docs/SCREENSHOTS.md).

---

### Phase 2

Phase 2: account and licenses. Shopify customer login, orders, addresses, the license vault,
invoices, support, legal texts, settings and account deletion, in all 11 languages. Written and
checked by compilation, unit tests and the Linux package tests; an end-to-end test needs the
owner's Customer Account client ID and BFF host (see [docs/OWNER_INPUTS.md](docs/OWNER_INPUTS.md)).
Design: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#account-layer-phase-2).

### Added (Phase 2)

- **Core:** SHA-256, base64url and secure random (pure Swift, Linux-buildable);
  `AppConfiguration` reads `KXShopID` (login redirect `shop.<id>.app://callback`) and
  `KXBackendHost`.
- **ShopifyKit:** Customer Account API login (discovery, PKCE S256, `state` and ID token checks,
  code exchange, refresh, Keychain storage, sign-out with the end-session URL), the Customer
  Account GraphQL client and `CustomerAccountRepository` (customer, orders with pagination, order
  detail, addresses with create, update and delete), legal texts (`ShopPoliciesQuery`,
  `PageByHandleQuery`, `LegalContentRepository`).
- **BackendKit (new package `Packages/Backend`):** the BFF client with ETag config, delivery
  states, license keys (HTTP 202 pending), invoice links, account deletion and device
  registration; `UnavailableBackendClient` while no host is configured; `LicenseKeyCache` in the
  Keychain. Keys never appear in descriptions or logs.
- **CommerceUI:** `CustomerSessionStore`, `AppSettingsStore`, `AccountDestination` routes and
  account deep links, error mapping for login and BFF errors.
- **AccountFeature:** the Konto tab with login, orders with status pills and timeline, order
  detail with invoice, keys and help with this order, addresses, sign-out and account deletion.
- **LicensesFeature, SupportFeature, LegalFeature, SettingsFeature** (new feature targets): the
  license vault (masked keys, optional Face ID lock, e-mail fallback), support by WhatsApp,
  e-mail and live chat with the support hours, legal texts from Shopify rendered natively,
  settings for market, language, appearance, privacy consents and the license lock.
- **App:** `AccountServices` wiring, a privacy cover in the app switcher, `NSFaceIDUsageDescription`
  localized through `InfoPlist.xcstrings`.
- **Docs and tools:** [docs/BFF_CONTRACT.md](docs/BFF_CONTRACT.md),
  [docs/openapi.yaml](docs/openapi.yaml), [Tools/MockBFF](Tools/MockBFF) with contract tests (run in
  CI), [docs/PRIVACY_NUTRITION_LABEL.md](docs/PRIVACY_NUTRITION_LABEL.md).

### Changed (Phase 2)

- `PrivacyInfo.xcprivacy` declares name, e-mail address, physical address and purchase history
  (linked, app functionality, no tracking), which the app reads after login.
- The cart UI test finds the line through the lines card and its remove button.

---

### Phase 1

Phase 1: commerce core. Browsing, product detail, search, the cart and checkout through Shopify
Checkout Kit, with market resolution, deep links and the image pipeline. It was written and
checked by compilation and the Linux package tests; the screens and UI tests have not run on a
simulator yet (see Known limitations). Design and decisions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#commerce-layer-phase-1).

### Added

#### ShopifyKit

- Cart model and operations: `cart(id:)`, `cartCreate`, `cartLinesAdd`, `cartLinesUpdate`,
  `cartLinesRemove`, `cartDiscountCodesUpdate`, `cartBuyerIdentityUpdate` and
  `cartAttributesUpdate`, with `userErrors` mapped to typed errors, behind `CartRepository` and
  `StorefrontCartRepository`.
- Catalog: products by handle with metafields, collection products with API-driven filters
  (`ProductFilter`) and sorting, cursor pagination, and `RELATED` recommendations.
- `SearchRepository` (predictive search and product search with pagination) and
  `ContentRepository` (blog articles and article detail).
- A dependency-free native HTML parser (`HTMLDocument`, `HTMLTreeBuilder`, `HTMLEntities`) for
  `descriptionHtml` and article content.

#### CommerceUI (new shared module in `Packages/Features`)

- `CartStore`: the one Shopify cart of the app. The cart ID is cached in `preferences` and
  re-read at launch and on foreground; mutations run serially, quantity taps are coalesced, an
  ambiguous mutation failure re-reads the cart instead of replaying the write, an expired or
  completed cart is forgotten and never rebuilt from its old lines, and the checkout is preloaded
  after every change (debounced).
- `MarketStore`: first-launch market resolution from region and preferred languages, persisted
  `MarketSelection`, `MarketConfirmationSheet`, and the buyer context (market and visitor
  consent) pushed into every Storefront request; a country change moves the cart.
- `CommerceRoute` and `DeepLinkParser` for `karinex://` links and `karinex.de` web URLs
  (`/products/`, `/collections/`, `/blogs/`, `/cart`, `/search`, with locale prefixes).
- `PriceDisplay` (locale-formatted `MoneyV2`, tax wording per market), `ProductCardView`,
  `ProductCarouselSection`, `ArticleScreen`, `RichTextView` (native rendering of Shopify rich
  text; `tel:` links are dropped), `LoadState`, `AsyncContentView` and `UserFacingError`.
- `KXImagePipeline` and `ProductImage` on Nuke 13.2.0: shared pipeline, 150 MB disk cache, the WebP
  `Accept` header, CDN width in pixels, and `ProductImagePrefetcher`.

#### Features

- `ProductFeature`: gallery with zoom viewer, variants, price with market tax note, key facts
  and activation from metafields, "So läuft es ab", native description, related products, FAQ,
  14-day promise with its condition, withdrawal notice for digital goods, sticky purchase bar
  (add to cart, buy now), share. Sections without store data are omitted.
- `CatalogFeature`: collection directory, collection screen with sort, filters and infinite
  scroll. `SearchFeature`: predictive results, recent and suggested searches, category shortcuts,
  results with sort and pagination. `HomeFeature`: live rows for deals, Windows, Office, Server,
  development, bestsellers and guides from one `HomeLayout`.
- `CartFeature`: lines with quantity controls and undo, discount codes, totals, cross-sell,
  payment and digital-goods notices, loading and error states.
- `CheckoutFeature`: `CheckoutCoordinator` (fresh checkout URL at the tap, one automatic retry on
  an expired checkout, cancel keeps the cart, recoverable failures), `CheckoutKitBridge`
  (KARINEX branding, preload; the only Checkout Kit import) and `OrderSuccessScreen`.

#### App

- `AppRouter` with one navigation path per tab, deep link and Universal Link handling
  (`.onOpenURL`), the cart badge, the one-time market confirmation, and `AppContainer` wiring for
  the catalog, search, content and cart repositories, `CartStore` and `MarketStore`.
- `App/KARINEX.entitlements` with `applinks:karinex.de` and `applinks:www.karinex.de`, applied
  once `KX_CODE_SIGN_ENTITLEMENTS` is set together with the team ID; the URL scheme `karinex`.
- Launch argument `-kx.market.confirm YES` to show the market sheet under UI tests.
- `Package.resolved` committed: Checkout Kit 3.9.2, Nuke 13.2.0, swift-snapshot-testing 1.19.6.

#### Localization

- About 300 new strings (`product.*`, `catalog.*`, `search.*`, `home.*`, `cart.*`, `checkout.*`,
  `commerce.*`, `tab.cart.badge`) translated into pl, nl, pt-PT, sv, da, es, fr, it and fi, with
  CLDR plural variations. `scripts/check_strings.py` passes without `--allow-missing-languages`.
  Native-speaker review is still outstanding (Phase 2 exit criterion).

#### Tests

- `CommerceUITests` and `FeaturesTests` for the stores, parser, prices, view models and the
  checkout coordinator; `AppRouterTests`; `CommerceUITests` (XCUITest) for the critical path.

### Changed

- Storefront API and Customer Account API pinned to `2026-10` (latest stable since 2026-10-01);
  fixtures re-recorded.
- Checkout Kit pinned to `3.9.2` (`from: "3.9.2"`).
- The buyer context is no longer fixed to Germany in German: it follows the resolved market.

### Known limitations

- **The Phase 1 screens and XCUITests have never run on a simulator.** Only compilation (iOS 26
  SDK type-check) and the Linux package tests have run. The macOS CI decides what needs fixing,
  after which the DesignSystem and new reference images must be recorded with **Record snapshots**.
- Universal Links stay inactive until the Apple team ID is set and `apple-app-site-association` is
  served on the store domain; the custom scheme works.
- Metafield-driven modules (key facts, FAQ, MPN, deal countdown) stay empty until a Storefront
  token and the metafield definitions exist ([docs/OWNER_INPUTS.md](docs/OWNER_INPUTS.md)).
- Some store product descriptions still mention PayPal and phone support
  ([docs/STORE_AUDIT.md](docs/STORE_AUDIT.md)); the app renders store content as returned and the
  owner must correct it in the store.
- `Package.resolved` still lists `viewinspector` and `swiftlintplugin`, which no package
  references; Xcode removes them on the next resolve.

## [0.1.0] - 2026-09-27

Phase 0: foundation. The workspace, the infrastructure and Storefront layers, the design system
and a tokenized five-tab shell that launches in light and dark mode, with CI and a TestFlight
lane. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and the decisions behind it.

### Added

#### Project and tooling

- XcodeGen specification `project.yml` and the generated, committed `KARINEX.xcodeproj` with the
  app target `KARINEX`, the test targets `KARINEXTests` and `KARINEXUITests`, and one shared
  scheme that runs every app and package test target with code coverage.
- Build settings in `Config/Base.xcconfig`, `Debug.xcconfig` and `Release.xcconfig`: iOS 17.0
  deployment target, Swift 6 with complete strict concurrency, String Catalog settings, German as
  the development language, bundle ID `de.karinex.app`, version 0.1.0, the verified store domains
  and API versions. `Config/Secrets.example.xcconfig` documents the git-ignored secrets.
- `Makefile` with `bootstrap`, `tools`, `project`, `build`, `test`, `test-packages`, `lint`,
  `format`, `check`, `fixtures`, `snapshots` and `clean`.
- SwiftLint (0.65.1) and SwiftFormat (0.63.0) configurations that agree with each other (4 spaces,
  140 columns), including the `no_print_logging` rule, and `.editorconfig`.
- Scripts: `check_strings.py` (String Catalog completeness and key usage), `check_copy_rules.py`
  (no em or en dashes, forbidden words and license claims), `check-warnings.sh` (zero-warning
  gate), `install-tools.sh` (pinned, checksum-verified tools), `select-simulator.sh` and
  `write-secrets-xcconfig.sh`.

#### Core

- `AppConfiguration` read from `Info.plist` with validation of hosts and API versions,
  `ConfigurationError`, computed Storefront, store web and Customer Account discovery URLs, and a
  tokenless `preview` configuration of the live store.
- `AppLanguage`: the 11 UI languages with BCP 47 normalization (`pt-BR` and `pt` to `pt-PT`,
  regional variants to their base language) and endonyms.
- `KXLogger` with `LogCategory`, `LogLevel` and pluggable sinks (`OSLogSink`,
  `StandardErrorLogSink`, `RecordingLogSink`); every message passes through `Redactor`, which masks
  credentials, tokens, JWTs, e-mail addresses, product keys, cart and customer identifiers and
  sensitive query items.
- `HTTPClient`, `HTTPRequest` and `HTTPResponse` (case-insensitive headers, `Retry-After` parsing,
  log-safe descriptions), `URLSessionHTTPClient` with `URLSessionConfiguration.kxDefault`
  (30 s timeout, fail fast offline, 20 MB memory and 100 MB disk cache), and `NetworkError`.
- `RetryPolicy` (exponential backoff with full jitter, `Retry-After` as a lower bound),
  `RetryExecutor`, `RetryDecision`, `Sleeper` and `TaskSleeper`.
- `RequestDeduplicator`, an actor that shares identical in-flight requests.
- `NetworkMonitoring` with `NWPathNetworkMonitor`, `StaticNetworkMonitor` and `ManualNetworkMonitor`.
- `Locked`, an `NSLock`-based replacement for `Mutex` on iOS 17.
- `SecureStore` with `KeychainStore` (device-only, not synchronizable) and `InMemorySecureStore`;
  `KeyValueStore` with `UserDefaultsStore` and `InMemoryKeyValueStore`.
- `PrivacyConsent` (everything off until the user decides), `ConsentStoring` and `ConsentStore`.
- `FeatureFlag`, `FeatureFlags` and `StaticFeatureFlagProvider` with `-kx.flag.<name>` overrides.
- `LaunchEnvironment` for `-kx.uitesting`, `-kx.reset` and `-kx.appearance`.

#### ShopifyKit

- `GraphQLClient` with `GraphQLEndpoint` and `GraphQLOperation`: deterministic request encoding,
  directive injection, retries that never replay a mutation after an ambiguous failure,
  de-duplication of identical in-flight queries, error mapping and logging without variables or
  bodies.
- `StorefrontClient` and `StorefrontConfiguration` with tokenless mode, and the context providers
  `StaticStorefrontContextProvider` and `MutableStorefrontContextProvider`.
- `StorefrontContext` and `VisitorConsent` rendered as `@inContext(country:language:visitorConsent:)`,
  and `ContextInjector`.
- `ShopifyError`, `UserError`, `UserErrorCode`, `UserErrorsPayload`, `GraphQLErrorDetail` and the
  query cost extension.
- Models: `ShopifyID`, `CountryCode`, `LanguageCode`, `CurrencyCode`, `MoneyV2` (exact `Decimal`
  parsing, locale formatting), `ShopifyImage` (CDN `width` renditions, WebP `acceptHeader`),
  `Connection`, `PageInfo`, `Product`, `ProductVariant`, `ProductSummary`, `ProductCollection`,
  `CollectionSummary`, `CollectionReference`, `Metafield`, `ProductMetafields`, `FAQEntry`,
  `Localization`, `Cart`, `CartLineInput` and `AttributeInput`.
- Operations `LocalizationQuery`, `ProductByHandleQuery` (metafields only with a token),
  `CollectionProductsQuery` (with `ProductCollectionSortKeys`) and `CartCreateMutation`, built from
  the fragments in `StorefrontFragments` and validated against the live API.
- Repositories `CatalogRepository`, `LocalizationRepository` and `CartRepository` with their
  Storefront implementations, and `CollectionPage`.
- `MarketResolver`, `MarketSelection` and `MarketResolution`.
- Fixtures recorded from the live store on 2026-09-26 (Storefront API 2026-07, tokenless):
  localization, the Office 2024 Professional Plus product in DE/DE and CH/FR, an unknown product,
  the first 8 bestsellers, a rejected `cartCreate`, the metafields `ACCESS_DENIED` response, plus
  `synthetic_throttled.json` and `manifest.json`.

#### DesignSystem

- `DesignTokens` (pure Swift): `BrandPalette`, `ColorToken` with light and dark values,
  `ContrastRequirement` (every allowed text and UI pairing, tested against WCAG AA in both
  appearances), `TypographyToken`, `SpacingToken`, `RadiusToken`, `BorderToken`, `MotionToken`
  and `RGBAColor`.
- Foundation helpers: `KXColor`, `.kxFont(_:)` and `KXFont` (serif headlines in the system serif),
  `KXSpacing`, `KXRadius`, `KXBorder`, `.kxScreenBackground()`, `.kxGutter()`, `KXMotion` and
  `KXHaptics`.
- Components with previews in light, dark and an accessibility size: `KXButton` and
  `KXButtonStyle`, `KXCard`, `KXBadge`, `KXPriceTag`, `KXSectionHeader`, `KXSpecRow`,
  `KXStepTimeline`, `KXAccordion`, `KXCountdown`, `KXTrustStrip`, `KXProductCard` and
  `KXProductImage`, `KXKeyCard`, `KXClipboard`, `KXSkeleton`, `KXEmptyState`, `KXBanner` with
  `.kxBanner(isPresented:placement:banner:)`, `KXWordmark` and `KXDivider`.
- `KXDesignSystemGallery`, a DEBUG-only catalog of every token and component.
- Snapshot tests for every component with swift-snapshot-testing 1.19.6: light and dark in German,
  and xxxLarge and accessibility sizes in Finnish.
- The DesignSystem String Catalog for component-owned strings (`kx.*`).

#### Features

- `HomeFeature`: `HomeView` with the editorial hero (`KXWordmark`, serif headline, "Zum
  Sortiment" call to action, a gold seal with subtle parallax), the trust strip with the four
  brand facts, the money-back conditions sheet (`MoneyBackConditionSheet`) and the support card
  with channels and service hours.
- `CatalogFeature` (`CatalogView`) and `SearchFeature` (`SearchView`): large-title screens with
  empty states until Phase 1.
- `CartFeature` (`CartView`): the empty cart with "Zum Sortiment", the payment methods as text and
  the right-of-withdrawal notice for digital content.
- `AccountFeature` (`AccountView`): logged-out benefits, version and build, and a DEBUG link to
  the design system gallery.
- A String Catalog per feature and `FeaturesTests` that check the content types in all 11 languages.

#### App

- `KarinexApp`, the composition root `AppContainer` with protocol-typed dependencies injected
  through the SwiftUI environment, `AppServices` (live and in-memory) and
  `ConfigurationResolution` (fallback to the built-in store configuration instead of a crash).
- `RootView` with the five tabs of `AppTab` (Start, Shop, Suche, Warenkorb, Konto), each in its
  own `NavigationStack`, the `AccentColor` tint and the forced appearance of `-kx.appearance`.
- `OfflineBannerModifier` and `OfflineBannerPolicy`: a real offline banner driven by
  `NetworkMonitoring` that keeps navigation bars reachable.
- App icon concept (gold serif "K" monogram with a double gold ring on forest green),
  `AccentColor`, `LaunchBackground`, `PrivacyInfo.xcprivacy` (no tracking) and `Info.plist` with
  the 11 localizations.
- `KARINEXTests` (container, configuration fallback, reset launches, tabs, offline policy) and
  `KARINEXUITests` (`ShellUITests`: tabs, root screens, hero call to action, money-back sheet,
  offline banner, dark appearance).

#### Localization

- All 97 app strings in the 11 UI languages (German source, English, Polish, Dutch, European
  Portuguese, Swedish, Danish, Spanish, French, Italian, Finnish), each translated by one
  localizer and reviewed by another against `docs/LOCALIZATION.md`, with translator comments on
  every key. `scripts/check_strings.py` enforces completeness, CLDR plural categories, format
  specifier parity and Xcode's rule that plural variations reference the number.

#### Tools

- `Tools/FixtureRecorder`: the `fixture-recorder` command (`make fixtures`) that records the
  ShopifyKit fixtures from the live store with the real client, anonymizes customer data and
  writes `manifest.json`; runs on macOS and Linux.

#### CI/CD

- `.github/workflows/ci.yml` with the jobs `packages-linux` (Swift 6.4, warnings as errors),
  `checks` (String Catalogs, copy rules, SwiftFormat, SwiftLint `--strict`) and `ios` (project
  sync check, build and all tests on the newest iPhone simulator, zero-warning gate, coverage
  summary).
- `.github/workflows/record-snapshots.yml` to record and commit snapshot references on the CI
  runner.
- `.github/workflows/testflight.yml` and `fastlane/Fastfile` (`tests` and `beta` lanes) for signed
  TestFlight uploads with automatic build numbers; `Gemfile`; Dependabot for GitHub Actions.

#### Documentation

- `README.md`, `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/API_VERSIONS.md`,
  `docs/STORE_AUDIT.md`, `docs/OWNER_INPUTS.md`, `docs/SECURITY.md`, `docs/LOCALIZATION.md`,
  `docs/PERFORMANCE.md`, and READMEs for the fixtures and the fixture recorder.

### Verified versions

Verified on 2026-09-26; evidence and upgrade procedure in
[docs/API_VERSIONS.md](docs/API_VERSIONS.md).

| Item | Version | Status |
| --- | --- | --- |
| Shopify Storefront API | `2026-07` | In use |
| Shopify Customer Account API | `2026-07` | Configured, used from Phase 2 |
| Checkout Kit (`checkout-sheet-kit-swift`) | `3.9.0` | Added in Phase 1 |
| Nuke | `13.2.0` | Added in Phase 1 |
| swift-snapshot-testing | `1.19.6` | In use (DesignSystem tests) |
| Swift toolchain (Linux CI) | `6.4.0` | In use |
| Xcode (macOS CI) | latest stable on `macos-26` (26.x) | In use |
| XcodeGen | `2.46.0` | In use |
| SwiftLint | `0.65.1` | In use |
| SwiftFormat | `0.63.0` | In use |
| fastlane | `~> 2.240` (Ruby 3.4) | In use |

### Known limitations

- **Tokenless mode until a Storefront token is provided.** Without `KX_STOREFRONT_ACCESS_TOKEN`
  the app cannot read metafields, so specs, FAQs, MPNs and deal end dates are unavailable, and
  requests are limited to a query cost of 1000. The values also need metafield definitions with
  Storefront access ([docs/STORE_AUDIT.md](docs/STORE_AUDIT.md), owner actions 1 to 3).
- **Snapshot references come from CI.** The 84 DesignSystem reference images were recorded on
  2026-09-27 by the `record-snapshots` workflow on the CI runner (Xcode 26.6, iPhone 17 simulator,
  iOS 26.5). Local runs on a different Xcode or simulator can differ by a few pixels; after every
  visual change, run the workflow again and review the committed images.
- **Store content conflicts listed in [docs/STORE_AUDIT.md](docs/STORE_AUDIT.md).** Some product
  descriptions contain payment method and support channel wording that contradicts the business
  facts, some titles use license-origin wording, several collection and page handles differ from
  PROMPT.md, and every stored deal end date has expired. The app renders store content as
  returned; these need fixing in the store.
- The buyer context is fixed to Germany in German; the market resolution at first launch arrives
  in Phase 1.
- Product images load through `AsyncImage`, which cannot request WebP; the Nuke pipeline with the
  WebP `Accept` header arrives in Phase 1.
- Shop and Search show empty states, the cart is always empty, and there is no login or license
  vault yet (Phases 1 and 2).
- No translation has had the native-speaker review that PROMPT.md 14 requires as a Phase 2 exit
  criterion ([docs/LOCALIZATION.md](docs/LOCALIZATION.md)).

