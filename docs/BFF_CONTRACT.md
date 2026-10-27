# BFF contract

The app talks to two kinds of servers: Shopify (Storefront API, Customer Account API, Checkout)
for everything about products, carts, customers and orders, and the KARINEX backend for
frontend (BFF) for the things Shopify cannot answer: license keys, invoice PDFs, the delivery
state reported by the fulfillment service, account deletion, push device registration and the
support configuration. This document is the contract between `Packages/Backend` (`BackendKit`)
and that service. The machine-readable form is [`openapi.yaml`](openapi.yaml) (OpenAPI 3.1);
[`Tools/MockBFF`](../Tools/MockBFF) implements it for local development.

## Base URL and configuration

- The base URL is `https://<KXBackendHost>`, read from the `KXBackendHost` Info.plist key
  (`BACKEND_HOST` in `Config/*.xcconfig`). Without a host the app uses
  `UnavailableBackendClient`: `/config` falls back to built-in values and every other call
  fails with `notConfigured`, which the screens turn into their e-mail fallbacks.
- All paths start with `/v1/app`. A breaking change gets a new prefix (`/v2/app`); the app
  keeps calling the version it was built against.
- Only HTTPS. Links in responses (invoice, activation guide, live chat) must be `https`; the app
  drops any other scheme.

## Requests

| Header | Value |
| --- | --- |
| `Authorization` | `Bearer <Customer Account API access token>` on every endpoint except `/config` |
| `Accept` | `application/json` |
| `Accept-Language` | The UI language, e.g. `de`, `fi`, `pt-PT` |
| `X-KX-App-Version` | The marketing version, e.g. `0.2.0` |
| `If-None-Match` | The last `ETag` of `/config` |
| `Content-Type` | `application/json` on requests with a body |

### Authentication

The token is the customer's Customer Account API access token. The BFF validates it by calling
the Customer Account API with it:

```graphql
query { customer { id emailAddress { emailAddress } } }
```

and resolves order ownership through its own Admin API access. A token Shopify rejects is a
`401`; an order that belongs to someone else is a `403` (never `404`, so the answer does not
reveal whether the order exists to another customer's token, and never the order's data).

The app never sends the token anywhere else, never logs it, and refreshes it before it
expires. After a `401` the app refreshes once and retries; a second `401` signs the customer out.

### Retries

The app repeats `GET` requests after timeouts, transport errors, `429` and `500` to `504`, with
exponential backoff and `Retry-After` (seconds, capped at 60). `POST` and `DELETE` are never
repeated by the app, so they must be idempotent on the server anyway (a repeated deletion
request returns the same `requestId`).

## Errors

Every non-2xx response carries:

```json
{ "code": "order_not_owned", "message": "The order does not belong to this customer.", "requestId": "req_01J9Z4" }
```

- `code`: a stable machine-readable snake_case string.
- `message`: an English text for logs. The app never shows it; it shows its own localized copy.
- `requestId`: echoed in the app's logs and given to support on request.

| Status | Meaning | App behavior |
| --- | --- | --- |
| `401` | Token missing, expired or rejected | Refresh once, then sign out |
| `403` | Order not owned by the customer | "Nicht gefunden" |
| `404` | Unknown order or endpoint not offered | Licenses and invoices: e-mail fallback |
| `429` | Rate limited; `Retry-After` set | Retry (GET), else "Zu viele Anfragen" |
| `5xx` | Server error | Retry (GET), else "Server nicht erreichbar" |

## Endpoints

### `GET /v1/app/config`

Unauthenticated. Lets the owner change support details and switches without an app release.
Answer with an `ETag`; the app sends `If-None-Match` and accepts `304 Not Modified`.

```json
{
  "supportHours": { "timeZone": "Europe/Berlin", "weekdays": [1, 2, 3, 4, 5, 6, 7], "opensAt": "06:00", "closesAt": "23:00" },
  "whatsappNumber": "4940123456",
  "liveChatUrl": "https://karinex.de/pages/live-chat",
  "supportEmail": "kundenservice@karinex.de",
  "featureFlags": { "licenseVault": true },
  "minSupportedAppVersion": "0.2.0"
}
```

