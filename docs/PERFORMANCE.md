# Performance budgets

Budgets from PROMPT.md section 13, how the architecture supports them, and how they are
measured. Reference device: iPhone 13 (A15), iOS 17, release build, warm network (Wi-Fi) unless
stated otherwise.

## Budgets

| Metric | Budget | How the design supports it | Measured with |
| --- | --- | --- | --- |
| Cold start to first meaningful content (Home hero and trust strip) | < 1.5 s | Home renders its editorial hero and trust strip from bundled layout without waiting for the network; catalog rows stream in with skeletons. `AppContainer` builds dependencies lazily and does no disk or network I/O on the main thread. | MetricKit `MXAppLaunchMetric`, Instruments "App Launch" |
| Skeleton visible after navigation | < 100 ms | `KXSkeleton` and `.kxSkeleton(isActive:)` render immediately from placeholder models | Instruments "SwiftUI" and "Hangs" |
| Storefront query p50 / p95 (EU, LTE) | 300 ms / 900 ms | Queries request only the fields each screen needs (separate `ProductSummary` and product detail fragments); identical in-flight queries are de-duplicated; `URLCache` 20 MB memory, 100 MB disk | `KXLogger` debug timing per operation, Instruments "Network" |
| Image bytes per product card | < 40 KB | Shopify CDN `width` parameter sized to the rendered width times the screen scale, WebP through the `Accept: image/webp` header (a 147 KB JPEG becomes about 15 KB) | Instruments "Network" |
| Checkout sheet first paint after "Zur Kasse" | < 1 s | Checkout Kit `preload(checkout:)` when the cart appears and after each cart change (debounced) (Phase 1) | Stopwatch on device, Checkout Kit logs |
| Scrolling | 0 hitches > 33 ms in catalog lists | Lazy stacks, fixed aspect ratios for images, no layout work that depends on image size, prefetch of the next row (Phase 1) | Instruments "Animation Hitches", MetricKit `MXAnimationMetric` |
| Memory while browsing | < 150 MB | Bounded image memory cache, no retained full-size images | Xcode memory gauge, MetricKit |
| Main-thread I/O | none | Keychain, UserDefaults writes and network happen off the main actor; view models are `@MainActor` but await work on other executors | Thread Performance Checker (enabled in the scheme), Instruments |

## Rules for contributors

- No synchronous network, disk or Keychain calls from views or `@MainActor` code paths that run
  during rendering.
- Every list screen has a skeleton state; no spinners in the middle of empty screens.
- New GraphQL fields must be justified by a screen that displays them; keep query cost low
  (tokenless requests are capped at 1000).
- Images always go through `ShopifyImage.url(width:)`.

## Measurement plan

- Phase 1: add an Instruments template and a UI test that measures launch with
  `XCTApplicationLaunchMetric` and scrolling with `XCTOSSignpostMetric.scrollDecelerationMetric`
  on CI simulators as a trend signal (not a gate; simulators are not representative).
- Phase 3: device measurements on iPhone 13 for every budget above, results recorded in this
  file with date and build number.
- MetricKit payloads are collected on device by default (on-device only, no upload). Uploading
  diagnostics requires the crash-report consent (PROMPT.md 3.10).
