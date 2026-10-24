# Pinned API and dependency versions

PROMPT.md section 3.8 requires verifying the current stable versions on the day work starts
and pinning them explicitly. This file is the record of that verification. Re-verify before
each phase and before every App Store submission.

## Verification of 2026-09-26

| Item | Pinned | Where it is pinned | Evidence |
| --- | --- | --- | --- |
| Shopify Storefront API | `2026-10` | `Config/Base.xcconfig` (`KX_STOREFRONT_API_VERSION`) | 2026-10 became the latest stable version on 2026-10-01 (commit `0c53502`); [shopify.dev/docs/api/usage/versioning](https://shopify.dev/docs/api/usage/versioning). Until 2026-09-26 the pin was `2026-07`. Fixtures were re-recorded against 2026-10. |
| Shopify Customer Account API | `2026-10` | `Config/Base.xcconfig` (`KX_CUSTOMER_ACCOUNT_API_VERSION`) | Same versioning page. Phase 2 starts from the `graphql_api` URL of the store's discovery document `https://karinex.de/.well-known/customer-account-api`, which returned the `2026-07` path on 2026-09-26; re-check it and that the `2026-10` path is served before the first Customer Account request. |
| Checkout Kit (`Shopify/checkout-sheet-kit-swift`) | `3.9.2` (`from: "3.9.2"`, resolved `3.9.2`) | `Packages/Features/Package.swift`, resolved in `KARINEX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Latest stable tag `3.9.2`; `3.9.0` (2026-09-18) was the latest on 2026-09-26. `4.0.0-rc.2` (2026-01-23) is a pre-release and is not used. 3.9 exposes `ShopifyCheckoutSheetKit.preload(checkout:)`, `present(checkout:from:delegate:)`, `CheckoutDelegate` (`checkoutDidComplete`, `checkoutDidCancel`, `checkoutDidFail`, `checkoutDidClickLink`, `checkoutDidEmitWebPixelEvent`) and `Configuration` (`colorScheme`, `tintColor`, `backgroundColor`, `title`, `preloading`, `closeButtonTintColor`). |
| Visitor consent to checkout | `@inContext(visitorConsent:)` | `ShopifyKit` (`StorefrontContext`) | [Changelog 2025-09-02](https://shopify.dev/changelog/incontext-directive-supports-visitor-consent-for-privacy-compliant-checkouts) and [Checkout Kit privacy compliance](https://shopify.dev/docs/storefronts/mobile/checkout-kit/privacy-compliance): requires Storefront API 2025-10 or later; Shopify encodes the consent into the `checkoutUrl`. |
| Swift toolchain (Linux CI) | Swift `6.4.0` | `.github/workflows/ci.yml` | [swift.org releases](https://www.swift.org/api/v1/install/releases.json): 6.4.0 released 2026-09-14. |
| Xcode (macOS CI) | latest stable on the runner | `.github/workflows/ci.yml` (`setup-xcode: latest-stable`) | PROMPT.md requires Xcode 26.x or newer. The exact version is printed in every CI run. |
| swift-snapshot-testing | `1.19.6` (`from:`) | `Packages/DesignSystem/Package.swift` | Latest tag on 2026-09-26. |
| XcodeGen | `2.46.0` | `Makefile`, CI | Latest tag on 2026-09-26. |
| SwiftLint | `0.65.1` | CI, `Makefile` | Latest tag on 2026-09-26. |
| SwiftFormat | `0.63.0` | CI, `Makefile` | Latest tag on 2026-09-26. |
| Nuke (image pipeline) | `13.2.0` (`from: "13.2.0"`, resolved `13.2.0`) | `Packages/Features/Package.swift`, `Package.resolved` | Latest tag on 2026-09-26. Products `Nuke` and `NukeUI`. |

## Endpoints (from the live store)

| Purpose | URL |
| --- | --- |
| Storefront GraphQL | `https://45dv93-bk.myshopify.com/api/2026-10/graphql.json` |
| OpenID configuration | `https://karinex.de/.well-known/openid-configuration` (issuer `https://shopify.com/authentication/91753283851`) |
| Authorization | `https://account.karinex.de/authentication/oauth/authorize` |
| Token | `https://account.karinex.de/authentication/oauth/token` |
| End session | `https://account.karinex.de/authentication/logout` |
| Customer Account GraphQL | `https://account.karinex.de/customer/api/2026-07/graphql` (as advertised on 2026-09-26; the app reads the live discovery document) |

The app does not hardcode the Customer Account endpoints: it reads them from the discovery
documents at runtime (PROMPT.md 5.4) and caches them. They are listed here for reference only.
The OpenID configuration advertises `code_challenge_methods_supported: ["S256"]` and the scopes
`openid`, `email` and `customer-account-api:full`, matching PROMPT.md 4.

## Upgrade procedure

1. Read the Shopify changelog for every version between the pinned one and the target.
2. Change `KX_STOREFRONT_API_VERSION` / `KX_CUSTOMER_ACCOUNT_API_VERSION` in `Config/Base.xcconfig`.
3. Re-record fixtures (`make fixtures`) and run `make test-packages`; decoding tests fail loudly
   on schema changes.
4. Update this file and `CHANGELOG.md`.
