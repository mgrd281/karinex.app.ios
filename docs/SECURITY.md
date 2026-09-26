# Security

Threat model and controls for the KARINEX iOS app (PROMPT.md sections 9 and 11). The "Status"
column is honest about what exists today and what lands in a later phase.

## Assets

| Asset | Where it lives | Sensitivity |
| --- | --- | --- |
| Public Storefront token | App binary (Info.plist, injected from git-ignored `Config/Secrets.xcconfig`) | Public by design (Shopify "public" token); rotate if abused |
| Customer Account tokens (access, refresh, id) | Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | High: grants access to the customer's orders and addresses |
| License keys (cached for offline viewing) | Keychain, same accessibility, never in UserDefaults, logs or backups | High: a key is money |
| Cart ID, market, language, appearance, consent choices | UserDefaults | Low |
| Invoices | Short-lived signed URLs from the BFF; never cached to disk | Medium |

Secrets that must **never** ship in the app: Admin API tokens, BFF secrets, APNs keys, App
Store Connect keys. The app only talks to the Storefront API, the Customer Account API and the
KARINEX BFF; it never calls the Admin API (hard rule 9).

## Controls

| Control | Status | Where |
| --- | --- | --- |
| Only the public Storefront token in the binary, from a git-ignored xcconfig | Phase 0 | `Config/Base.xcconfig`, `Config/Secrets.example.xcconfig`, `.gitignore` |
| Tokenless fallback when no token is configured (no secret needed for CI builds) | Phase 0 | `ShopifyKit` `StorefrontConfiguration` |
| Keychain wrapper with device-only accessibility, non-synchronizable items, per-service wipe | Phase 0 | `Core` `KeychainStore` |
| Logging without PII: every log line passes through `Redactor` (emails, bearer tokens, Shopify tokens, JWTs, product keys, cart tokens, OAuth query items) | Phase 0 | `Core` `KXLogger`, `Redactor` |
| GraphQL client never logs variables or bodies | Phase 0 | `ShopifyKit` `GraphQLClient` |
| Mutations are never replayed after an ambiguous failure (no duplicate cart lines) | Phase 0 | `ShopifyKit` retry rules |
| App Transport Security enforced (no exceptions in Info.plist) | Phase 0 | `App/Info.plist` |
| Privacy manifest, no tracking, no tracking domains | Phase 0 | `App/Resources/PrivacyInfo.xcprivacy` |
| No analytics, crash reporting or push before explicit opt-in; consent stored and revocable | Phase 0 model, Phase 2 UI | `Core` `PrivacyConsent`, `ConsentStore` |
| Consent passed to checkout via `@inContext(visitorConsent:)` | Phase 0 client, Phase 1 cart | `ShopifyKit` `StorefrontContext` |
| OAuth 2.0 Authorization Code + PKCE (S256), `state` and `nonce` validation, `ASWebAuthenticationSession` with ephemeral session | Phase 2 | `ShopifyKit` Customer Account client |
| Silent token refresh, logout through `end_session_endpoint` with `id_token_hint`, Keychain wipe on logout and account deletion | Phase 2 | `AccountFeature` |
| License vault: privacy overlay in the app switcher, optional Face ID / Touch ID gate, clipboard copy with 120 s expiry and `localOnly` | Component in Phase 0 (`KXClipboard`), vault in Phase 2 | `DesignSystem`, `LicensesFeature` |
| BFF calls authenticated with the Customer Account access token; the BFF validates it against Shopify and checks order ownership; per-token rate limits and audit log of key reads | Phase 2 (server side) | `BFF_CONTRACT.md` |
| Optional certificate pinning for the BFF host | Phase 2, decision pending | |
| Jailbreak detection | Not planned (PROMPT.md 11) | |

## Reporting

Report vulnerabilities privately to kundenservice@karinex.de with the subject "Security".
Do not open public GitHub issues for security problems.

## Developer checklist

- Never paste a real token, license key or customer e-mail into code, tests, fixtures or logs.
  Fixtures are recorded from public catalog data only; the recorder writes no customer data.
- `Config/Secrets.xcconfig` stays local. CI writes it from repository secrets.
- New persistence of anything sensitive goes into the Keychain through `SecureStore`.
- New log statements use `KXLogger`; do not use `print` or `NSLog`.
