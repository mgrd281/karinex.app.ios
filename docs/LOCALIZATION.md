# Localization

KARINEX earns about 63 % of its revenue outside Germany, so every language is a first-class
product surface, not a translation afterthought (PROMPT.md section 8).

## Languages

| App language | Catalog ID | Storefront `LanguageCode` | Address form | Notes |
| --- | --- | --- | --- | --- |
| Deutsch (source) | `de` | `DE` | **Sie** (formal) | Source of truth for every string |
| English | `en` | `EN` | you | British English (licence as noun, cancelled, colour) because the audience is European |
| Polski | `pl` | `PL` | impersonal or infinitive UI labels, polite 2nd person where needed | Full CLDR plurals: one, few, many, other |
| Nederlands | `nl` | `NL` | je/jouw | Standard Dutch (Netherlands), works for Flanders |
| Português (Portugal) | `pt-PT` | `PT_PT` | 3rd person formal (o seu, adicione) | European Portuguese only. Never Brazilian forms (no "você", "tela", "celular") |
| Svenska | `sv` | `SV` | du | |
| Dansk | `da` | `DA` | du | |
| Español (España) | `es` | `ES` | tú | Spain vocabulary (ordenador, móvil) |
| Français | `fr` | `FR` | vous | Non-breaking space before `: ; ? !` and inside « » |
| Italiano | `it` | `IT` | tu | |
| Suomi | `fi` | `FI` | implicit 2nd person / passive | Watch length: Finnish compounds are long |

The store also has Greek (`EL`) and Romanian (`RO`) content. The app UI does not support them
in v1; such devices get the English UI and English store content.

## How strings work in code

- Every user-facing string lives in a String Catalog (`.xcstrings`), one per module:
  `App/Resources/Localizable.xcstrings`, `Packages/DesignSystem/Sources/DesignSystem/Resources/Localizable.xcstrings`,
  and `Packages/Features/Sources/<Feature>/Resources/Localizable.xcstrings`.
- Keys are lowercase dot paths (`home.hero.title`). The German value is the source text.
- Packages look strings up in their own bundle: `Text("home.hero.title", bundle: .module)` or
  `String(localized: "home.hero.title", bundle: .module)`. The app target uses `Text("tab.home")`.
- Design-system components receive already-localized `String`s from the caller. Only strings
  that belong to a component itself (for example "Kopieren" on the key card) live in the
  DesignSystem catalog.
- Every key has a `comment` that tells translators where the text appears and how much room
  it has.
- Plurals use catalog plural variations with `%lld`; never build plurals in code.
- Prices come from Shopify as `MoneyV2` and are formatted with the user's `Locale`
  ("11,90 €", "119 kr", "CHF 12.90"). Never put prices or currency symbols in a catalog.
- Dates and support hours are computed in `Europe/Berlin` and formatted for the user's locale.

`make check` (and CI) runs `scripts/check_strings.py`, which fails when a key is missing in any
of the 11 languages, a translation is empty, plural categories are incomplete, format
specifiers differ between languages, code references a key that does not exist, or a catalog
contains a key no code uses. `scripts/check_copy_rules.py` fails on em or en dashes in any
catalog value and on forbidden words.

## Tone rules (all languages)

1. Calm, precise, premium retail. Short sentences. No filler ("einfach", "ganz bequem",
   "super"), no exclamation marks, no emoji.
2. **No em dash (—) or en dash (–)** in any language. Use a comma, colon, period, or the local
   word for "to" in ranges ("06:00 bis 23:00 Uhr", "6:00 to 23:00").
3. No claims the app cannot prove: never "100 % legal", "original licence", "verified",
   "guaranteed genuine", "cheapest" or equivalents in any language. Product texts from Shopify
   are shown as they are; the app adds nothing to them.
4. Payment methods are exactly Apple Pay, credit card, Klarna. Support channels are exactly
   WhatsApp, e-mail and live chat. Never mention other payment methods or phone support.
5. The 100-day money-back promise always carries its condition: it applies only to activated
   licence keys and physical goods; delivered but unactivated keys are not refunded
   voluntarily; statutory warranty rights remain unaffected.
