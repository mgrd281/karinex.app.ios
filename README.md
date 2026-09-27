# KARINEX for iOS

The official native iOS app of [KARINEX](https://www.karinex.de), a Hamburg-based Shopify store
for Microsoft software licenses (Windows, Office, Windows Server, Visual Studio, Visio,
Project) that serves consumers in 28 European countries. The app is a headless Shopify client
built with SwiftUI: catalog, prices, cart and checkout come live from the Shopify Storefront API
and Checkout Kit, accounts from the Customer Account API, and license keys and invoices from the
KARINEX backend. It is designed as a premium, fully localized first-party product in 11
languages, in light and dark mode.

The product and engineering specification is [PROMPT.md](PROMPT.md). How the code is organized
and why is described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Status

**Phase 0 (foundation) is complete**, released as version `0.1.0`
([CHANGELOG.md](CHANGELOG.md)). The app launches to a tokenized five-tab shell (Start, Shop,
Suche, Warenkorb, Konto) in light and dark mode, on top of:

- `Core`: configuration, redacting logger, HTTP client, retry, request de-duplication,
  reachability, Keychain and preferences storage, privacy consent, feature flags,
- `ShopifyKit`: a typed Storefront GraphQL client with `@inContext`, models, operations,
  repositories, market resolution and fixtures recorded from the live store,
- `DesignSystem`: WCAG-tested design tokens, the "Editorial Luxe" component set (`KXButton`,
  `KXCard`, `KXPriceTag`, `KXProductCard`, `KXKeyCard`, `KXCountdown`, ...), a DEBUG gallery and
  snapshot tests,
- CI on GitHub Actions and a fastlane TestFlight lane.

Next is Phase 1 (commerce core: product detail, catalog, search, cart, Checkout Kit, deep
links). See the [roadmap](docs/ARCHITECTURE.md#roadmap).

## Requirements

| Tool | Version | Needed for |
| --- | --- | --- |
| macOS with **Xcode 26 or newer** | iOS 26 SDK or newer | Building and running the app, all tests |
| iOS deployment target | **iOS 17.0** | iPhone first, iPad compatible |
| Swift | 6 language mode, strict concurrency | Everything |
| XcodeGen 2.46.0, SwiftLint 0.65.1, SwiftFormat 0.63.0, xcbeautify | pinned in the `Makefile` and CI | `make bootstrap` (Homebrew) or `make tools` (checksum-verified binaries) |
| Python 3 | any current | `make check` |
| Ruby 3.4 and Bundler | | fastlane (`bundle install`), only for release lanes |
| Swift 6.4 toolchain on Linux | optional | `make test-packages` without a Mac |

## Quick start

```sh
git clone https://github.com/mgrd281/karinex.app.ios.git
cd karinex.app.ios

make bootstrap        # installs xcodegen, swiftlint, swiftformat, xcbeautify (Homebrew)
                      # and creates Config/Secrets.xcconfig from the example
$EDITOR Config/Secrets.xcconfig   # optional, see "Configuration and secrets"
make project          # regenerates KARINEX.xcodeproj from project.yml
open KARINEX.xcodeproj
```

Select the `KARINEX` scheme and an iPhone simulator, then run. No secret is required for the
simulator: without a Storefront token the app uses Shopify's tokenless access to the live store.
`KARINEX.xcodeproj` is committed, so on a clean checkout `make project` produces no diff; it is
required after every change to `project.yml`.

## Everyday commands

Run `make help` for the list. Most targets need macOS with Xcode; `test-packages`, `lint`,
`format`, `check` and `fixtures` also work on Linux.

| Command | What it does |
| --- | --- |
| `make bootstrap` | Installs the developer tools with Homebrew and creates `Config/Secrets.xcconfig` |
| `make tools` | Installs the pinned SwiftFormat, SwiftLint (and XcodeGen on macOS) into `build/tools` |
| `make project` | Regenerates `KARINEX.xcodeproj` from `project.yml` (commit both) |
| `make build` | Builds the app for the iOS Simulator and fails on compiler warnings |
| `make test` | Runs every test (unit, package, snapshot, UI) on an automatically chosen iPhone simulator, in German, with coverage |
| `make test-packages` | Builds with warnings as errors and tests Core, ShopifyKit and DesignTokens with `swift test` |
| `make lint` | SwiftFormat `--lint` and SwiftLint `--strict`, exactly as CI |
| `make format` | Applies SwiftLint autocorrections and SwiftFormat |
| `make check` | Validates the String Catalogs (11 languages) and the copy rules |
| `make fixtures` | Re-records the Storefront fixtures from the live store (tokenless unless `KX_STOREFRONT_TOKEN` is set) |
| `make snapshots` | Records DesignSystem snapshot references locally (commit the ones from the CI workflow) |
| `make clean` | Removes derived data, results and SwiftPM build directories |

Pick a simulator with `make test SIMULATOR_ID=<udid>` or `KX_SIMULATOR_NAME="iPhone 16" make test`.
Build and test logs and result bundles land in `build/results`.

## Repository layout

| Path | Contents |
| --- | --- |
| `App/` | App target `KARINEX`: `Sources/Composition` (`AppContainer`, `AppServices`, `ConfigurationResolution`), `Sources/Shell` (`RootView`, `AppTab`, offline banner), `Resources` (asset catalog, String Catalog, privacy manifest), `Tests`, `UITests`, `Info.plist` |
| `Packages/Core` | Foundation-only infrastructure, tested on Linux |
| `Packages/ShopifyKit` | Storefront GraphQL client, models, operations, repositories, `MarketResolver`, recorded fixtures |
| `Packages/DesignSystem` | `DesignTokens` (pure Swift, WCAG tests) and `DesignSystem` (SwiftUI components, gallery, snapshot tests) |
| `Packages/Features` | One target per feature: `HomeFeature`, `CatalogFeature`, `SearchFeature`, `CartFeature`, `AccountFeature` |
| `Tools/FixtureRecorder` | Command-line tool that records the ShopifyKit fixtures from the live store |
| `Config/` | `.xcconfig` build settings; `Secrets.xcconfig` is git-ignored |
| `project.yml` | XcodeGen specification; source of truth for `KARINEX.xcodeproj` |
| `scripts/` | CI and developer scripts (string and copy checks, warning gate, simulator selection, secrets file, tool installer) |
| `fastlane/`, `Gemfile` | Release automation (`tests` and `beta` lanes) |
| `.github/` | GitHub Actions workflows and Dependabot |
| `docs/` | Documentation (see below) |

## Configuration and secrets

Build settings flow from the `.xcconfig` files into `Info.plist` keys (`KXShopDomain`,
`KXStorefrontAPIVersion`, `KXStorefrontAccessToken`, ...) and are read at launch by
`AppConfiguration`. An invalid configuration never crashes the app: it falls back to the
built-in live store configuration in tokenless mode and logs an error.

**Not secret, committed** (`Config/Base.xcconfig`):

| Setting | Value |
| --- | --- |
| `KX_BUNDLE_ID` | `de.karinex.app` |
| `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` | `0.1.0`, `1` (TestFlight builds get the next build number automatically) |
| `KX_SHOP_DOMAIN` | `45dv93-bk.myshopify.com` |
| `KX_STORE_WEB_DOMAIN` | `www.karinex.de` |
| `KX_STOREFRONT_API_VERSION`, `KX_CUSTOMER_ACCOUNT_API_VERSION` | `2026-07` (verified, see [docs/API_VERSIONS.md](docs/API_VERSIONS.md)) |

**Secrets, git-ignored** (`Config/Secrets.xcconfig`, created from `Config/Secrets.example.xcconfig`
by `make bootstrap`; all may stay empty for simulator builds):

| Setting | Purpose | Effect when empty |
| --- | --- | --- |
| `KX_STOREFRONT_ACCESS_TOKEN` | Public Storefront token of the Headless channel | Tokenless mode: catalog, search and cart work; metafields (specs, FAQ) are unavailable |
| `KX_CUSTOMER_ACCOUNT_CLIENT_ID` | Customer Account API public client (Phase 2) | No login |
| `KX_APPLE_TEAM_ID` | Signing team | Simulator only; required for device builds and TestFlight |

Never commit real values. `.gitignore` also excludes `.p8`, `.p12`, provisioning profiles and
`.env` files.

**Launch arguments** for development and UI tests (Edit Scheme > Run > Arguments):
`-kx.uitesting`, `-kx.offline` (with `-kx.uitesting`), `-kx.reset`, `-kx.appearance light|dark`
and `-kx.flag.<name> YES|NO`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#launch-switches).

## CI

GitHub Actions, defined in `.github/workflows`:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `ci.yml` | Every push and pull request | **packages-linux**: Core, ShopifyKit, DesignTokens and FixtureRecorder built with warnings as errors and tested on Linux (Swift 6.4). **checks**: String Catalogs, copy rules, SwiftFormat, SwiftLint `--strict`. **ios**: checks that `KARINEX.xcodeproj` matches `project.yml`, then builds and runs every test target on the newest iPhone simulator (macOS 26, latest stable Xcode), with a zero-warning gate and a coverage summary |
| `record-snapshots.yml` | Manual, on a branch | Records the DesignSystem snapshot references on the CI simulator, commits them and re-runs CI |
| `testflight.yml` | Manual | `bundle exec fastlane beta`: signed Release build uploaded to TestFlight with the next build number |

Repository secrets: `KX_STOREFRONT_ACCESS_TOKEN`, `KX_CUSTOMER_ACCOUNT_CLIENT_ID` and
`KX_APPLE_TEAM_ID` (optional for CI), plus `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_CONTENT`
(base64 of the App Store Connect `.p8` key) for TestFlight. Details:
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#cicd).

## Documentation

| Document | Contents |
| --- | --- |
| [PROMPT.md](PROMPT.md) | Product and engineering specification (business facts, hard rules, phases) |
| [CLAUDE.md](CLAUDE.md) | Short working rules for contributors and coding agents |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, dependency rules, data flow, networking, design system, testing, CI/CD, decisions, roadmap |
| [docs/API_VERSIONS.md](docs/API_VERSIONS.md) | Verified and pinned Shopify API, Checkout Kit and tool versions, upgrade procedure |
| [docs/STORE_AUDIT.md](docs/STORE_AUDIT.md) | What the live store contains (markets, handles, metafields) and the owner actions it needs |
| [docs/OWNER_INPUTS.md](docs/OWNER_INPUTS.md) | Inputs the owner must provide, with status |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model, controls and developer checklist |
| [docs/LOCALIZATION.md](docs/LOCALIZATION.md) | Languages, tone rules per language, glossary, QA |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Performance budgets and how they are measured |
| [Fixtures README](Packages/ShopifyKit/Tests/ShopifyKitTests/Fixtures/README.md) | Recorded Storefront fixtures and how to re-record them |
| [Tools/FixtureRecorder/README.md](Tools/FixtureRecorder/README.md) | The fixture recorder tool |

## Owner inputs still open

Several inputs from the store owner are still missing. None blocks Phase 0; the most important
ones for Phase 1 are the **public Storefront token** and the **metafield definitions with
Storefront access** (without them product specs and FAQs stay empty), the **Apple team ID** and
the **App Store Connect API key** (for device builds and TestFlight), and the
**`apple-app-site-association`** file on `www.karinex.de` for Universal Links. Phase 2 needs the
Customer Account client ID and redirect URI, the WhatsApp number, the live chat URL, the BFF base
URL and the Impressum page handle.

The complete, current list with status is in [docs/OWNER_INPUTS.md](docs/OWNER_INPUTS.md); the
store-side actions (metafield definitions, collections, product text fixes) are in
[docs/STORE_AUDIT.md](docs/STORE_AUDIT.md#required-owner-actions-blocking-phase-1-product-details).
