# Changelog

All notable changes to the KARINEX iOS app are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The version is
`MARKETING_VERSION` in `Config/Base.xcconfig`; TestFlight build numbers are assigned by the
fastlane `beta` lane. Update this file and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) with every
change.

## [Unreleased]

No changes yet. Phase 1 (commerce core) lands here.

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
- **Snapshot references are recorded by the `record-snapshots` workflow.** The repository ships
  the snapshot tests without reference images (`__Snapshots__` holds only `.gitkeep`). CI compares
  with recording disabled, so the `ios` job fails on missing references until the Record snapshots
  workflow has run on the branch; run it again after every visual change and review the images.
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