| Field | Type | Notes |
| --- | --- | --- |
| `supportHours` | object | `weekdays` are ISO weekdays (1 Monday to 7 Sunday); `opensAt` before `closesAt`, `HH:mm` in `timeZone`. Missing: Monday to Sunday 06:00 to 23:00 Europe/Berlin |
| `whatsappNumber` | string or null | International format, digits only. Used exclusively to build a `https://wa.me/` link; the app never displays it as a number to dial. Missing or fewer than six digits: no WhatsApp button |
| `liveChatUrl` | string or null | `https` only. Missing: no live chat button |
| `supportEmail` | string | Missing: `kundenservice@karinex.de` |
| `featureFlags` | object of booleans | Unknown flags are ignored |
| `minSupportedAppVersion` | string or null | Older apps ask the customer to update |

There is deliberately no field for a voice support channel: KARINEX offers support by
WhatsApp, e-mail and live chat only.

### `GET /v1/app/orders`

The customer's orders as the fulfillment service knows them, newest first, at most 100.

```json
{
  "orders": [
    { "orderId": "5678", "name": "#1042", "deliveryStatus": "delivered", "hasLicenses": true, "hasInvoice": true }
  ]
}
```

| Field | Type | Notes |
| --- | --- | --- |
| `orderId` | string | Numeric Shopify order ID (the last segment of the order GID) |
| `name` | string or null | Order name, e.g. `#1042` |
| `deliveryStatus` | `pending`, `delivered`, `shipped` | Unknown values are read as `pending` |
| `hasLicenses` | boolean | Default `false` |
| `hasInvoice` | boolean | Default `true` |

Prices, totals and line items are not part of this response: the app reads them from the
Customer Account API, the only source of order truth.

### `GET /v1/app/orders/{orderId}/licenses`

The keys of one order. Audit-log every read (customer, order, request ID; never the key).

- `200` with the keys, `202` (empty body allowed) while delivery is pending, `403` for an order
  of another customer.

```json
{
  "licenses": [
    {
      "lineItemId": "13021827334411",
      "productTitle": "Office 2024 Professional Plus",
      "sku": "OFF-2024-PP",
      "key": "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX",
      "deliveredAt": "2026-10-20T09:41:00Z",
      "activationGuideUrl": "https://karinex.de/blogs/guides/office-2024-aktivieren"
    }
  ]
}
```

A line with quantity 2 has two entries with the same `lineItemId`. `deliveredAt` is ISO 8601
with or without fractional seconds. The app stores keys only in the Keychain
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), deletes them on sign-out, and never logs them.

### `GET /v1/app/orders/{orderId}/invoice`

A short-lived signed link to the invoice PDF.

```json
{ "url": "https://files.karinex.de/invoices/5678.pdf?sig=abc", "expiresAt": "2026-10-25T10:15:00Z" }
```

`404` when there is no invoice yet; the app then says the invoice comes by e-mail.

### `POST /v1/app/account/delete`

Starts the GDPR erasure workflow (Art. 17 GDPR, App Store guideline 5.1.1(v)). Body
`{ "confirm": true }`. Answer `202`:

```json
{ "requestId": "del_01J9Z7" }
```

The app then removes the tokens and the key cache from the device. The customer receives a
confirmation by e-mail; statutory retention of invoices is explained there.

### `GET /v1/app/loyalty`

The customer's standing in the loyalty program. The backend computes every number from an
append-only ledger; the app shows them and never calculates points. Signed in with the customer
token like the other routes.

```json
{
  "enabled": true,
  "tier": { "id": "gold", "points": 1573, "pending": 120,
            "next": { "tier": "platin", "min": 2500, "remaining": 927 },
            "progress": 0.63, "maxReached": false },
  "discount": { "active": true, "percent": 5, "next": { "tier": "platin", "percent": 8 },
                "ladder": [{ "tier": "silber", "min": 1000, "percent": 3 },
                           { "tier": "gold", "min": 2500, "percent": 5 }] },
  "perks": [{ "de": "Früher Zugang zu Aktionen", "en": "Early access to promotions" }],
  "reward": { "available": 1840, "pending": 120,
              "expiringSoon": { "points": 500, "at": "2026-12-01T00:00:00.000Z" } },
  "redeem": { "steps": [{ "points": 1000, "cents": 100, "minSubtotalCents": 1000 }],
              "maxPercent": 20, "minOrderCents": 1000, "codeValidDays": 30 },
  "earn": { "tierPerEuro": 10, "rewardPerEuro": 10, "holdDays": 7,
            "tierWindowMonths": 12, "rewardExpiryMonths": 12 },
  "history": [{ "id": "e1", "type": "EARN", "status": "CONFIRMED", "tierPoints": 399,
                "rewardPoints": 399, "orderNumber": "#1042", "at": "2026-10-20T10:00:00.000Z" }]
}
```

