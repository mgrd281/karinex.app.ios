# Architecture

How the KARINEX iOS app is built, why it is built that way, and where each responsibility
lives. This file describes the code as it is at the end of Phase 0 (version 0.1.0). Keep it
current with every change (see [CLAUDE.md](../CLAUDE.md)); the product specification is
[PROMPT.md](../PROMPT.md).

## Contents

1. [Purpose](#purpose)
2. [Module graph and dependency rules](#module-graph-and-dependency-rules)
3. [Composition root and dependency injection](#composition-root-and-dependency-injection)
4. [Data flow](#data-flow)
5. [Networking](#networking)
6. [Tokenless mode and metafields](#tokenless-mode-and-metafields)
7. [Markets and languages](#markets-and-languages)
8. [Design system](#design-system)
9. [Images](#images)
10. [Security and privacy](#security-and-privacy)
11. [Localization](#localization)
12. [Testing strategy](#testing-strategy)
13. [CI/CD](#cicd)
14. [Decisions](#decisions)
15. [Roadmap](#roadmap)

## Purpose

KARINEX is the native iOS app of the Shopify store [karinex.de](https://www.karinex.de), which
sells Microsoft software licenses (mostly digital keys delivered by e-mail) to consumers in 28
European countries. The app is a headless Shopify client: catalog, prices, cart and checkout
come live from the Shopify Storefront API and Checkout Kit, accounts from the Customer Account
API, and license keys and invoices from the KARINEX backend (BFF). Nothing product-related is
hardcoded.

The architecture serves four goals:

- **Correctness toward the store.** Shopify is the only source of product truth, mutations are
  never replayed, and money is shown exactly as Shopify returns it.
- **Privacy and safety by default.** No tracking, no PII in logs, secrets only in the Keychain,
  consent off until the user opts in.
- **A premium, localized UI.** One design system with tested tokens, 11 UI languages, Dynamic
  Type and dark mode everywhere.
- **A codebase a senior engineer can take over in an afternoon.** Small modules with enforced
  boundaries, protocol-typed dependencies, deterministic tests, and CI that fails on warnings.

Phase 0 delivers the foundation: the module structure, the infrastructure (configuration,
logging, HTTP, retry, storage, consent, flags), the Storefront GraphQL client with live
fixtures, the design system with its gallery and snapshot tests, and a tokenized five-tab shell
that launches in light and dark mode.

## Module graph and dependency rules

```
               +---------------------------------------------------+
               | App target KARINEX (App/Sources)                  |
               | KarinexApp, AppContainer, AppServices,            |
               | ConfigurationResolution, RootView, AppTab,        |
               | OfflineBannerModifier                             |
               +---------------------------------------------------+
                  |                                             |
                  | imports the feature roots                   | also links Core, ShopifyKit,
                  v                                             | DesignSystem, DesignTokens
   +-----------------------------------------------+            |
   | Packages/Features (one target per feature)    |            |
   |                                               |            |
   |   HomeFeature      CatalogFeature             |            |
   |   SearchFeature    CartFeature                |            |
   |   AccountFeature                              |            |
   |                                               |            |
   |   no feature imports another feature          |            |
   +-----------------------------------------------+            |
          |                    |                 |              |
          v                    v                 |              |
   +------------------+  +------------------+    |              |
   | DesignSystem     |  | ShopifyKit       |    |              |
   | SwiftUI, iOS 17  |  | Foundation only  |    |              |
   +------------------+  +------------------+    |              |
          |                    |                 |              |
          v                    v                 v              v
   +------------------+  +--------------------------------------------+
   | DesignTokens     |  | Core                                       |
   | pure Swift       |  | Foundation only                            |
   +------------------+  +--------------------------------------------+

   Tools/FixtureRecorder (executable, macOS and Linux) --> ShopifyKit, Core
```

| Module | Package | Depends on | Builds on Linux | Responsibility |
| --- | --- | --- | --- | --- |
| `Core` | `Packages/Core` | Foundation | yes | `AppConfiguration`, `KXLogger` and `Redactor`, `HTTPClient` and `URLSessionHTTPClient`, `RetryPolicy` and `RetryExecutor`, `RequestDeduplicator`, `NetworkMonitoring`, `Locked`, `SecureStore` and `KeyValueStore`, `PrivacyConsent`, `FeatureFlags`, `LaunchEnvironment`, `AppLanguage` |
| `ShopifyKit` | `Packages/ShopifyKit` | `Core` | yes | `GraphQLClient`, `StorefrontClient`, `@inContext` (`StorefrontContext`, `ContextInjector`), `ShopifyError`, models, operations, repositories, `MarketResolver`, recorded fixtures |
| `DesignTokens` | `Packages/DesignSystem` | Foundation | yes | `BrandPalette`, `ColorToken`, `ContrastRequirement`, `TypographyToken`, spacing, radius, border and motion tokens, `RGBAColor` with WCAG math |
| `DesignSystem` | `Packages/DesignSystem` | `DesignTokens` | no (SwiftUI) | `KXColor`, `.kxFont(_:)`, layout and motion helpers, the `KX*` components, `KXDesignSystemGallery` |
| `HomeFeature`, `CatalogFeature`, `SearchFeature`, `CartFeature`, `AccountFeature` | `Packages/Features` | `Core`, `DesignSystem`, `ShopifyKit` | no (SwiftUI) | One tab each, with its own String Catalog |
| `KARINEX` (App target) | `project.yml` | everything above | no | Composition root, tab shell, app resources |
| `FixtureRecording`, `fixture-recorder` | `Tools/FixtureRecorder` | `Core`, `ShopifyKit` | yes | Records the ShopifyKit fixtures from the live store |

### Dependency rules

1. **Features never depend on each other.** `Packages/Features/Package.swift` generates every
   feature target from one list with the same three dependencies (`Core`, `DesignSystem`,
   `ShopifyKit`), so an import of another feature does not compile. Cross-feature navigation
   goes through closures that the App passes in: `HomeView(onBrowse:)` and
   `CartView(onBrowse:)` switch the root `AppTab` to `.shop`. Deep links (Phase 1) are resolved
   in the App target, which then selects a tab and pushes a route.
2. **Core has no Shopify knowledge.** Core knows nothing about GraphQL, Storefront types or
   Shopify API semantics. It only carries store configuration values as plain strings
   (`AppConfiguration.shopDomain`, `storefrontAPIVersion`, `storefrontEndpoint`) and, in
   `Redactor`, the textual formats of Shopify credentials and cart tokens so that logs are safe
   in every module. Everything that speaks GraphQL lives in ShopifyKit, so the Customer Account
   API and the BFF client can reuse Core without pulling in Storefront code.
3. **DesignSystem has no ShopifyKit dependency** (and no Core dependency). Components take
   plain, already localized and already formatted values: `KXProductCardModel` holds strings and
   an image URL, `KXPriceTag` takes price strings. Features map ShopifyKit models to them
   (`MoneyV2.formatted(locale:)`, `ShopifyImage.url(width:)`). This keeps the components
   reusable, previewable with recorded sample strings, and snapshot-testable without a network.
4. **DesignTokens is platform-free.** It imports only Foundation (for `pow` in the WCAG math),
   never UIKit or SwiftUI, so the palette and the contrast rules build and run under
   `swift test` on Linux. `Packages/DesignSystem/Package.swift` declares the SwiftUI
   `DesignSystem` target (and its snapshot tests) only when not building on Linux.
5. **Only the App target composes.** Concrete implementations (`KeychainStore`,
   `UserDefaultsStore`, `NWPathNetworkMonitor`, `URLSessionHTTPClient`,
   `StorefrontCatalogRepository`, ...) are instantiated in `AppContainer` and `AppServices`.
   Features receive protocols, values and closures through their initializers.
6. **Core, ShopifyKit and DesignTokens stay Linux-buildable.** Platform APIs are guarded with
   `#if canImport(FoundationNetworking)`, `canImport(Security)`, `canImport(Network)` and
   `canImport(os)`. The `packages-linux` CI job enforces this.

## Composition root and dependency injection

The composition root is `AppContainer` (`App/Sources/Composition/AppContainer.swift`), a
`@MainActor @Observable final class` built once per process by `KarinexApp`:

```swift
@main
struct KarinexApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
        }
    }
}
```

`RootView` reads it with `@Environment(AppContainer.self)` and hands each screen only what it
needs, for example `AccountView(appVersion: container.configuration.appVersion, buildNumber:
container.configuration.buildNumber)`. Feature modules never see the container itself, which
keeps them testable and prevents a service locator from spreading through the code.

### What the container holds

Every long-lived dependency is exposed as a protocol-typed property:

| Property | Type | Live implementation |
| --- | --- | --- |
| `configuration` | `AppConfiguration` | from `Info.plist` via `ConfigurationResolution` |
| `secureStore` | `any SecureStore` | `KeychainStore` (service `de.karinex.app`) |
| `preferences` | `any KeyValueStore` | `UserDefaultsStore` |
| `consentStore` | `any ConsentStoring` | `ConsentStore` on `preferences` (key `privacy.consent.v1`) |
| `featureFlags` | `any FeatureFlagProviding` | `StaticFeatureFlagProvider(launchArguments:)`, all flags off by default |
| `networkMonitor` | `any NetworkMonitoring` | `NWPathNetworkMonitor` (a `StaticNetworkMonitor` under UI tests) |
| `httpClient` | `any HTTPClient` | one shared `URLSessionHTTPClient` (it owns the URL cache) |
| `storefrontClient` | `StorefrontClient` | tokenless unless a token is configured |
| `storefrontContextProvider` | `MutableStorefrontContextProvider` | Germany in German with the stored visitor consent |
| `catalogRepository` | `any CatalogRepository` | `StorefrontCatalogRepository` |
| `localizationRepository` | `any LocalizationRepository` | `StorefrontLocalizationRepository` |

Platform services are grouped in `AppServices` (`App/Sources/Composition/AppServices.swift`):
`AppServices.live(launchEnvironment:arguments:bundleIdentifier:)` for the app and
`AppServices.inMemory(networkStatus:)` for previews and tests (`InMemorySecureStore`,
`InMemoryKeyValueStore`, `StaticNetworkMonitor`, an ephemeral `URLSession`). The container has
two factories: `AppContainer.live(bundle:processInfo:)` and `AppContainer.preview(networkStatus:)`.
Tests call the designated initializer directly with a `RecordingLogSink`.

`StorefrontCartRepository` exists in ShopifyKit but is not wired into the container yet; the
cart arrives in Phase 1.

### Configuration

```
Config/Base.xcconfig + Config/Secrets.xcconfig (git-ignored)
        |  build settings KX_SHOP_DOMAIN, KX_STOREFRONT_API_VERSION, ...
        v
App/Info.plist  KXShopDomain = $(KX_SHOP_DOMAIN), KXStorefrontAccessToken = $(KX_STOREFRONT_ACCESS_TOKEN), ...
        |
        v
AppConfiguration(infoDictionary:)  validates hosts and API versions (YYYY-01/04/07/10)
        |  throws ConfigurationError
        v
ConfigurationResolution  on failure: AppConfiguration.preview (live store, tokenless)
                         with the real version and build number, and a logged error
```

A broken build configuration never crashes the app. Empty strings and unresolved `$(VAR)`
values become `nil` for optional keys (token, client ID) and are errors for required ones.
`AppConfiguration` and `StorefrontConfiguration` print only whether a token is configured,
never the token.

### Launch switches

`LaunchEnvironment` (Core) and `AppServices` read these arguments, which the UI tests and Xcode
schemes use:

| Argument | Environment variable | Effect |
| --- | --- | --- |
| `-kx.uitesting` | `KX_UI_TESTING=1` | Deterministic UI test mode; the network status is fixed (online) |
| `-kx.offline` | | Only with `-kx.uitesting`: reports the device as offline to exercise the offline banner |
| `-kx.reset` | `KX_RESET_STATE=1` | Wipes preferences, consent and this app's Keychain items before anything is read |
| `-kx.appearance light` or `dark` | `KX_APPEARANCE` | Forces a color scheme (`RootView` applies it with `.preferredColorScheme`) |
| `-kx.flag.<name> YES` or `NO` | | Overrides a `FeatureFlag` (`licenseVault`, `wishlist`, `pushNotifications`, `liveActivity`, `homeWidget`, `remoteConfig`) |

## Data flow

The app follows MVVM with repositories and a unidirectional data flow:

```
  SwiftUI view (@MainActor)
      |  intent: a method call (load, refresh, addToCart)          ^  state
      v                                                            |
  view model (@Observable, @MainActor, one per screen)  -----------+
      |  async call through a protocol
      v
  repository protocol: CatalogRepository, LocalizationRepository, CartRepository
      |  Storefront* implementation reads the current StorefrontContext
      v
  StorefrontClient  ->  GraphQLClient  ->  HTTPClient (URLSessionHTTPClient)  ->  Shopify
```

- Views render state and forward user intents; they never call repositories or clients.
- View models own the screen state, call repository protocols with `async/await`, and turn the
  result (a typed model such as `Product`, `CollectionPage`, `Localization`, `Cart`, or a
  `ShopifyError`) into a new state value. Structured concurrency only: loading work runs in the
  view's `.task`, so it is cancelled when the view disappears.
- Repositories are stateless translators between operations and models. They read the buyer
  context from `StorefrontContextProviding` on every call, so a market or consent change applies
  to the next request without rebuilding anything.
- Navigation between features is a closure or a typed route owned by the App, never a direct
  reference to another feature.

**Phase 0 status.** The five tab roots show fixed, localized business content, so they need no
view models yet. The logic they do have lives in small value types that `FeaturesTests` cover:
`HomeTrustFact`, `MoneyBackClause` and `SupportChannel` (HomeFeature), `AccountBenefit` and
`AccountAppInfo` (AccountFeature). The first view models arrive with the Phase 1 catalog,
product and cart screens.

## Networking

Three layers, each with one job:

| Layer | Type | Module | Job |
| --- | --- | --- | --- |
| Transport | `HTTPClient` protocol, `URLSessionHTTPClient` | Core | Send an `HTTPRequest`, return every `HTTPResponse` (non-2xx included), map failures without a response to `NetworkError` |
| GraphQL | `GraphQLClient`, `GraphQLEndpoint`, `GraphQLOperation` | ShopifyKit | Encode, inject directives, retry, de-duplicate, decode, map errors, log |
| Storefront | `StorefrontClient`, `StorefrontConfiguration` | ShopifyKit | Endpoint and token header, and an `@inContext` directive on every call |

### URLSessionHTTPClient

`URLSessionHTTPClient` wraps one `URLSession` built from `URLSessionConfiguration.kxDefault`:
persistent (not ephemeral), `waitsForConnectivity = false` so offline requests fail fast, a
30 second request timeout, and a dedicated `URLCache` of 20 MB in memory and 100 MB on disk in
`Library/Caches/de.karinex.urlcache`. It does not throw for HTTP errors: interpreting status
codes is the job of the API layer. `URLError` codes map to `NetworkError` (`offline`,
`timeout`, `cancelled`, `transport(code:)`, `invalidResponse`); `notConnectedToInternet`,
`networkConnectionLost`, `cannotFindHost`, `cannotConnectToHost` and similar codes become
`.offline`. `HTTPRequest` and `HTTPResponse` have log-safe descriptions and mirrors: query values
and credential headers are masked and bodies appear only as a byte count.

### GraphQLClient

`GraphQLClient.execute(_:directive:)` runs a `GraphQLOperation` (a type with `operationName`,
`kind` (`.query` or `.mutation`), a static `document` and typed `Variables` and
`ResponseData`):

1. inserts the optional directive with `ContextInjector.inject(_:into:)`,
2. encodes `{"query", "operationName", "variables"}` with sorted keys, so identical operations
   produce identical bytes,
3. adds the endpoint's static headers, the per-call `authorization` headers (Phase 2 bearer
   tokens), `Content-Type` and `Accept: application/json`,
4. sends with retries (below), sharing identical in-flight queries,
5. decodes `data`, `errors` and `extensions` and maps failures to `ShopifyError`,
6. logs operation name, status, duration, attempts and query cost at debug level. Variables,
   headers and bodies are never logged.

The endpoint is API-agnostic (`GraphQLEndpoint(url:headers:timeout:authorization:)`), so the
Customer Account API client of Phase 2 reuses the same client with a bearer token supplier and
no `@inContext`.

### @inContext and visitor consent

Operation documents are written **without** `@inContext`. `StorefrontClient.execute(_:context:)`
always renders the directive from a `StorefrontContext(country:language:visitorConsent:)` and
`ContextInjector` inserts it before the operation's selection set, skipping comments, strings,
variable definitions with default values and leading fragments:

```
query ProductByHandle(...) @inContext(country: DE, language: DE, visitorConsent: {analytics: false, preferences: true, marketing: false, saleOfData: false}) { ... }
```

`VisitorConsent(privacyConsent:)` maps the user's `PrivacyConsent`: `analytics` follows the
analytics opt-in, `preferences` is always `true` (remembering language and market is needed for
the store to work), `marketing` and `saleOfData` are always `false`. The consent is supported
from Storefront API 2025-10 on; Shopify encodes it into the cart's `checkoutUrl`, so checkout
(Checkout Kit, Phase 1) applies the same tracking rules. The container builds the initial
context from `MarketSelection.germany` and the stored consent; `MutableStorefrontContextProvider.update(to:)`
replaces it when the market or the consent changes.

### Retry rules

`RetryPolicy.default` allows 3 attempts in total with exponential backoff and full jitter
(random delay up to `min(6 s, 0.4 s * 2^(retry - 1))`). A `Retry-After` header is a lower bound;
when a server asks for more than `maxRetryAfter` (12 s) the request is not retried at all
rather than retried too early or parking the UI. `RetryExecutor` checks for cancellation between
attempts.

| Failure | Query | Mutation | Reason |
| --- | --- | --- | --- |
| `NetworkError.offline` | no | no | Fail fast so the offline banner shows immediately |
| `NetworkError.cancelled` | no | no | The caller went away |
| `NetworkError.timeout`, `.transport` | yes | no | The request may have reached Shopify |
| HTTP 429 | yes, honoring `Retry-After` | yes | Shopify rejected the request before executing it |
| GraphQL `THROTTLED` (HTTP 200) | yes | yes | Rejected before execution |
| HTTP 500, 502, 503, 504 | yes | no | The mutation may have executed |
| GraphQL `INTERNAL_SERVER_ERROR` (HTTP 200) | yes | no | Shopify's documented 200 form of a 500 |
| Other 4xx, `ACCESS_DENIED`, decoding errors | no | no | Repeating the same request cannot help |

**Why mutations are never replayed.** After a timeout, a dropped connection or a 5xx, the app
cannot know whether Shopify executed the mutation. Replaying `cartLinesAdd` would add the line a
second time, replaying `cartCreate` would create a second cart. Only failures where Shopify
states that it rejected the request before executing it (HTTP 429, `THROTTLED`) are safe to
repeat. After an ambiguous mutation failure, or a cancellation while the request was in flight,
callers re-read the affected state (for example `cart(id:)`) instead of repeating the write.

### In-flight de-duplication

`RequestDeduplicator<Key, Value>` (a Core actor) lets concurrent callers with the same key share
one in-flight task. `GraphQLClient` keys it with the complete `HTTPRequest` as sent: URL,
headers (so the credentials) and body bytes (so document, directive and variables). Two screens
asking for the same collection in the same context therefore cause one request; different
contexts, different tokens or any mutation are never shared. The entry is removed when the task
finishes, so this is de-duplication, not caching (the `URLCache` and, later, in-memory stores
cache). Cancelling one caller does not cancel the shared request for the others; when the last
waiting caller is cancelled the shared request is cancelled too.

### Error mapping to UI states

Every failure reaches the caller as a `ShopifyError`:

| `ShopifyError` | Source |
| --- | --- |
| `.network(NetworkError)` | No HTTP response (offline, timeout, cancelled, TLS, ...) |
| `.accessDenied(requiredAccess:)` | HTTP 401 or 403, or a GraphQL `ACCESS_DENIED` (with the missing scope) |
| `.throttled` | HTTP 429 or `THROTTLED` after the retry budget |
| `.http(statusCode:)` | Any other non-2xx status |
| `.graphQL([GraphQLErrorDetail])` | Any other top-level GraphQL error; partial data is never returned |
| `.userErrors([UserError])` | `userErrors` of a mutation payload (`UserErrorsPayload.throwingUserErrors()`) |
| `.notFound` | A resource that must exist does not |
| `.decoding(String)` | `"<Type>: <codingPath>"`, never payload content |

The helpers `isConnectivityProblem`, `isCancellation`, `isTransient` and `logDescription` let
view models map errors to the standard UI states without switching over every case:

| Condition | UI state |
| --- | --- |
| Loading, no content yet | `KXSkeleton` or `.kxSkeleton(isActive:)` on the placeholder layout |
| Content | The screen |
| Empty result, `nil` product or collection, `.notFound` | `KXEmptyState` with a way forward |
| `isConnectivityProblem` | The shell's offline banner plus cached content when available; reload when the network returns |
| `isCancellation` | Nothing (the view went away) |
| `isTransient` (throttled, 5xx, 408, internal errors) | Error state or `KXBanner(.error)` with "Erneut versuchen" |
| `.userErrors` | Inline message next to the affected input, using Shopify's localized `UserError.message` |
| `.accessDenied`, `.decoding`, `.graphQL`, other `.http` | Generic error state; logged with `logDescription` (codes only) |

The offline banner already works in Phase 0: `OfflineBannerModifier` (App shell) subscribes to
`NetworkMonitoring.statusUpdates()` and shows `KXBanner(.offline)` with the `.inset` placement,
which pushes the tab content down so navigation bars stay reachable. `OfflineBannerPolicy`
shows it only for a known `.offline` status, so a normal launch never flashes it.

## Tokenless mode and metafields

The Storefront API answers **without an access token** for products, collections,
localization, search, pages, blogs and cart. Until the owner provides a public token
(`KX_STOREFRONT_ACCESS_TOKEN`, see [OWNER_INPUTS.md](OWNER_INPUTS.md)), the app runs in this
tokenless mode:

- `StorefrontConfiguration.isTokenless` is `true` when the token is empty; no
  `X-Shopify-Storefront-Access-Token` header is sent.
- Tokenless requests cannot read metafields: selecting them fails the **whole** request with
  `ACCESS_DENIED` (`requiredAccess: unauthenticated_read_metafields`, recorded in
  `product_metafields_access_denied_DE_DE.json`). The `ProductDetail` fragment therefore selects
  `metafields(identifiers: $metafieldIdentifiers) @include(if: $includeMetafields)`, and
  `StorefrontCatalogRepository` passes `includeMetafields: !client.isTokenless`.
- Tokenless requests are capped at a query cost of 1000; the Phase 0 queries cost 5 to 14.

`ProductMetafields` gives typed, failure-tolerant access to the keys of PROMPT.md 5.1 and the
store's existing keys (`ProductMetafields.Identifier`): `faq` (`karinex.faq` parsed into
`[FAQEntry]`), the spec keys (`licenseType`, `architecture`, `deviceCount`, `deliveryForm`,
`activationMethod`, `languages`, `supportStatus`), the rich text sections
(`detailsContent`, `shippingContent`, `warrantyContent` as `MetafieldContent`), `mpn` (falls
back to `mm-google-shopping.mpn`), `dealEndsAt` (falls back to `custom.angebotsende`) and
`lowestPrice30Days(currency:)`. Every accessor returns `nil` for missing or malformed values and
never crashes; in tokenless mode all of them are `nil`, so product screens must treat every
metafield module as optional.

Switching to token mode is configuration only: put the token into `Config/Secrets.xcconfig` and
the CI secret. Values also need metafield definitions with Storefront read access, which the
store does not have yet ([STORE_AUDIT.md](STORE_AUDIT.md), owner actions 2 and 3).

## Markets and languages

| | App UI | Store content (Storefront `localization`) |
| --- | --- | --- |
| Languages | 11: `de` (source), `en`, `pl`, `nl`, `pt-PT`, `sv`, `da`, `es`, `fr`, `it`, `fi` (`AppLanguage`, `CFBundleLocalizations`) | 13: DA, DE, EL, EN, ES, FI, FR, IT, NL, PL, PT_PT, RO, SV. Greek and Romanian have content but no UI |
| Countries | | 28 markets (AT BE BG CH CY CZ DE DK EE ES FI FR GR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK); currencies EUR, CHF, CZK, DKK, HUF, PLN, RON, SEK. The Netherlands offer only NL content |

**The UI language follows the iOS per-app language setting.** Because `Info.plist` lists the 11
localizations in `CFBundleLocalizations`, iOS offers a language choice for KARINEX in the
Settings app, and String Catalogs, `Locale` formatting and system controls follow it
automatically. The app never overrides `AppleLanguages` itself (see the decision below).

**The Storefront content language follows the selected market.** Product titles, descriptions
and prices come in the language and currency of `MarketSelection` (country and
`LanguageCode`), sent with `@inContext`. The two can legitimately differ: a German speaker in
the Netherlands sees a German UI with Dutch product content, because the NL market offers only
NL. Prices are always the market's `MoneyV2`, formatted with the user's locale.

`MarketResolver.resolve(regionCode:preferredLanguages:localization:)` picks the initial market:

- **Country:** the device region when the store sells there, otherwise `DE`; if the store did
  not sell to the default either, its first country.
- **Language:** the first preferred language that is one of the 11 app languages **and**
  available in that country (`pt`, `pt-BR` and `pt-PT` map to `PT_PT`, `de-AT` to `DE`);
  otherwise `EN`, then `DE`, then the first app language the country offers.
- `MarketResolution.reason` (`deviceMatch`, `countryUnavailable`, `languageUnavailable`,
  `countryAndLanguageUnavailable`) and `wasAdjusted` let the one-time confirmation sheet
  explain a fallback once.

Examples covered by `MarketResolverTests`: CH with French UI gives CH/FR; AT with `de-AT` gives
AT/DE; a US region (not sold) gives DE; a Greek UI gives EN (EL is a store language but not an
app language); an English device in the Netherlands gets NL content.

**Phase 0 status.** The container uses `MarketSelection.germany` for every call. Phase 1 runs the
resolver at first launch (feeding it the UI language first, `Bundle.main.preferredLocalizations`,
then `Locale.preferredLanguages`), persists the `MarketSelection` in `preferences`, shows the
confirmation sheet and updates `storefrontContextProvider`. Settings (Phase 2) changes the market
in-app and links to the iOS language setting for the UI language.

## Design system

"KARINEX Editorial Luxe for iOS": cream panels, deep forest green, restrained champagne gold,
serif display type, native iOS chrome.

### Tokens in code, verified by tests

```
BrandPalette (raw brand hex values)
    -> ColorToken (semantic token, light and dark value)        DesignTokens, pure Swift
    -> ContrastRequirement.all (allowed text/background pairs)  tested on Linux
    -> KXColor (dynamic UIColor/Color per trait collection)     DesignSystem, SwiftUI
```

- `ColorToken` defines every semantic color (`background`, `surface`, `textPrimary`, `brand`,
  `textOnBrand`, `accent`, `accentText`, `urgency`, `keyCardBackground`, ...) with a light and a
  dark value. In dark mode `brand` becomes gold and `textOnBrand` ink, so primary buttons invert
  automatically.
- `ContrastRequirement.all` lists the only pairs components may use for text (WCAG AA 4.5:1)
  and non-text UI (3:1). `DesignTokensTests` checks every pair in both appearances and that
  gold is never a text color on light surfaces (it is decorative; readable gold text uses
  `accentText`). Changing a value that breaks contrast fails CI.
- `TypographyToken` (display, title1 to title3, headline, body, callout, subheadline, footnote,
  caption, eyebrow, price, numeral, licenseKey) defines design (serif, sans, monospaced), weight,
  base size, the Dynamic Type text style it scales with, tracking and digit style.
- `SpacingToken` (8 pt grid, 16 pt gutter, 44 pt tap target), `RadiusToken` (card 18),
  `BorderToken` and `MotionToken` (springs between 0.25 and 0.35 s) complete the set; SwiftUI
  code uses them through `KXSpacing`, `KXRadius`, `KXBorder` and `KXMotion`.

The asset catalog holds only what iOS reads by name before any code runs: `AppIcon`,
`AccentColor` (global tint of system chrome; mirrors `ColorToken.brand`: forest in light, gold
in dark) and `LaunchBackground` (the launch screen; mirrors `ColorToken.background`). Keep those
two in sync by hand when the tokens change.

### Typography: system serif (New York) for now

`.kxFont(_:)` applies a token through `KXFontModifier`, which scales size and tracking with
`@ScaledMetric` relative to the token's text style, and `KXFont.font(_:size:)`, which returns
`Font.system(size:weight:design:)`. For serif tokens the design is `.serif`, which iOS renders
in **New York**, Apple's system serif with optical sizes, all weights and full Dynamic Type
support. Cormorant Garamond (the web headline face) is not bundled yet (see the decision below).

To switch the headlines to Cormorant Garamond later:

1. Add the OFL font files (the weights used by serif tokens: medium and semibold) and the
   license text under `Packages/DesignSystem/Sources/DesignSystem/Resources/Fonts/`; the
   target already processes `Resources`.
2. Register them once at launch from the package bundle with
   `CTFontManagerRegisterFontsForURL` (package resources are not covered by the app's
   `UIAppFonts`), called from `KarinexApp.init`.
3. In `KXFont.font(_:size:)`, return `Font.custom(<PostScript name for the weight>, fixedSize:
   size)` when `style.design == .serif`. Use `fixedSize:` because `KXFontModifier` has already
   scaled the size; `Font.custom(_:size:)` would scale it a second time.
4. Review `baseSize` and `tracking` of the serif tokens in `TypographyToken` (Cormorant has a
   small x-height and thin strokes), check the `numeral` digits of `KXCountdown`, then re-record
   the snapshots and review them in light, dark and the accessibility sizes.

Nothing else changes, because every component uses `.kxFont(_:)`.

### Components

All in `Packages/DesignSystem/Sources/DesignSystem/Components/`, each with `#Preview`s in
light, dark and an accessibility text size, and snapshot tests:

| Component | Purpose |
| --- | --- |
| `KXButton`, `KXButtonStyle` (`.kx(...)`) | Primary (brand fill), secondary (gold hairline outline), tertiary; regular and compact; loading, disabled, full width |
| `KXCard`, `KXCardStyle` | Cream panel (standard or elevated), radius 18, hairline border, optional gold inset ring |
| `KXBadge` | Gold, urgency, neutral and success capsules |
| `KXPriceTag` | Price, struck-through compare-at price, savings badge, optional tax note, combined accessibility label |
| `KXSectionHeader` | Serif title, eyebrow, short gold rule, optional trailing action |
| `KXSpecRow` | Label and value with a dot leader; stacks at large text sizes |
| `KXStepTimeline` | Vertical or horizontal steps with gold numerals (done, current, upcoming) |
| `KXAccordion`, `KXAccordionItem` | Expandable rows with a gold plus that turns into a cross |
| `KXCountdown`, `KXCountdownComponents` | Flip-digit countdown to a date, days from 24 h, `onExpire`, no flip with Reduce Motion |
| `KXTrustStrip`, `KXTrustItem` | Grid or carousel of trust facts, optional footnote marker and tap action |
| `KXProductCard`, `KXProductCardModel`, `KXProductImage` | Product tile with image, badge, serif title and compact price tag |
| `KXKeyCard`, `KXLicenseKeyFormatting` | Certificate-style license key card with masking, grouping and copy |
| `KXClipboard` | `copySensitive(_:expiresAfter:)`: local-only pasteboard item that expires after 120 s |
| `KXSkeleton`, `.kxSkeleton(isActive:)` | Placeholder with shimmer (none with Reduce Motion) |
| `KXEmptyState` | SF Symbol in a gold ring, serif title, message, optional action |
| `KXBanner`, `.kxBanner(isPresented:placement:banner:)` | Offline, error, info and success banners with VoiceOver announcements; `overlay` or `inset` placement |
| `KXWordmark` | The interim typographic "KARINEX" logo |
| `KXDivider` | Hairline divider, standard or gold accent, horizontal or vertical |

Foundation helpers in `Foundation/`: `KXColor`, `KXTypography` (`.kxFont(_:)`, `KXFont`),
`KXLayout` (`KXSpacing`, `KXRadius`, `KXBorder`, `.kxScreenBackground()`, `.kxGutter()`),
`KXMotion` (`.standard`, `.snappy`, `.gentle`, `.fade`, all Reduce Motion aware) and
`KXHaptics`.

Components take already-localized strings from the caller. Strings that belong to a component
itself (for example "Kopieren" on the key card or the default offline message) live in the
DesignSystem String Catalog under `kx.<component>.*`.

### Gallery

`KXDesignSystemGallery` (`Gallery/`, compiled only in DEBUG) is a developer catalog: color
tokens with light and dark values and contrast pairs, the type scale, spacing, radii, borders,
motion, and one page per component with its variants and states (for example
`KXGalleryButtonPage`, `KXGalleryKeyCardPage`), organized by `KXGalleryTopic` over the files
`KXGalleryFoundationPages.swift`, `KXGalleryCommercePages.swift`, `KXGalleryContentPages.swift`,
`KXGalleryFeedbackPages.swift` and `KXGallerySupport.swift`. Its preview settings override
appearance and Dynamic Type size for the pages it opens. `AccountView` links to it in DEBUG
builds, so it is one tap away on the Konto tab.

### Snapshot tests

`Packages/DesignSystem/Tests/DesignSystemTests` renders every component with
[swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) 1.19.6 under
Swift Testing. `SnapshotSupport.swift` defines the fixed matrix and canvas:

| Variant name | Appearance | Text size | Sample language |
| --- | --- | --- | --- |
| `light-large-de` | light | Large (default) | German |
| `dark-large-de` | dark | Large | German |
| `light-xxxl-fi` | light | xxxLarge | Finnish (long compounds) |
| `light-axxl-fi` | light | accessibilityExtraLarge (AX3) | Finnish |

The canvas is 390 pt wide at display scale 2 on the page background, compared with precision
0.995 and perceptual precision 0.98. The parent suite `DesignSystemSnapshotTests` is
`.serialized` because rendering spins the main run loop. Nothing depends on time or network: the
countdown uses a fixed reference date, product images use the local `SnapshotProductArtwork`,
and the shimmer is switched off. References live in `__Snapshots__/<TestFile>/<test>.<variant>.png`
and are recorded by CI (see [CI/CD](#cicd)).

## Images

Product images come from the Shopify CDN, which was measured on 2026-09-26:

- The `width` query parameter is honored: a 147 KB original becomes 27 KB at card size.
  `ShopifyImage.url(width:)` adds or replaces `width` and keeps every other query item (such as
  the `v` cache buster). Pass pixels, not points: rendered width times the display scale.
- `format=webp` is **ignored**. The CDN negotiates WebP from the request's `Accept` header, which
  brings the same image to about 15 KB. `ShopifyImage.acceptHeader` is
  `image/webp,image/*;q=0.8`; the image pipeline must send it.

In Phase 0 `KXProductImage` loads with `AsyncImage` (skeleton while loading, restart after a
cancelled download in lazy stacks, neutral fallback symbol), which cannot set request headers.
Phase 1 moves image loading to Nuke 13.2.0 with an `ImagePipeline` configured once in the App
target to send `ShopifyImage.acceptHeader`, plus prefetching of the next row. Budget: less than
40 KB per product card ([PERFORMANCE.md](PERFORMANCE.md)).

## Security and privacy

Details and the threat model are in [SECURITY.md](SECURITY.md). In short:

- Only the **public** Storefront token can ship in the binary, injected from the git-ignored
  `Config/Secrets.xcconfig`; without it the app is tokenless. No Admin API, BFF or APNs secrets
  exist in the app, and it never calls the Admin API.
- Secrets go into the Keychain through `SecureStore` (`KeychainStore`: generic passwords,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable, `removeAll()` limited
  to the app's service). Preferences and the consent go into `UserDefaults`.
- Every log line goes through `KXLogger`, which passes it through `Redactor` (credential headers,
  bearer tokens, OAuth fields and query items, cart and customer GIDs, checkout tokens, Shopify
  tokens, JWTs, e-mail addresses, product keys, long opaque secrets). The SwiftLint rule
  `no_print_logging` forbids `print`, `debugPrint`, `dump` and `NSLog` in app and package code.
  `GraphQLClient` never logs variables, headers or bodies; `ShopifyError.logDescription` contains
  codes only.
- `PrivacyConsent` is all off (`.undecided`) until the user decides; analytics, crash reporting
  and push registration must not start unless the matching flag is `true`. The consent reaches
  checkout through `@inContext(visitorConsent:)`.
- `App/Resources/PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, no collected
  data and the `UserDefaults` reason `CA92.1`. App Transport Security has no exceptions.
- `KXClipboard.copySensitive` puts license keys on the pasteboard as local-only items that
  expire after 120 seconds.

## Localization

The mechanism is summarized here; tone rules, the glossary and QA are in
[LOCALIZATION.md](LOCALIZATION.md).

- One String Catalog per module: `App/Resources/Localizable.xcstrings` (`tab.*`),
  `Packages/DesignSystem/Sources/DesignSystem/Resources/Localizable.xcstrings` (`kx.*`) and
  `Packages/Features/Sources/<Feature>/Resources/Localizable.xcstrings` (`home.*`, `catalog.*`,
  `search.*`, `cart.*`, `account.*`). German (`de`) is the source language everywhere
  (`DEVELOPMENT_LANGUAGE = de`, `defaultLocalization: "de"` in the SwiftUI packages).
- Package code resolves strings in its own bundle: `Text("home.hero.title", bundle: .module)`
  or `String(localized: "...", bundle: .module)`. The App target uses `Text("tab.home")`. Each
  feature has a small `<Feature>Resources` enum (for example `HomeResources`) so tests can
  resolve a string in a specific language through a `.lproj` folder.
- Keys are lowercase dot paths and every key has a translator comment. Plurals use catalog
  plural variations, never code.
- `scripts/check_strings.py` (`make check`, CI) fails on missing languages, empty values,
  incomplete plural categories, format specifier mismatches, keys used in code but missing from
  the catalog, unused keys, and package code that forgets `bundle: .module`.
  `scripts/check_copy_rules.py` fails on em or en dashes in catalog values and on forbidden
  words and claims in Swift code, catalogs and `Info.plist` files.
- Prices are never in catalogs: they are `MoneyV2` values formatted with the user's `Locale`.

## Testing strategy

| Suite | Framework | Runs on | What it covers |
| --- | --- | --- | --- |
| `CoreTests` | Swift Testing | Linux and iOS simulator | Configuration parsing, `AppLanguage` normalization, one test per `Redactor` pattern plus false-positive checks, retry math and executor, de-duplication, `Locked`, stores, consent, flags, launch environment, `NetworkError` mapping, `Retry-After` parsing |
| `ShopifyKitTests` | Swift Testing | Linux and iOS simulator | Every fixture decoded through the real `GraphQLClient` with `StubHTTPClient`; request bodies and headers (operation name, `@inContext`, token header only with a token); retry and de-duplication rules; error mapping; `ContextInjector`; `MarketResolver`; `MoneyV2` parsing and formatting; `ShopifyImage.url(width:)`; `ProductMetafields` |
| `DesignTokensTests` | Swift Testing | Linux and iOS simulator | Palette values, dark mapping, WCAG contrast of every allowed pair in both appearances, spacing, radius, motion and type rules |
| `DesignSystemTests` | Swift Testing + SnapshotTesting | iOS simulator | Snapshots of every component in the four-variant matrix, plus logic tests (`KXCountdownComponents`, `KXLicenseKeyFormatting`, `KXClipboard` options, component models) |
| `FeaturesTests` | Swift Testing | iOS simulator | Content types of the feature modules in all 11 languages, the legal and support wording, and that no app-authored string contains an em or en dash |
| `KARINEXTests` (`App/Tests`) | Swift Testing | iOS simulator (hosted) | `AppContainer` composition, configuration fallback, reset launches, flags, buyer context, `AppTab` order, symbols, identifiers and titles, the offline banner policy |
| `KARINEXUITests` (`App/UITests`) | XCTest (XCUITest) | iOS simulator | `ShellUITests`: five tabs, each tab's root screen, hero call to action opens Shop, money-back conditions sheet, offline banner keeps the navigation bar reachable, forced dark appearance |
| `FixtureRecordingTests` | Swift Testing | Linux and macOS | Recorder CLI parsing, plan, anonymizer and output with a canned transport |

**Fixtures from the live store.** `Tools/FixtureRecorder` runs the real `StorefrontClient`
against the production store (read queries plus one `cartCreate` with a non-existent variant
that creates nothing) and stores the raw bodies, pretty-printed with sorted keys, plus
`manifest.json`. Hand-written error envelopes are named `synthetic_*.json`. Re-record with
`make fixtures` after an API version change or store content change and update the asserted
values; see `Packages/ShopifyKit/Tests/ShopifyKitTests/Fixtures/README.md`.

**Snapshot recording workflow.** References are recorded on the CI runner image so they are
pixel compatible with the `ios` job:

1. Change or add a component and its snapshot test.
2. Run the **Record snapshots** workflow (`record-snapshots.yml`) from the Actions tab on your
   branch. It records with `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all`, uploads the PNGs as an
   artifact, commits them to the branch and starts CI for the new commit.
3. Review the committed images in the pull request.

`make snapshots` records locally for experiments; local references can differ from the CI
renderer, so commit the ones from the workflow. The library's own `SNAPSHOT_TESTING_RECORD`
variable drives the mode; tests never hardcode `record: true`, and CI runs with `never`, so a
missing reference fails instead of being recorded silently.

**UI tests** launch with `-kx.uitesting -kx.reset -AppleLanguages (de) -AppleLocale de_DE`, find
elements by accessibility identifiers (`tab.<name>`, `screen.<name>`, `home.hero.cta`,
`shell.offlineBanner`) with the German title as a fallback for tab buttons, and never depend on
the host network.

**Linux package tests.** `make test-packages` (and the `packages-linux` CI job) builds Core,
ShopifyKit and DesignTokens with `-warnings-as-errors` and runs `swift test`; on macOS the
DesignTokens tests run through `xcodebuild` because the package declares only iOS.

## CI/CD

| Workflow | Trigger | Jobs and steps |
| --- | --- | --- |
| `ci.yml` | every push, pull requests, manual | **packages-linux** (`swift:6.4.0-noble` container): build with `-warnings-as-errors` and test Core, ShopifyKit, DesignTokens and the FixtureRecorder. **checks** (Ubuntu): `check_strings.py`, `check_copy_rules.py`, SwiftFormat 0.63.0 `--lint`, SwiftLint 0.65.1 `--strict` in the official Docker image. **ios** (`macos-26`, latest stable Xcode): project sync check, secrets file, package resolution (prints `Package.resolved`), `build-for-testing`, `test-without-building` of the whole `KARINEX` scheme in German on the newest iPhone simulator with `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never`, zero-warning gate, coverage summary, result bundles uploaded on failure |
| `record-snapshots.yml` | manual, on a branch | Records the DesignSystem references, uploads them, commits them as `github-actions[bot]` and dispatches `ci.yml` for the new commit |
| `testflight.yml` | manual | `bundle exec fastlane beta` on `macos-26` |
| `dependabot.yml` | weekly | Updates the GitHub Actions; Swift packages and fastlane are updated deliberately |

- **Zero-warning gate.** Packages build with `-Xswiftc -warnings-as-errors`, and
  `scripts/check-warnings.sh` scans the Linux test logs and the Xcode build log for `warning:`
  lines in `App/`, `Packages/` or `Tools/` (third-party checkouts are ignored). SwiftLint runs
  with `--strict`.
- **Project sync check.** The `ios` job runs `xcodegen generate --spec project.yml` with the
  pinned XcodeGen 2.46.0 and fails if `KARINEX.xcodeproj` changes; the fastlane `beta` lane does
  the same before archiving.
- **Secrets.** `scripts/write-secrets-xcconfig.sh` writes `Config/Secrets.xcconfig` from the
  repository secrets `KX_STOREFRONT_ACCESS_TOKEN`, `KX_CUSTOMER_ACCOUNT_CLIENT_ID` and
  `KX_APPLE_TEAM_ID` (all optional for CI; empty values keep the tokenless fallback), validating
  each value so it cannot break the xcconfig syntax.
- **TestFlight lane.** `fastlane beta` requires `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`
  (base64 of the .p8) and `KX_APPLE_TEAM_ID`; it validates the key, checks the project sync,
  writes the secrets file, sets the build number to the latest TestFlight build plus one, builds
  a Release archive with automatic signing through the App Store Connect API key and uploads it
  without waiting for processing. `fastlane tests` runs the full suite locally.

## Decisions

Each decision records the context, the choice and its consequences.

### ADR 1: XcodeGen with a committed project

A hand-maintained `project.pbxproj` produces merge conflicts and silent drift when several people
(or agents) add files. `project.yml` is the source of truth and `KARINEX.xcodeproj` is generated
from it with a pinned XcodeGen 2.46.0 **and committed**, so a fresh clone opens in Xcode without
any tool, and Xcode Cloud or other CI can build it as is. The price is a second file to commit
after every change to targets or settings; CI and the fastlane `beta` lane regenerate the project
and fail when the committed copy is stale. Tuist was not chosen because it adds a heavier
toolchain for no benefit at this size.

### ADR 2: One package per layer, and one Features package with one target per feature

Layers with different platform needs must stay separable: Core, ShopifyKit and DesignTokens are
Foundation-only and tested on Linux, while DesignSystem and the features need SwiftUI. Each layer
is therefore its own local package with `public` APIs as the boundary. The features share one
package (`Packages/Features`) with one library target per feature instead of one package per
feature: a single manifest generates all feature targets with identical dependencies, which makes
"features never depend on each other" true by construction; each target still has its own
resource bundle and String Catalog and compiles in parallel; and the Xcode package list stays
short. Adding a feature means adding its name to `featureNames`, creating
`Sources/<Name>/Resources/Localizable.xcstrings`, and linking the product in `project.yml`.

### ADR 3: Design tokens in code, not in an asset catalog

PROMPT.md suggests asset catalog colors. The tokens live in Swift instead (`DesignTokens`),
because only code can be unit tested on Linux: `ContrastRequirement.all` checks every permitted
text and UI pairing against WCAG AA in light and dark on every CI run, so a palette change that
breaks readability cannot merge. Code is also the single source for SwiftUI (`KXColor`), UIKit
(`KXColor.uiColor(_:)`, needed for the Checkout Kit configuration) and the snapshot tests, and
token changes are reviewable as text diffs. The asset catalog keeps only `AppIcon`, `AccentColor`
and `LaunchBackground`, which iOS reads by name before code runs; they mirror `brand` and
`background` and must be updated by hand with them.

### ADR 4: System serif (New York) instead of bundling Cormorant Garamond for now

The brand uses Cormorant Garamond on the web, but the logo and brand redesign is still pending.
The system serif gives optical sizes, every weight, complete glyph coverage for all 11 languages
and first-class Dynamic Type at no binary, licensing or registration cost, and stays legible at
small and accessibility sizes where a thin-stroked display face struggles. All serif text goes
through `TypographyToken.design == .serif` and `KXFont.font(_:size:)`, so switching later is a
local change (steps in [Typography](#typography-system-serif-new-york-for-now)) followed by
re-recorded snapshots.

### ADR 5: `ProductCollection` instead of `Collection`

The Storefront type is called `Collection`, but a public `ShopifyKit.Collection` would shadow the
standard library's `Collection` protocol in every module that imports ShopifyKit and produce
confusing diagnostics. The model is named `ProductCollection`; its descriptive part is
`CollectionSummary`, a page of it `CollectionPage`, a product's reference to it
`CollectionReference`, and the sort enum keeps Shopify's name `ProductCollectionSortKeys`.

### ADR 6: `Locked` instead of `Mutex` (iOS 17)

`Synchronization.Mutex` needs iOS 18, and the app supports iOS 17. `Locked<Value: Sendable>`
(Core) wraps an `NSLock` with the same programming model (`withLock(_:)`, `value`,
`replace(with:)`) and is `@unchecked Sendable` with a documented justification. It guards the
mutable state of `MutableStorefrontContextProvider`, the waiter bookkeeping of
`RequestDeduplicator` and attempt counters. When the deployment target reaches iOS 18, replace it
with `Mutex` (mind that `Mutex` is non-copyable, so shared instances stay inside a class).

### ADR 7: Tokenless fallback

The Storefront API serves products, collections, localization, search, content and cart without
a token, and the owner has not created the Headless channel token yet. Rather than blocking on
it, the app treats the token as optional configuration: `StorefrontConfiguration.isTokenless`
drops the header and repositories stop requesting metafields. CI, previews, the fixture recorder
and TestFlight builds therefore need no secret, and an invalid configuration falls back to the
tokenless live store instead of crashing. The cost is that metafield-driven modules (specs, FAQ,
deal end dates) stay empty until the token and the metafield definitions exist, and requests are
limited to a query cost of 1000.

### ADR 8: Checkout Kit 3.9.0 for Phase 1

Checkout must run through Shopify's `ShopifyCheckoutSheetKit` (PROMPT.md 3.2). On 2026-09-26 the
latest stable release was 3.9.0 (2026-09-18); `4.0.0-rc.2` is a pre-release and is not used. The
dependency is added in Phase 1 (not in Phase 0, so the foundation stays free of third-party
runtime code) as `from: "3.9.0"` for the checkout feature only, with the resolved version pinned
by the committed `Package.resolved`. Upgrades are deliberate: Dependabot watches only GitHub
Actions. The APIs relied on (`preload(checkout:)`, `present(checkout:from:delegate:)`,
`CheckoutDelegate`, `Configuration`) are listed in [API_VERSIONS.md](API_VERSIONS.md).

### ADR 9: UI language through the iOS per-app language setting

PROMPT.md asks for a language choice in Settings. Overriding `AppleLanguages` inside the app
needs a restart, can leave system formatting, system controls and String Catalog lookups
inconsistent, and duplicates a feature iOS already provides: with `CFBundleLocalizations` set,
Settings > KARINEX > Language switches the UI language per app, and SwiftUI, `Locale` and
String Catalogs follow it. The app therefore uses the system setting for the UI language (the
Settings screen links to it) and keeps its own choice only for the market, which also selects the
Storefront content language. The two can differ on purpose (see
[Markets and languages](#markets-and-languages)).

### ADR 10: An own GraphQL client instead of Apollo

The app uses a handful of hand-written operations against two Shopify APIs. A small typed client
(`GraphQLOperation`, `GraphQLClient`) keeps the toolchain simple (no code generation step, no
schema download in CI), gives full control over `@inContext` injection, retry semantics for
mutations, de-duplication and redacted logging, and runs on Linux. Every operation document is
validated against the live API when fixtures are recorded, and decoding tests fail loudly on
schema changes. Revisit if the operation count grows to where generated types pay off.

## Roadmap

Delivery phases from PROMPT.md 14. Feature names follow `Packages/Features/Package.swift`.

### Phase 1: Commerce core

- **New feature targets:** `ProductFeature` (product detail: gallery, variant selector, price
  with tax wording per market, key facts from metafields, "So läuft es ab", description rendered
  natively from `descriptionHtml` with `tel:` links dropped, comparison, FAQ, refund conditions,
  sticky add-to-cart bar) and `CheckoutFeature` (Checkout Kit presentation, preload, delegate,
  success screen).
- **Existing features filled with live data:** Home (deal carousel, category rows, bestsellers,
  guides), Catalog (collections, sort, filters, cursor pagination, pull to refresh), Search
  (predictive search and results), Cart (lines, quantities, discount codes, notices, checkout).
  View models per screen as described in [Data flow](#data-flow).
- **ShopifyKit:** cart query and mutations (`cartLinesAdd`, `cartLinesUpdate`, `cartLinesRemove`,
  `cartDiscountCodesUpdate`, `cartBuyerIdentityUpdate`, `cartAttributesUpdate`), predictive search
  and product search, blog articles; `StorefrontCartRepository` wired into `AppContainer`, the cart
  ID persisted in `preferences`.
- **Markets:** first-launch `MarketResolver` run, confirmation sheet, persisted `MarketSelection`.
- **App:** deep links and Universal Links (`/products/`, `/collections/`, `/blogs/`), custom
  scheme `karinex://`.
- **Dependencies to add:** Checkout Kit **3.9.0** (`https://github.com/Shopify/checkout-sheet-kit-swift`,
  product `ShopifyCheckoutSheetKit`) and Nuke **13.2.0** (`https://github.com/kean/Nuke`, `Nuke`
  and `NukeUI`) for the image pipeline with `ShopifyImage.acceptHeader` and prefetching; commit
  `Package.resolved`.
- **Quality:** launch and scrolling measurements ([PERFORMANCE.md](PERFORMANCE.md)), all 11
  languages kept complete, TestFlight build 1.

### Phase 2: Account and licenses

- **New feature targets:** `LicensesFeature` (license vault with `KXKeyCard`, Keychain cache,
  privacy overlay, optional Face ID), `SupportFeature` (WhatsApp, e-mail, live chat, opening hours
  computed in Europe/Berlin), `LegalFeature` (Impressum, AGB, Datenschutz, Widerrufsbelehrung,
  Versand, rendered natively) and `SettingsFeature` (market, link to the iOS language setting,
  appearance, notifications, privacy consents, Face ID, about).
- **AccountFeature:** Customer Account API login (OAuth 2.0 with PKCE through
  `ASWebAuthenticationSession`), orders with timeline, addresses, invoices, account deletion,
  logout.
- **ShopifyKit:** a Customer Account API client on `GraphQLClient` with a bearer token
  `authorization` supplier, endpoint discovery from `customerAccountDiscoveryURL`.
- **Backend:** a BFF client and a mock server, `BFF_CONTRACT.md` and `openapi.yaml`; feature
  flags `licenseVault` and `remoteConfig`.
- **Docs and quality:** `PRIVACY_NUTRITION_LABEL.md`, all 11 languages with native review,
  TestFlight build 2.

### Phase 3: Delight and launch

- Push notifications through the BFF (consent-gated), the "Blitzangebot" widget and the "Lizenz
  wird zugestellt" Live Activity (new extension targets in `project.yml`; flags
  `pushNotifications`, `homeWidget`, `liveActivity`), wishlist and recently viewed with SwiftData
  (flag `wishlist`).
- iPad adaptive polish, accessibility audit, performance pass against every budget on an iPhone
  13, App Store metadata in all languages, `APP_STORE_REVIEW_NOTES.md`, screenshot plan and
  submission.
