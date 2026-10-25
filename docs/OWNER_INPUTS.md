# Owner inputs (PROMPT.md section 15)

Status of every input the owner must provide. Values that could be verified from the live
store were filled in; everything else is still open. Secrets never go into git: they belong in
`Config/Secrets.xcconfig` locally and in GitHub Actions secrets for CI.

| Input | Status | Value / where it goes | Needed for |
| --- | --- | --- | --- |
| `{{SHOP}}`, `{{SHOP_ID}}` | Done (verified) | `45dv93-bk.myshopify.com`, `91753283851` in `Config/Base.xcconfig` | Phase 0 |
| `{{STOREFRONT_VERSION}}`, `{{CUSTOMER_ACCOUNT_VERSION}}` | Done (verified) | `2026-10` / `2026-10`, see [API_VERSIONS.md](API_VERSIONS.md) | Phase 0 |
| `{{STOREFRONT_PUBLIC_TOKEN}}` | **Open** | `KX_STOREFRONT_ACCESS_TOKEN` in `Config/Secrets.xcconfig` + CI secret. The app runs tokenless until then (no metafields). | Phase 1 (product specs, FAQ) |
| `{{CUSTOMER_ACCOUNT_CLIENT_ID}}` | **Open** | `KX_CUSTOMER_ACCOUNT_CLIENT_ID` in `Config/Secrets.xcconfig` + CI secret | Phase 2 |
| `{{CUSTOMER_ACCOUNT_REDIRECT_URI}}` | Decided, **owner registers it** | `shop.91753283851.app://callback`, the format Shopify requires for mobile clients (derived from `KX_SHOP_ID`). Register it in Headless (or the Customer Account API app) > Callback URIs, together with the client type "Public". | Phase 2 |
| `{{WHATSAPP_NUMBER}}` | **Open** | Served by the BFF `/v1/app/config` so it can change without an app release. Shown only as a WhatsApp action, never as a phone number. | Phase 2 |
| `{{LIVE_CHAT_URL}}` | **Open** (a `live-chat` page exists on the store) | BFF `/v1/app/config` | Phase 2 |
| `{{BFF_BASE_URL}}` | **Open** | Host name only (HTTPS, no path) as `KX_BACKEND_HOST` in `Config/Base.xcconfig` or `Secrets.xcconfig`. The service must implement [BFF_CONTRACT.md](BFF_CONTRACT.md); until then the app uses its e-mail fallbacks. | Phase 2 |
| `{{BUNDLE_ID}}` | Done (registered) | `de.karinex.app` and `de.karinex.app.widgets` (the widget extension) exist as App IDs in the developer account | Phase 1 (TestFlight) |
| `{{APPLE_TEAM_ID}}` | Provided | `3227J7CBXY`. Still to do by the owner: add it as the GitHub secret `KX_APPLE_TEAM_ID` (and in `Config/Secrets.xcconfig` for local device builds) | Phase 1 (device builds, TestFlight) |
| App Store Connect API key | **Open** | CI secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` (base64 of the .p8) | Phase 1 (TestFlight lane) |
| Universal Links | **Open** | `apple-app-site-association` on `www.karinex.de` with the team ID and bundle ID | Phase 1 |
| Collection handles | Verified, differ from PROMPT.md | See [STORE_AUDIT.md](STORE_AUDIT.md): `microsoft-office`, `windows-server`, no `blitzangebote` | Phase 1 |
| Impressum page handle | Assumed, **please confirm** | The app shows the page `rechtliche-hinweise` as Impressum and `widerrufsrecht` as Widerrufsbelehrung (refund policy as fallback) | Phase 2 |
| Blog handle | Verified | `news` and `guides` | Phase 1 |
| Metafield definitions | **Open** | See [STORE_AUDIT.md](STORE_AUDIT.md), owner actions 2 and 3 | Phase 1 |
| Logo | Interim | Typographic wordmark "KARINEX" (`KXWordmark`) | |
| App icon | Concept delivered for approval | `App/Resources/Assets.xcassets/AppIcon.appiconset`: gold serif "K" monogram with a double gold ring on forest green | Phase 1 |
| Reviewer account, test product, 100 % discount code | **Open** | Needed for App Review | Phase 3 |
