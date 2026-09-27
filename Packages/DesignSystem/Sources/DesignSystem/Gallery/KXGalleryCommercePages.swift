#if DEBUG
import SwiftUI

// MARK: - KXStepTimeline

/// Process explanations and a progress timeline that can be stepped through.
struct KXGalleryStepTimelinePage: View {
    /// Index of the current order step; equal to the step count when every step is done.
    @State private var currentOrderStep = 1

    /// "So läuft es ab", restating the purchase flow of PROMPT.md section 2.
    private let process = [
        KXStepTimeline.Step(title: "Bestellen", detail: "Produkt in den Warenkorb legen"),
        KXStepTimeline.Step(title: "Bezahlen", detail: "Apple Pay, Kreditkarte oder Klarna"),
        KXStepTimeline.Step(title: "Schlüssel per E-Mail", detail: "In wenigen Minuten"),
    ]

    private let orderTitles = ["Bestellt", "Bezahlt", "Lizenz versendet"]

    var body: some View {
        KXGalleryPage(topic: .stepTimeline) {
            KXGalleryDemo("Informational steps, horizontal", note: "state: nil, gold numerals. Vertical at accessibility sizes.") {
                KXStepTimeline(steps: process, direction: .horizontal)
            }
            KXGalleryDemo("Informational steps, vertical") {
                KXStepTimeline(steps: process)
            }
            KXGalleryDemo("Progress states", note: "done, current and upcoming. Step through to see the transitions.") {
                VStack(alignment: .leading, spacing: KXSpacing.l) {
                    KXStepTimeline(steps: orderSteps)
                    KXStepTimeline(steps: orderSteps, direction: .horizontal)
                    KXButton("Next state", systemImage: "forward.frame", style: .secondary, size: .compact) {
                        currentOrderStep = (currentOrderStep + 1) % (orderTitles.count + 1)
                    }
                }
            }
        }
    }

    /// The order steps for the current position: done before it, current at it, upcoming after.
    private var orderSteps: [KXStepTimeline.Step] {
        orderTitles.enumerated().map { index, title in
            let state: KXStepTimeline.Step.State = if index < currentOrderStep {
                .done
            } else if index == currentOrderStep {
                .current
            } else {
                .upcoming
            }
            return KXStepTimeline.Step(title: title, state: state)
        }
    }
}

// MARK: - KXAccordion

/// Single and multiple expansion, custom content and caller-owned expansion state.
struct KXGalleryAccordionPage: View {
    @State private var expandedIDs: Set<String> = []

    /// Questions and answers restating the business facts of PROMPT.md section 2.
    private let faq: [(question: String, answer: String)] = [
        (
            question: "Wie erhalte ich meinen Lizenzschlüssel?",
            answer: "Nach der Zahlung erhalten Sie den Schlüssel und die Rechnung per E-Mail."
        ),
        (
            question: "Welche Zahlungsarten stehen zur Verfügung?",
            answer: "Apple Pay, Kreditkarte und Klarna."
        ),
        (
            question: "Wann ist der Support erreichbar?",
            answer: "Montag bis Sonntag, 06:00 bis 23:00 Uhr deutscher Zeit, per WhatsApp, E-Mail und Live-Chat."
        ),
    ]

    var body: some View {
        KXGalleryPage(topic: .accordion) {
            KXGalleryDemo("Expansion .single", note: "The first row starts open; opening another row closes it.") {
                KXAccordion(items: faqItems, expansion: .single, initiallyExpanded: [faq[0].question])
            }
            KXGalleryDemo("Expansion .multiple, custom content") {
                KXAccordion(items: [
                    KXAccordionItem(title: KXGallerySamples.refundFact) {
                        VStack(alignment: .leading, spacing: KXSpacing.xs) {
                            Text(verbatim: KXGallerySamples.refundCondition)
                            KXBadge("Bedingung", style: .neutral, systemImage: "info.circle")
                        }
                    },
                    KXAccordionItem(title: "Support", text: KXGallerySamples.supportChannels),
                ])
            }
            KXGalleryDemo("Caller-owned state", note: "KXAccordion(items:expansion:expandedIDs:) with a binding.") {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    HStack(spacing: KXSpacing.s) {
                        KXButton("Expand all", style: .secondary, size: .compact) {
                            expandedIDs = Set(faq.map(\.question))
                        }
                        KXButton("Collapse all", style: .tertiary, size: .compact) {
                            expandedIDs = []
                        }
                    }
                    KXAccordion(items: faqItems, expandedIDs: $expandedIDs)
                    KXGalleryEventLabel("Open rows: \(expandedIDs.count)")
                }
            }
        }
    }

    private var faqItems: [KXAccordionItem] {
        faq.map { KXAccordionItem(title: $0.question, text: $0.answer) }
    }
}

