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
| `--api-version` | `2026-10` | Storefront API version |
| `--token` | none (tokenless) | public Storefront access token; also read from `KX_STOREFRONT_TOKEN` |
| `--output` | required | fixture directory |

Runs on macOS 14+ and Linux (URLSession from FoundationNetworking).

## Structure

- `Sources/FixtureRecording`: the library with all logic.
  - `FixturePlan.swift`: which operations are recorded in which context and what outcome is
    expected (`FixtureSpec`, with deferred specs whose variables come from earlier steps
    through a `FixtureSession`), plus the synthetic `synthetic_*.json` envelopes (documented
    Shopify formats).
  - `FixtureRecorder.swift`: runs the plan and writes the fixtures and `manifest.json`.
  - `RecordingHTTPClient.swift`: `HTTPClient` decorator that keeps the raw responses.
  - `FixtureJSON.swift`: `JSONValue` with a platform-independent pretty printer and the
    `FixtureAnonymizer` (cart tokens in cart, line and checkout IDs and checkout URLs,
    customer and address IDs, personal fields; replaced with `REDACTED`, shape kept).
  - `CommandLineOptions.swift`: argument parsing.
- `Sources/fixture-recorder`: the executable entry point.
- `Tests/FixtureRecordingTests`: offline tests with a canned transport (`swift test`).

## Safety

The store is production. The plan contains read queries, one `cartCreate` whose merchandise
ID (`gid://shopify/ProductVariant/1`) does not exist (Shopify answers with a user error and
creates nothing), and one cart lifecycle on a cart the recorder creates itself with the two
cheapest digital variants: `cartCreate`, `cartLinesAdd`, `cartLinesUpdate`,
`cartDiscountCodesUpdate` (a code that does not exist), `cartLinesRemove`, then `cart(id:)`.
`FixturePlan.allowedMutations` lists these operations and a test fails if the plan sends any
other; cart mutations refuse to run unless the same run created the cart (`FixtureSession`).
The checkout URL is never opened, so the cart never becomes an order and expires on its own;
its attribute `kx_fixture_recording=true` marks it among abandoned carts. Do not add other
mutations to the plan.

Cart IDs, line IDs and checkout URLs carry the secret cart token. `FixtureAnonymizer`
replaces the token parts with `REDACTED` in every body and in the variables of the manifest,
keeping the shape (`gid://shopify/Cart/REDACTED?key=REDACTED`). The token is never written
to any file, and no customer data is requested.

See `Packages/ShopifyKit/Tests/ShopifyKitTests/Fixtures/README.md` for the recorded files.
