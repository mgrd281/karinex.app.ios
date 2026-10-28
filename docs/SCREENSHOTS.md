# Screenshot shot list

Screenshots for App Store Connect, the same set in all 13 languages. They are taken from the
running app against the live store, so every product, price and text on them is real store
content in the market of the language. Nothing is retouched in: no invented prices, ratings,
badges or claims, and no device frames with marketing text that the app does not show.

## Sizes

| Device class | Simulator | Required |
| --- | --- | --- |
| iPhone 6.9" | iPhone 17 Pro Max | yes |
| iPhone 6.3" | iPhone 17 Pro | recommended |
| iPad 13" | iPad Pro 13-inch (M5) | yes if the iPad build ships |

## Markets per language

| Language | Market (country picker) |
| --- | --- |
| de | Deutschland |
| en | Deutschland (English UI) |
| pl, nl, pt-PT, sv, da, es, fr, it, fi, ro, el | PL, NL, PT, SE, DK, ES, FR, IT, FI, RO, GR |

## Shots

| # | Screen | State | Shows |
| --- | --- | --- | --- |
| 1 | Start | Light mode, signed out | Hero, deal and bestseller carousels from the store |
| 2 | Shop, category | Light mode | Product grid with filters |
| 3 | Product detail | Light mode | Gallery, price of the market, specs, refund condition next to the promise |
| 4 | Warenkorb | One product | Totals as Shopify returns them, "Zur Kasse" |
| 5 | Checkout | Shopify checkout sheet | Apple Pay, card, Klarna (whatever the store shows) |
| 6 | Konto, Bestellungen | Reviewer account | Orders with status pills |
| 7 | Meine Lizenzen | Reviewer account, key masked | The license vault; never a real key in clear text |
| 8 | Hilfe und Support | Within support hours | WhatsApp, e-mail and live chat, the hours |
| 9 | Start | Dark mode | The dark theme |

## How to take them

1. Sign in with the reviewer account on a clean simulator; set the language under
   Settings > KARINEX > Language and the market in the app.
2. Status bar: `xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100`.
3. Take each shot with `xcrun simctl io booted screenshot <language>-<number>.png`.
4. Store them under `fastlane/screenshots/<locale>/` (the locales of `fastlane/metadata`).
