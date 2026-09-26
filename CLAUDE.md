# CLAUDE.md

Guidance for AI coding agents (and humans) working in this repository.

## Source of truth

- **[PROMPT.md](PROMPT.md)** is the product and engineering specification of the KARINEX iOS app.
  Read sections 2 (business facts), 3 (hard rules) and the section for the area you touch
  before changing anything. Its hard rules are non-negotiable.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) describes how the code is organized and why.
- [docs/STORE_AUDIT.md](docs/STORE_AUDIT.md) records what the live store actually contains
  (collection handles, metafields, markets). Prefer it over assumptions in PROMPT.md.
- [CHANGELOG.md](CHANGELOG.md) and `docs/ARCHITECTURE.md` must be updated with every change.

## Hard rules in short

- Shopify is the only source of product truth; never hardcode prices, specs, ratings or claims.
- No Apple In-App Purchase. Checkout only through Shopify Checkout Kit.
- The words PayPal, Hotline and the `tel:` scheme never appear in code or String Catalogs.
- German copy: formal "Sie", calm, no em or en dashes. All 11 languages via String Catalogs.
- No analytics, crash reporting or push registration before explicit consent.
- Never log PII (use `KXLogger`, which redacts).
- Complete, compiling code only: no TODOs, stubs or placeholders.

## Layout

| Path | What |
| --- | --- |
| `App/` | App target `KARINEX`: composition root, root tab view, resources, tests, UI tests |
| `Packages/Core` | Foundation-only infrastructure (config, logging, HTTP, retry, storage, consent, flags) |
| `Packages/ShopifyKit` | Storefront GraphQL client, models, operations, repositories, fixtures |
| `Packages/DesignSystem` | `DesignTokens` (pure Swift) and `DesignSystem` (SwiftUI components, gallery) |
| `Packages/Features` | One module per feature (Home, Catalog, Search, Cart, Account, ...) |
| `Tools/FixtureRecorder` | Records Storefront API fixtures from the live store |
| `Config/` | `.xcconfig` files; `Secrets.xcconfig` is git-ignored |
| `project.yml` | XcodeGen spec; `KARINEX.xcodeproj` is generated from it and committed |

## Everyday commands

```sh
make bootstrap       # install tools, create Config/Secrets.xcconfig
make project         # regenerate KARINEX.xcodeproj after editing project.yml
make test            # full test suite on an iOS simulator
make test-packages   # Core, ShopifyKit, DesignTokens with `swift test` (works on Linux too)
make lint            # SwiftFormat + SwiftLint
make check           # String Catalog completeness and copy rules
make fixtures        # re-record Storefront fixtures from the live store
```

## Conventions

- Swift 6 language mode, strict concurrency, iOS 17 minimum. Guard newer APIs with `#available`.
- Tests use Swift Testing; UI tests use XCTest.
- Strings: `Text("feature.key", bundle: .module)` in packages, `Text("key")` in the app target.
  Every key needs a translator comment and all 11 languages (`make check`).
- Colors, fonts, spacing and motion only through the design-system tokens (`KXColor`,
  `.kxFont(_:)`, `KXSpacing`, `KXRadius`, `KXMotion`).
