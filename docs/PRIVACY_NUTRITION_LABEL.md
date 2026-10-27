# App Privacy (nutrition label)

The answers for App Store Connect, "App Privacy", derived from what the code actually does.
`App/Resources/PrivacyInfo.xcprivacy` declares the same data types. Update both together
whenever a feature starts or stops handling data.

## Tracking

**No.** The app does not track: no advertising identifier, no third-party analytics or
advertising SDK, no data broker, no fingerprinting. `NSPrivacyTracking` is `false` and there are
no tracking domains. No App Tracking Transparency prompt is needed.

## Data linked to the user

Collected only after the customer signs in with their Shopify customer account, and used only
for app functionality (showing the account, orders, keys and addresses). Shopify stores it as
KARINEX's service provider; the BFF reads it to check order ownership.

| App Store category | Data type | Where it comes from | Purpose |
| --- | --- | --- | --- |
| Contact Info | Name | Customer Account API `customer` | App Functionality |
| Contact Info | Email Address | Customer Account API `customer`; BFF token check | App Functionality |
| Contact Info | Physical Address | Customer Account API addresses (view and edit) | App Functionality |
| Purchases | Purchase History | Customer Account API orders; BFF delivery states, keys, invoices | App Functionality |
| Identifiers | Device ID | The APNs device token, sent to the BFF only after the customer turned on notifications in the settings | App Functionality |

Not collected: no contact number field exists in the app, in the address form or in the
Customer Account queries.

## Data not linked to the user

None today.

## Data that is not declared, and why

| Data | Reason |
| --- | --- |
| Payment info | Entered only in Shopify Checkout (Checkout Kit). KARINEX never receives card data; Apple Pay and the payment providers process it. The owner confirms this matches the store's payment setup before submission. |
| Cart contents | The anonymous Storefront cart ID is kept on the device to restore the cart; it identifies no person and is not linked to an account until checkout. |
| Market and language | Stored on the device; sent to Shopify as `@inContext` to get prices and texts of the right market. Not collected. |
| Support messages | WhatsApp, e-mail and live chat open outside the app; the app only prefills an order number. |
| Usage data, diagnostics | Not collected, with one opt-in exception: after the customer turned on usage analytics in Settings, the product page reads and updates the store's anonymous save counter of the product (`SaveCountStore`, only the product handle, no identifier). `.crashReports` is not read yet; no SDK is linked. If one is added it starts only after opt-in, and this document and the manifest change before release. |
| Wishlist and recently viewed | Product IDs stored on the device only; never sent anywhere. |
| Widget | Requests the public bestseller collection from Shopify with the device's region and language; no identifier is sent. |

## On-device storage

- Customer Account tokens and delivered license keys: Keychain,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, removed on sign-out and after an account
  deletion request.
- Preferences (market, appearance, license lock, consent): `UserDefaults`
  (`NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`).

## Account deletion

Konto, "Konto löschen" sends `POST /v1/app/account/delete` (see
[BFF_CONTRACT.md](BFF_CONTRACT.md)). Without a backend the app opens a prepared e-mail to
`kundenservice@karinex.de`. This satisfies guideline 5.1.1(v).

## Privacy policy URL

The store's privacy policy, served by Shopify (`shop.privacyPolicy`), shown in the app under
Rechtliches and linked in App Store Connect as `https://karinex.de/policies/privacy-policy`.