6. Legal references (§ 356 Abs. 5 BGB) appear in German. Other languages describe the same
   rule neutrally ("For digital content, the right of withdrawal ends once delivery starts with
   your express consent.") and do not cite German paragraphs unless the text is shown to a
   German-market user.
7. Tax wording: "inkl. MwSt." only where Shopify's market includes tax (EU). Equivalents: EN
   "incl. VAT", FR "TTC", IT "IVA inclusa", ES "IVA incluido", NL "incl. btw", PL "z VAT",
   PT "IVA incluído", SV "inkl. moms", DA "inkl. moms", FI "sis. ALV". Switzerland and other
   non-EU markets stay neutral.
8. Button labels are verbs or verb phrases in the imperative or infinitive customary for the
   language ("In den Warenkorb", "Add to basket", "Ajouter au panier").
9. Length: the longest languages (FI, PT, DE, PL) must fit. Components wrap rather than
   truncate; still prefer the shorter of two equally natural phrasings.

## Glossary

| Deutsch | English | Français | Italiano | Español | Nederlands | Polski | Português (PT) | Svenska | Dansk | Suomi |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Lizenzschlüssel | licence key | clé de licence | codice di licenza | clave de licencia | licentiesleutel | klucz licencyjny | chave de licença | licensnyckel | licensnøgle | lisenssiavain |
| Warenkorb | basket | panier | carrello | cesta | winkelwagen | koszyk | carrinho | varukorg | kurv | ostoskori |
| Zur Kasse | Checkout | Passer la commande | Vai alla cassa | Tramitar pedido | Afrekenen | Przejdź do kasy | Finalizar compra | Till kassan | Til kassen | Kassalle |
| Bestellung | order | commande | ordine | pedido | bestelling | zamówienie | encomenda | beställning | ordre | tilaus |
| Rechnung | invoice | facture | fattura | factura | factuur | faktura | fatura | faktura | faktura | lasku |
| Konto | account | compte | account | cuenta | account | konto | conta | konto | konto | tili |
| Anmelden | Sign in | Se connecter | Accedi | Iniciar sesión | Inloggen | Zaloguj się | Iniciar sessão | Logga in | Log ind | Kirjaudu |
| Sortiment | range | catalogue | catalogo | catálogo | assortiment | oferta | catálogo | sortiment | sortiment | valikoima |
| Blitzangebote | Flash deals | Ventes flash | Offerte lampo | Ofertas flash | Flitsaanbiedingen | Błyskawiczne okazje | Ofertas relâmpago | Blixtrea | Lyntilbud | Salamatarjoukset |
| 100 Tage Geld-zurück | 100-day money-back | Remboursement sous 100 jours | Rimborso entro 100 giorni | Reembolso en 100 días | 100 dagen geld terug | 100 dni na zwrot pieniędzy | 100 dias de reembolso | Pengarna tillbaka i 100 dagar | Pengene tilbage i 100 dage | 100 päivän rahat takaisin |
| Lieferung per E-Mail | delivery by e-mail | livraison par e-mail | consegna via e-mail | entrega por correo electrónico | levering per e-mail | dostawa e-mailem | entrega por e-mail | leverans via e-post | levering via e-mail | toimitus sähköpostitse |
| Kreditkarte | credit card | carte bancaire | carta di credito | tarjeta de crédito | creditcard | karta kredytowa | cartão de crédito | kreditkort | kreditkort | luottokortti |
| Widerrufsrecht | right of withdrawal | droit de rétractation | diritto di recesso | derecho de desistimiento | herroepingsrecht | prawo odstąpienia od umowy | direito de livre resolução | ångerrätt | fortrydelsesret | peruuttamisoikeus |

Brand and product names are never translated: KARINEX (always uppercase), Windows, Office,
Microsoft 365, Visual Studio, Apple Pay, Klarna, WhatsApp.

## QA

- `make check` must pass before every merge.
- Pseudo-localization: run the app with the scheme's Application Language set to "Double-Length
  Pseudolanguage" and "Right-to-Left Pseudolanguage" to catch truncation and hard-coded layout.
- Snapshot tests render every design-system component with Finnish sample text at
  `accessibilityExtraLarge` to catch overflow.
- Phase 2 exit criterion: a native speaker review for each language (PROMPT.md 14).
