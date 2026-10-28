# Payment icons

The acceptance marks of the payment methods the app shows (Apple Pay and Google Pay, the card
brands Shopify reports in `shop.paymentSettings`, UnionPay, Klarna), taken from Shopify's
open-source set
[activemerchant/payment_icons](https://github.com/activemerchant/payment_icons) (MIT license,
see `MIT-LICENSE`), the same icons Shopify themes show in the web shop footer.

The SVGs here are the sources; the only change is that the Display P3 colour declarations were
removed so every renderer uses the sRGB colours of the files. The app uses PDF copies of them in
`Packages/Features/Sources/CommerceUI/Resources/PaymentMethods.xcassets` (converted with
CairoSVG, vector data preserved). The brand marks themselves belong to their owners and are only
used to show which payment methods the shop accepts. Only the methods of PROMPT.md section 2
are included. `unionpay.svg` and `google_pay.svg` (added 2026-10-26) declare no Display P3
colours and are unchanged. Rechnung and Vorkasse have no brand mark; `invoice.svg` and `prepayment.svg` are the app's own
marks for them (drawn for KARINEX on 28.10.2026, not part of the MIT set), converted the same way.
