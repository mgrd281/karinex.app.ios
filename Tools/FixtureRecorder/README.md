# FixtureRecorder

Records the ShopifyKit test fixtures from the live KARINEX Storefront API with the real
`StorefrontClient` (so every response is also decoded and validated) and stores the raw
response bodies, deterministically pretty-printed, plus a `manifest.json`.

```sh
cd Tools/FixtureRecorder
swift run fixture-recorder --output ../../Packages/ShopifyKit/Tests/ShopifyKitTests/Fixtures
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--shop-domain` | `45dv93-bk.myshopify.com` | myshopify domain of the store |
| `--api-version` | `2026-07` | Storefront API version |
| `--token` | none (tokenless) | public Storefront access token; also read from `KX_STOREFRONT_TOKEN` |
| `--output` | required | fixture directory |

Runs on macOS 14+ and Linux (URLSession from FoundationNetworking).

## Structure

- `Sources/FixtureRecording`: the library with all logic.
  - `FixturePlan.swift`: which operations are recorded in which context and what outcome is
    expected, plus the synthetic `synthetic_*.json` envelopes (documented Shopify formats).
  - `FixtureRecorder.swift`: runs the plan and writes the fixtures and `manifest.json`.
  - `RecordingHTTPClient.swift`: `HTTPClient` decorator that keeps the raw responses.
  - `FixtureJSON.swift`: `JSONValue` with a platform-independent pretty printer and the
    `FixtureAnonymizer` (cart, checkout, customer and address IDs, checkout URLs, personal
    fields).
  - `CommandLineOptions.swift`: argument parsing.
- `Sources/fixture-recorder`: the executable entry point.
- `Tests/FixtureRecordingTests`: offline tests with a canned transport (`swift test`).

## Safety

The store is production. The plan only contains read queries and a single `cartCreate`
whose merchandise ID (`gid://shopify/ProductVariant/1`) does not exist, so Shopify answers
with a user error and creates nothing. Do not add other mutations to the plan. The token is
never written to any file.

See `Packages/ShopifyKit/Tests/ShopifyKitTests/Fixtures/README.md` for the recorded files.
