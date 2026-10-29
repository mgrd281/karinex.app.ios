# App Store review notes

Text for App Store Connect, "App Review Information", plus the background a reviewer may ask
about. Paste the English block into "Notes"; keep the rest for replies in Resolution Center.

## Notes for the reviewer (paste into App Store Connect)

```
KARINEX is the native app of the online store karinex.de. It sells digital license keys for
software that is installed and used on computers outside this app, and a few physical media
that are shipped. Nothing is unlocked inside the app, so purchases go through the store's
Shopify checkout (Shopify Checkout Kit), as guideline 3.1.3(e) and 3.1.5 allow for goods and
services consumed outside the app. The app has no paid features and no In-App Purchase.

Demo account: none. Browsing, search, product pages, cart, checkout (as a guest), legal texts and
support work without an account. The account area (orders, invoices, license vault) uses the
store's own Shopify customer login, which sends a one-time code to the customer's e-mail address;
there is no password. If you need to see the account area, please reply in Resolution Center and
we will give you access to a demo mailbox right away.

Checkout: please place no real order. Opening the checkout and reaching the payment step shows
the full purchase flow (guest checkout, Apple Pay, card, Klarna, invoice, bank transfer).

Account deletion: Konto > Persönliche Daten > Konto und Daten löschen (guideline 5.1.1(v)).
Support: WhatsApp, e-mail and live chat from Konto > Hilfe und Support, daily 08:00 to 23:00 German time.
Tracking: none. Analytics and notifications start only after explicit consent.
Languages: German (primary), English, Polish, Dutch, Portuguese (Portugal), Swedish, Danish,
Spanish, French, Italian, Finnish.
```

The owner decided on 2026-10-29 not to create a reviewer account, a test product or a 100 percent
discount code (see [OWNER_INPUTS.md](OWNER_INPUTS.md)). The notes above say so. If App Review
asks for a demo account (guideline 2.1), reply in Resolution Center and set one up then.

## Background for likely questions

| Topic | Answer |
| --- | --- |
| Guideline 3.1.1 (In-App Purchase) | The keys activate software on a PC or Mac; they are not consumed in the app and unlock nothing in it. Physical media are shipped. Payment happens in Shopify checkout (Apple Pay, Google Pay, card, Klarna, invoice or bank transfer). |
| Guideline 4.2 (minimum functionality) | All screens are native SwiftUI: catalog with filters, product detail, search, cart, account with orders, invoices and a license vault, support, legal texts, settings. The only web surfaces are the Shopify checkout and the Shopify login page, both required by Shopify. |
| Guideline 5.1.1 (data collection) | See [PRIVACY_NUTRITION_LABEL.md](PRIVACY_NUTRITION_LABEL.md). Login data is used only to show the account. |
| Guideline 5.1.1(v) (account deletion) | In the app, Konto > Persönliche Daten > Konto und Daten löschen, sends the erasure request; without a backend it opens a prepared e-mail. |
| Guideline 5.2 (intellectual property) | Product names and descriptions come from the store. The app adds no claims about license origin. |
| Face ID | Optional lock for the license vault, off by default, set under Konto > Einstellungen. `NSFaceIDUsageDescription` is localized. |
| Sign in with Apple (4.8) | Not required: the app offers no third-party social login; login is the store's own customer account. |

## Before each submission

- [ ] Someone can answer App Review in Resolution Center the same day (the notes promise access to the account area on request).
- [ ] `make check` passes (strings, copy rules, metadata).
- [ ] [PRIVACY_NUTRITION_LABEL.md](PRIVACY_NUTRITION_LABEL.md) matches App Store Connect.
- [ ] Screenshots follow [SCREENSHOTS.md](SCREENSHOTS.md).
