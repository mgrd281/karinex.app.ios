// MARK: - Store data

/// Store data recorded from the live Storefront API on 2026-09-26 (Storefront API 2026-07, DE/DE,
/// collection "bestseller"). Titles are store content and rendered as-is in every language,
/// including their dashes (written as `\u{2013}` escapes). Prices are the `MoneyV2` amounts
/// formatted for the market; Finnish formatting of EUR amounts is identical ("29,90 €").
enum SnapshotStoreData {
    static let officeProPlusTitle = "Microsoft Office 2024 Professional Plus Download kaufen"
    static let officeProPlusPrice = "29,90 €"
    static let officeProPlusCompareAtPrice = "149,99 €"

    static let windowsProTitle = "Windows 11 Pro kaufen \u{2013} Dauerlizenz 1 PC, Download"
    static let windowsProPrice = "12,90 €"
    static let windowsProCompareAtPrice = "79,99 €"

    static let officeMacTitle = "Microsoft Office 2024 Standard für Mac Key \u{2013} Sofort Download"
    static let officeMacPrice = "13,90 €"
    static let officeMacCompareAtPrice = "39,99 €"

    /// The CH/FR market price of Office 2024 Professional Plus (no tax note outside the EU).
    static let officeProPlusPriceCHF = "CHF 29.00"

    /// An obviously fake license key; real keys never appear in code.
    static let placeholderLicenseKey = "XXXXX-00000-XXXXX-00000-XXXXX"
}

// MARK: - Caller copy

/// The already-localized strings a caller passes into the components, in the snapshot language.
///
/// German is the source language. Finnish is one of the longest app languages; its long compound
/// words ("Käyttöoikeusavain") stress wrapping at large text sizes. Service facts restate
/// PROMPT.md section 2 (delivery by e-mail, payment methods, support hours, refund condition).
/// Strings owned by the components themselves come from the DesignSystem String Catalog.
struct SnapshotCopy: Sendable {
    // MARK: Actions

    let browse: String
    let addToCart: String
    let guide: String
    let showAll: String

    // MARK: Prices

    let taxNote: String
    /// Savings derived from the recorded Windows 11 Pro price and compare-at price.
    let windowsProSavings: String

    // MARK: Badges

    let bestsellerBadge: String
    let saleBadge: String
    let digitalBadge: String
    let deliveredBadge: String

    // MARK: Section headers

    let sectionTitle: String
    let sectionEyebrow: String
    let processTitle: String
    let longSectionTitle: String
    let allProducts: String

    // MARK: Specifications

    let productLabel: String
    let licenseLabel: String
    let licenseValue: String
    let deliveryLabel: String
    let deliveryValue: String
    let licenseKeyLabel: String

    // MARK: Service facts

    let supportTitle: String
    let supportChannels: String
    let email: String
    let deliveryFact: String
    let paymentFact: String
    let refundFact: String
    let supportFact: String

    // MARK: Empty states

    let emptyCartTitle: String
    let emptyCartMessage: String
    let noResultsTitle: String
    let noResultsMessage: String

    // MARK: Banners

    let deliveryInfo: String
    let addedToCart: String

    // MARK: Timelines

    let orderStep: String
    let orderStepDetail: String
    let payStep: String
    let payStepDetail: String
    let keyStep: String
    let keyStepDetail: String
    let orderedState: String
    let paidState: String
    let licenseSentState: String

    // MARK: FAQ

    let keyQuestion: String
    let keyAnswer: String
    let paymentQuestion: String
    let paymentAnswer: String
    let supportQuestion: String
    let supportAnswer: String

    /// The copy for `language`.
    static func forLanguage(_ language: SnapshotLanguage) -> SnapshotCopy {
        switch language {
        case .de: german
        case .fi: finnish
        }
    }