// MARK: - KXCountdown

/// Live countdowns, the expiry callback and fixed frames for a reference date.
struct KXGalleryCountdownPage: View {
    /// Reference date of the fixed frames (2026-09-26, the day the samples were recorded).
    private static let referenceDate = Date(timeIntervalSinceReferenceDate: 812_160_000)

    /// The live samples count down to now plus 2 days and 3 hours (contract section 5).
    @State private var liveEnd = Date.now.addingTimeInterval(2 * 86_400 + 3 * 3_600)
    @State private var shortEnd = Date.now.addingTimeInterval(10)
    @State private var expiryCount = 0

    var body: some View {
        KXGalleryPage(topic: .countdown) {
            KXGalleryDemo("Live, style .ink", note: "Days are shown while 24 hours or more remain.") {
                KXCountdown(endsAt: liveEnd)
            }
            KXGalleryDemo("Live, style .brand, size .compact") {
                KXCountdown(endsAt: liveEnd, style: .brand, size: .compact)
            }
            KXGalleryDemo("onExpire", note: "A ten second countdown; the callback fires once at zero.") {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    KXCountdown(endsAt: shortEnd, size: .compact) {
                        expiryCount += 1
                    }
                    KXButton("Restart", systemImage: "arrow.counterclockwise", style: .secondary, size: .compact) {
                        shortEnd = Date.now.addingTimeInterval(10)
                    }
                    KXGalleryEventLabel(expiryCount == 0 ? nil : "onExpire received: \(expiryCount)")
                }
            }
            KXGalleryDemo("Fixed frame", note: "now: a reference date renders one static frame, as in snapshot tests.") {
                KXCountdown(endsAt: Self.referenceDate.addingTimeInterval(3 * 3_600 + 4 * 60 + 5), now: Self.referenceDate)
            }
            KXGalleryDemo("Ended") {
                KXCountdown(endsAt: Self.referenceDate, now: Self.referenceDate, size: .compact)
            }
        }
    }
}

// MARK: - KXTrustStrip

/// The four trust facts of the Start tab as a grid and as a carousel.
struct KXGalleryTrustStripPage: View {
    @State private var isConditionPresented = false

    var body: some View {
        KXGalleryPage(topic: .trustStrip) {
            KXGalleryDemo("Arrangement .grid", note: "The money-back item has a footnote marker and opens its condition.") {
                KXTrustStrip(items: items)
            }
            KXGalleryDemo("Arrangement .carousel", note: "Placed edge to edge; the strip applies the gutter itself.", isEdgeToEdge: true) {
                KXTrustStrip(items: items, arrangement: .carousel)
            }
            KXGalleryDemo("Odd item count") {
                KXTrustStrip(items: Array(items.prefix(3)))
            }
        }
        .sheet(isPresented: $isConditionPresented) {
            KXGalleryRefundConditionSheet()
                .presentationDetents([.medium])
        }
    }

    private var items: [KXTrustItem] {
        [
            KXTrustItem(systemImage: "envelope", text: KXGallerySamples.deliveryFact),
            KXTrustItem(systemImage: "creditcard", text: KXGallerySamples.paymentFact),
            KXTrustItem(systemImage: "arrow.uturn.backward", text: KXGallerySamples.refundFact, footnoteMarker: "*") {
                isConditionPresented = true
            },
            KXTrustItem(systemImage: "bubble.left.and.bubble.right", text: KXGallerySamples.supportFact),
        ]
    }
}

/// The refund condition presented from the money-back trust item.
private struct KXGalleryRefundConditionSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                KXSectionHeader(KXGallerySamples.refundFact)
                Text(verbatim: KXGallerySamples.refundCondition)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(KXSpacing.gutter)
            .padding(.top, KXSpacing.m)
        }
        .kxScreenBackground()
    }
}

// MARK: - KXProductCard

/// Product cards with remote, missing and local images, badges and the availability note.
struct KXGalleryProductCardPage: View {
    private let columns = [
        GridItem(.flexible(), spacing: KXSpacing.m, alignment: .top),
        GridItem(.flexible(), spacing: KXSpacing.m, alignment: .top),
    ]