- Two kinds of points: status points (`tier`, never spent, counted over `tierWindowMonths`) and
  reward points (`reward`, redeemable, expire `rewardExpiryMonths` after each credit).
- `tier.id` is `starter`, `silber`, `gold`, `platin`, `diamant` or `elite`; an unknown id (also in
  `tier.next` and `discount`) is shown as `starter`.
- `discount` is the permanent discount of the level. Shopify applies it as an automatic discount to
  every order of a signed-in customer of that level; it combines with a reward code. `active` is
  false (and `percent` 0, `ladder` empty) while the store has it switched off. Older backends omit
  the field.
  `tier.next` is `null` and `maxReached` true at the top level (the ring is full).
- `enabled: false` while the program is switched off (nothing is earned or redeemed).
- Dates are ISO 8601 with or without fractional seconds. `history[].type` is `EARN`, `REFUND`,
  `REDEEM`, `RELEASE`, `ADJUST` or `EXPIRE`; `status` is `PENDING` or `CONFIRMED`.
- Points of an order are credited after payment as pending and confirmed `holdDays` after
  delivery. A refund takes back exactly the linked points.

### `POST /v1/app/loyalty/redeem`

Exchanges reward points for a one-time Shopify discount code (one customer, one use, a fixed
amount, valid `codeValidDays`). Body:

```json
{ "points": 1000, "idempotencyKey": "5D1F3C0E-8E5B-4C1C-9B53-0D2A7E2E4C11" }
```

`idempotencyKey` is 8 to 64 letters, digits, `-` or `_`. The app creates one per attempt and
reuses it after a failure that may have reached the backend, so a repeated tap returns the same
code and never spends the points twice. Answer `200`:

```json
{ "code": "KX-ABCD-1234", "cents": 100, "minSubtotalCents": 1000, "expiresAt": "2026-11-26T10:00:00.000Z" }
```

`409 { "code": "redeem_rejected", "reason": "insufficient" | "disabled" | "in_progress" }`:
refused, no points spent (`in_progress` means the same key is still being processed).
`503` with `Retry-After` when Shopify could not issue the code; the reservation is released.
Points of a code that expires unused are credited back.

### `GET /v1/app/wallet-card`

The customer's KARINEX card for Apple Wallet: the same `.pkpass` the customer account on the web
offers (name, level and points while the loyalty program runs, the license keys on the back). One
card per e-mail; downloading again returns the same serial number, so Wallet replaces the card
instead of adding a second one. The customer is the e-mail of the token, never a parameter.
Answer `200` with `Content-Type: application/vnd.apple.pkpass` (a ZIP archive), `private, no-store`.
`404 not_found` when the account has no card (marketplace relay addresses) or Apple Wallet is not
set up on the backend; the app then shows a short note. At most 10 cards per minute and customer.

### `POST /v1/app/devices` and `DELETE /v1/app/devices/{apnsToken}`

Phase 3. Registers an APNs token only after the customer agreed to notifications.

```json
{ "apnsToken": "a1b2c3", "locale": "de", "country": "DE", "consent": { "orderUpdates": true, "deals": false } }
```

`201` or `204`. `DELETE` answers `204`, and `404` for an unknown token (the app treats both as
success).

## Push payloads (Phase 3)

Sent by the BFF through APNs, only for the categories the device consented to.

| Type | Consent | Payload | App |
| --- | --- | --- | --- |
| `order.paid` | `orderUpdates` | `{ "type": "order.paid", "orderId": "5678", "name": "#1042" }` | Starts the delivery Live Activity |
| `license.delivered` | `orderUpdates` | `{ "type": "license.delivered", "orderId": "5678" }` | Ends the Live Activity, opens `karinex://account/licenses` |
| `deal.started` | `deals` | `{ "type": "deal.started", "collection": "blitzangebote" }` | Opens the collection |

Alert texts are localized on the server with the device's `locale`; they never contain keys,
prices or personal data beyond the order name.

## Rate limits and logging

- Per token: 60 requests per minute; licenses: 20 per minute. Above that `429` with `Retry-After`.
- Logs contain the request ID, route, status and duration. Never tokens, keys, e-mail
  addresses or addresses.