    /// German, formal "Sie".
    static let german = SnapshotCopy(
        browse: "Zum Sortiment",
        addToCart: "In den Warenkorb",
        guide: "Anleitung",
        showAll: "Alle anzeigen",
        taxNote: "inkl. MwSt.",
        windowsProSavings: "Sie sparen 67,09 €",
        bestsellerBadge: "Bestseller",
        saleBadge: "Sale",
        digitalBadge: "Digital",
        deliveredBadge: "Zugestellt",
        sectionTitle: "Bestseller",
        sectionEyebrow: "Sortiment",
        processTitle: "So läuft es ab",
        longSectionTitle: "Lizenzschlüssel und Lieferung per E-Mail",
        allProducts: "Alle Produkte",
        productLabel: "Produkt",
        licenseLabel: "Lizenz",
        licenseValue: "Dauerlizenz, 1 PC",
        deliveryLabel: "Lieferung",
        deliveryValue: "Download",
        licenseKeyLabel: "Lizenzschlüssel",
        supportTitle: "Support",
        supportChannels: "WhatsApp, E-Mail und Live-Chat, Mo. bis So., 06:00 bis 23:00 Uhr",
        email: "E-Mail",
        deliveryFact: "Lieferung per E-Mail in Minuten",
        paymentFact: "Apple Pay, Kreditkarte, Klarna",
        refundFact: "100 Tage Geld-zurück",
        supportFact: "Support Mo. bis So., 06:00 bis 23:00 Uhr",
        emptyCartTitle: "Ihr Warenkorb ist leer",
        emptyCartMessage: "Legen Sie Produkte in den Warenkorb, um sie hier zu sehen.",
        noResultsTitle: "Keine Treffer",
        noResultsMessage: "Bitte versuchen Sie einen anderen Suchbegriff.",
        deliveryInfo: "Die Lieferung erfolgt per E-Mail.",
        addedToCart: "In den Warenkorb gelegt.",
        orderStep: "Bestellen",
        orderStepDetail: "Produkt in den Warenkorb legen",
        payStep: "Bezahlen",
        payStepDetail: "Apple Pay, Kreditkarte oder Klarna",
        keyStep: "Schlüssel per E-Mail",
        keyStepDetail: "In wenigen Minuten",
        orderedState: "Bestellt",
        paidState: "Bezahlt",
        licenseSentState: "Lizenz versendet",
        keyQuestion: "Wie erhalte ich meinen Lizenzschlüssel?",
        keyAnswer: "Nach der Zahlung erhalten Sie den Schlüssel und die Rechnung per E-Mail.",
        paymentQuestion: "Welche Zahlungsarten stehen zur Verfügung?",
        paymentAnswer: "Apple Pay, Kreditkarte und Klarna.",
        supportQuestion: "Wann ist der Support erreichbar?",
        supportAnswer: "Montag bis Sonntag, 06:00 bis 23:00 Uhr, per WhatsApp, E-Mail und Live-Chat."
    )

    /// Finnish, with long compound words.
    static let finnish = SnapshotCopy(
        browse: "Siirry valikoimaan",
        addToCart: "Lisää ostoskoriin",
        guide: "Käyttöohje",
        showAll: "Näytä kaikki",
        taxNote: "sis. ALV",
        windowsProSavings: "Säästät 67,09 €",
        bestsellerBadge: "Myydyin",
        saleBadge: "Ale",
        digitalBadge: "Digitaalinen",
        deliveredBadge: "Toimitettu",
        sectionTitle: "Myydyimmät tuotteet",
        sectionEyebrow: "Valikoima",
        processTitle: "Näin se toimii",
        longSectionTitle: "Käyttöoikeusavaimet ja toimitus sähköpostitse",
        allProducts: "Kaikki tuotteet",
        productLabel: "Tuote",
        licenseLabel: "Käyttöoikeus",
        licenseValue: "Pysyvä käyttöoikeus, 1 tietokone",
        deliveryLabel: "Toimitus",
        deliveryValue: "Lataus",
        licenseKeyLabel: "Käyttöoikeusavain",
        supportTitle: "Asiakastuki",
        supportChannels: "WhatsApp, sähköposti ja live-chat, maanantaista sunnuntaihin klo 6.00 ja 23.00 välillä",
        email: "Sähköposti",
        deliveryFact: "Toimitus sähköpostitse minuuteissa",
        paymentFact: "Apple Pay, luottokortti, Klarna",
        refundFact: "100 päivän rahat takaisin",
        supportFact: "Asiakastuki joka päivä klo 6.00 ja 23.00 välillä",
        emptyCartTitle: "Ostoskorisi on tyhjä",
        emptyCartMessage: "Lisää tuotteita ostoskoriin, niin näet ne täällä.",
        noResultsTitle: "Ei hakutuloksia",
        noResultsMessage: "Kokeile toista hakusanaa.",
        deliveryInfo: "Toimitus tapahtuu sähköpostitse.",
        addedToCart: "Lisätty ostoskoriin.",
        orderStep: "Tilaa",
        orderStepDetail: "Lisää tuote ostoskoriin",
        payStep: "Maksa",
        payStepDetail: "Apple Pay, luottokortti tai Klarna",
        keyStep: "Käyttöoikeusavain sähköpostitse",
        keyStepDetail: "Muutamassa minuutissa",
        orderedState: "Tilattu",
        paidState: "Maksettu",
        licenseSentState: "Lisenssi lähetetty",
        keyQuestion: "Miten saan käyttöoikeusavaimeni?",
        keyAnswer: "Maksun jälkeen saat avaimen ja laskun sähköpostitse.",
        paymentQuestion: "Mitä maksutapoja voin käyttää?",
        paymentAnswer: "Apple Pay, luottokortti ja Klarna.",
        supportQuestion: "Milloin asiakastuki on tavoitettavissa?",
        supportAnswer: "Maanantaista sunnuntaihin klo 6.00 ja 23.00 välillä WhatsAppin, sähköpostin ja live-chatin kautta."
    )
}
