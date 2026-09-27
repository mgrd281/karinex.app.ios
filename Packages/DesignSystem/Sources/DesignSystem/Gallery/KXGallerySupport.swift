#if DEBUG
import SwiftUI

// MARK: - Page

/// The scrolling page of one gallery topic: the topic summary followed by its demos, on the
/// page background, with the topic title in the navigation bar.
struct KXGalleryPage<Content: View>: View {
    private let topic: KXGalleryTopic
    private let content: Content

    /// Creates a page.
    ///
    /// - Parameters:
    ///   - topic: The topic whose title and summary the page shows.
    ///   - content: The demos, stacked vertically with generous spacing. Each demo applies the
    ///     screen gutter itself (see ``KXGalleryDemo``), so edge-to-edge content is possible.
    init(topic: KXGalleryTopic, @ViewBuilder content: () -> Content) {
        self.topic = topic
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                Text(verbatim: topic.summary)
                    .kxFont(.callout)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .kxGutter()
                content
            }
            .padding(.vertical, KXSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kxScreenBackground()
        .navigationTitle(Text(verbatim: topic.title))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("gallery.page.\(topic.rawValue)")
    }
}

// MARK: - Demo block

/// One labeled demo on a gallery page: an eyebrow title, an optional note and the content.
struct KXGalleryDemo<Content: View>: View {
    private let title: String
    private let note: String?
    private let isEdgeToEdge: Bool
    private let content: Content

    /// Creates a demo block.
    ///
    /// - Parameters:
    ///   - title: Short developer label, e.g. "Style .secondary".
    ///   - note: Optional explanation below the title.
    ///   - isEdgeToEdge: When `true` the content is not inset by the screen gutter (for
    ///     components that manage their own margins, such as the carousel).
    ///   - content: The demonstrated views.
    init(
        _ title: String,
        note: String? = nil,
        isEdgeToEdge: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.note = note
        self.isEdgeToEdge = isEdgeToEdge
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(verbatim: title)
                    .kxFont(.eyebrow)
                    .foregroundStyle(KXColor.accentText)
                    .accessibilityAddTraits(.isHeader)
                if let note {
                    Text(verbatim: note)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .kxGutter()
            content
                .padding(.horizontal, isEdgeToEdge ? 0 : KXSpacing.gutter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Event log

/// A single line that reports the last callback a demo received, so closures such as `onTap`,
/// `onExpire` or `onDismiss` can be verified by hand.
struct KXGalleryEventLabel: View {
    private let event: String?

    /// Creates the label.
    ///
    /// - Parameter event: Description of the last event, or `nil` before the first one.
    init(_ event: String?) {
        self.event = event
    }

    var body: some View {
        Label {
            Text(verbatim: event ?? "No callback received yet")
        } icon: {
            Image(systemName: event == nil ? "circle.dashed" : "checkmark.circle")
                .accessibilityHidden(true)
        }
        .kxFont(.footnote)
        .foregroundStyle(KXColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Sample data

/// Sample content for the gallery.
///
/// Product titles, prices and image URLs were recorded from the live Storefront API on
/// 2026-09-26 (Storefront API 2026-07, DE/DE, collection "bestseller"; the CHF title and price
/// from the CH/FR market). Titles are store content and rendered as-is, including their dashes,
/// which are written as `\u{2013}` escapes. Prices are the `MoneyV2` amounts formatted for the
/// market. The license key is an obviously fake placeholder; real keys never appear in code.
/// Service facts (delivery by e-mail, payment methods, support hours, refund condition) restate
/// PROMPT.md section 2.
enum KXGallerySamples {
    // MARK: Products

    static let officeProPlusTitle = "Microsoft Office 2024 Professional Plus Download kaufen"
    static let officeProPlusPrice = "29,90 €"
    static let officeProPlusCompareAtPrice = "149,99 €"
    static let officeProPlusImageURL = URL(
        string: "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Office_2024_Professional_Plus.webp"
    )

    static let windowsProTitle = "Windows 11 Pro kaufen \u{2013} Dauerlizenz 1 PC, Download"
    static let windowsProPrice = "12,90 €"
    static let windowsProCompareAtPrice = "79,99 €"
    static let windowsProImageURL = URL(
        string: "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Windows-11-Pro-Key-Download-kaufen..webp?v=1787442708"
    )

    static let officeMacTitle = "Microsoft Office 2024 Standard für Mac Key \u{2013} Sofort Download"
    static let officeMacPrice = "13,90 €"
    static let officeMacCompareAtPrice = "39,99 €"

    static let officeProPlusTitleCHFR = "Acheter Microsoft Office 2024 Professional Plus \u{2013} Téléchargement"
    static let officeProPlusPriceCHF = "CHF 29.00"

    /// Savings derived from the recorded Windows 11 Pro price and compare-at price
    /// (79,99 € minus 12,90 €).
    static let windowsProSavings = "Sie sparen 67,09 €"

    static let taxNote = "inkl. MwSt."

    // MARK: License

    static let placeholderLicenseKey = "XXXXX-00000-XXXXX-00000-XXXXX"

    // MARK: Service facts

    static let deliveryFact = "Lieferung per E-Mail in Minuten"
    static let paymentFact = "Apple Pay, Kreditkarte, Klarna"
    static let refundFact = "100 Tage Geld-zurück"
    static let supportFact = "Support Mo. bis So., 06:00 bis 23:00 Uhr deutscher Zeit"
    static let supportChannels = "WhatsApp, E-Mail und Live-Chat, Mo. bis So., 06:00 bis 23:00 Uhr deutscher Zeit"
    static let refundCondition = """
        Gilt nur für aktivierte Lizenzschlüssel und physische Ware. Zugestellte, nicht aktivierte \
        Schlüssel werden nicht freiwillig erstattet. Ihre gesetzlichen Gewährleistungsrechte \
        bleiben unberührt.
        """

    // MARK: Long words

    /// Finnish copy with long compound words, for wrapping checks.
    static let finnishLicenseKey = "Käyttöoikeusavain"
    static let finnishDelivery = "Toimitus sähköpostitse minuuteissa"

    /// The product cards of the product card page, in grid order.
    static let productCards: [KXProductCardModel] = [
        KXProductCardModel(
            id: "office-2024-professional-plus",
            title: officeProPlusTitle,
            price: officeProPlusPrice,
            compareAtPrice: officeProPlusCompareAtPrice,
            taxNote: taxNote,
            badge: "Bestseller",
            imageURL: officeProPlusImageURL
        ),
        KXProductCardModel(
            id: "windows-11-pro",
            title: windowsProTitle,
            price: windowsProPrice,
            compareAtPrice: windowsProCompareAtPrice,
            taxNote: taxNote,
            badge: "Sale",
            badgeTone: .urgency,
            imageURL: windowsProImageURL
        ),
    ]
}
#endif