    var body: some View {
        KXGalleryPage(topic: .productCard) {
            KXGalleryDemo("Remote images", note: "KXProductCard(model) loads the image with AsyncImage.") {
                LazyVGrid(columns: columns, spacing: KXSpacing.l) {
                    ForEach(KXGallerySamples.productCards) { model in
                        KXProductCard(model)
                    }
                }
            }
            KXGalleryDemo(
                "Missing and local images",
                note: "No URL shows the neutral fallback; the second card passes its own image view."
            ) {
                LazyVGrid(columns: columns, spacing: KXSpacing.l) {
                    KXProductCard(officeMacModel)
                    KXProductCard(officeMacModel) {
                        KXGalleryProductArtwork()
                    }
                }
            }
            KXGalleryDemo("availabilityNote", note: "State demo: the note is sample copy, not store data.") {
                LazyVGrid(columns: columns, spacing: KXSpacing.l) {
                    KXProductCard(unavailableModel)
                }
            }
            KXGalleryDemo("Inside a NavigationLink", note: "The card is not a button; the link supplies the trait.") {
                LazyVGrid(columns: columns, spacing: KXSpacing.l) {
                    NavigationLink {
                        KXGalleryPage(topic: .productCard) {
                            KXGalleryDemo("Destination") {
                                KXPriceTag(
                                    price: KXGallerySamples.windowsProPrice,
                                    compareAtPrice: KXGallerySamples.windowsProCompareAtPrice,
                                    taxNote: KXGallerySamples.taxNote
                                )
                            }
                        }
                    } label: {
                        KXProductCard(KXGallerySamples.productCards[1])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var officeMacModel: KXProductCardModel {
        KXProductCardModel(
            id: "office-2024-standard-mac",
            title: KXGallerySamples.officeMacTitle,
            price: KXGallerySamples.officeMacPrice,
            compareAtPrice: KXGallerySamples.officeMacCompareAtPrice,
            taxNote: KXGallerySamples.taxNote
        )
    }

    private var unavailableModel: KXProductCardModel {
        KXProductCardModel(
            id: "office-2024-professional-plus-ch",
            title: KXGallerySamples.officeProPlusTitleCHFR,
            price: KXGallerySamples.officeProPlusPriceCHF,
            imageURL: KXGallerySamples.officeProPlusImageURL,
            availabilityNote: "Derzeit nicht verfügbar"
        )
    }
}

/// A local stand-in for a product photo, built from shapes only.
private struct KXGalleryProductArtwork: View {
    var body: some View {
        ZStack {
            KXColor.brandSoft
            Circle()
                .strokeBorder(KXColor.accent, lineWidth: KXBorder.emphasis)
                .padding(KXSpacing.l)
            KXWordmark(size: .small, color: KXColor.textOnBrand)
                .padding(.horizontal, KXSpacing.xl)
        }
    }
}

// MARK: - KXKeyCard

/// The license card revealed with every action, masked without secondary actions, and with a
/// key that has no dashes.
struct KXGalleryKeyCardPage: View {
    @State private var isWindowsKeyRevealed = true
    @State private var isOfficeKeyRevealed = false
    @State private var isUngroupedKeyRevealed = true
    @State private var lastEvent: String?

    var body: some View {
        KXGalleryPage(topic: .keyCard) {
            KXGalleryDemo("Revealed, all actions", note: "Copy writes the fake key to the pasteboard, local only, for two minutes.") {
                KXKeyCard(
                    productName: KXGallerySamples.windowsProTitle,
                    licenseKey: KXGallerySamples.placeholderLicenseKey,
                    isRevealed: $isWindowsKeyRevealed,
                    subtitle: "Dauerlizenz, 1 PC",
                    onShowGuide: { lastEvent = "onShowGuide received" },
                    onContactSupport: { lastEvent = "onContactSupport received" }
                )
            }
            KXGalleryDemo("Masked, no secondary actions") {
                KXKeyCard(
                    productName: KXGallerySamples.officeProPlusTitle,
                    licenseKey: KXGallerySamples.placeholderLicenseKey,
                    isRevealed: $isOfficeKeyRevealed
                )
            }
            KXGalleryDemo("Key without dashes", note: "Grouped in chunks of five for display only.") {
                KXKeyCard(
                    productName: KXGallerySamples.officeMacTitle,
                    licenseKey: KXGallerySamples.placeholderLicenseKey.filter { $0 != "-" },
                    isRevealed: $isUngroupedKeyRevealed
                )
            }
            KXGalleryDemo("Callbacks") {
                KXGalleryEventLabel(lastEvent)
            }
        }
    }
}

// MARK: - Previews

#Preview("Commerce components, light") {
    NavigationStack {
        KXGalleryProductCardPage()
    }
}

#Preview("Commerce components, dark") {
    NavigationStack {
        KXGalleryKeyCardPage()
    }
    .preferredColorScheme(.dark)
}

#Preview("Commerce components, accessibility size") {
    NavigationStack {
        KXGalleryCountdownPage()
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
