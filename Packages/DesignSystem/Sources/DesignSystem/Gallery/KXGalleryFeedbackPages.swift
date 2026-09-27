#if DEBUG
import SwiftUI

// MARK: - KXSkeleton

/// Skeleton placeholders, the redacting `kxSkeleton(isActive:)` modifier and the shimmer switch.
struct KXGallerySkeletonPage: View {
    @State private var isLoading = true
    @State private var isShimmerEnabled = true

    var body: some View {
        KXGalleryPage(topic: .skeleton) {
            KXGalleryDemo(
                "Settings",
                note: "Reduce Motion always removes the shimmer. Snapshot tests switch it off with .kxSkeletonShimmer(false)."
            ) {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    Toggle(isOn: $isLoading) {
                        Text(verbatim: "kxSkeleton(isActive:)")
                    }
                    Toggle(isOn: $isShimmerEnabled) {
                        Text(verbatim: "kxSkeletonShimmer(_:)")
                    }
                }
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .tint(KXColor.brand)
            }
            KXGalleryDemo("KXSkeleton blocks", note: "Placeholders for two product cards.") {
                HStack(alignment: .top, spacing: KXSpacing.m) {
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: KXSpacing.xs) {
                            KXSkeleton(cornerRadius: KXRadius.card, isAccessibilityElement: true)
                                .aspectRatio(1, contentMode: .fit)
                            KXSkeleton()
                                .frame(width: 64, height: 10)
                            KXSkeleton()
                                .frame(height: 16)
                            KXSkeleton()
                                .frame(width: 80, height: 20)
                        }
                    }
                }
            }
            KXGalleryDemo("kxSkeleton(isActive:)", note: "The real layout, redacted while loading.") {
                KXCard {
                    VStack(alignment: .leading, spacing: KXSpacing.s) {
                        Text(verbatim: KXGallerySamples.officeProPlusTitle)
                            .kxFont(.title3)
                            .foregroundStyle(KXColor.textPrimary)
                        KXPriceTag(
                            price: KXGallerySamples.officeProPlusPrice,
                            compareAtPrice: KXGallerySamples.officeProPlusCompareAtPrice,
                            taxNote: KXGallerySamples.taxNote
                        )
                        KXButton("In den Warenkorb", isFullWidth: true) {}
                    }
                }
                .kxSkeleton(isActive: isLoading)
            }
        }
        .kxSkeletonShimmer(isShimmerEnabled)
    }
}

// MARK: - KXEmptyState

/// Empty states with and without the primary action.
struct KXGalleryEmptyStatePage: View {
    @State private var actionCount = 0

    var body: some View {
        KXGalleryPage(topic: .emptyState) {
            KXGalleryDemo("With action", note: "The button appears only when actionTitle and action are both set.") {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    KXEmptyState(
                        systemImage: "bag",
                        title: "Ihr Warenkorb ist leer",
                        message: "Legen Sie Produkte in den Warenkorb, um sie hier zu sehen.",
                        actionTitle: "Zum Sortiment"
                    ) {
                        actionCount += 1
                    }
                    KXGalleryEventLabel(actionCount == 0 ? nil : "Actions received: \(actionCount)")
                }
            }
            KXGalleryDemo("Without action") {
                KXEmptyState(
                    systemImage: "magnifyingglass",
                    title: "Keine Treffer",
                    message: "Bitte versuchen Sie einen anderen Suchbegriff."
                )
            }
            KXGalleryDemo("Long words") {
                KXEmptyState(
                    systemImage: "key",
                    title: KXGallerySamples.finnishLicenseKey,
                    message: KXGallerySamples.finnishDelivery
                )
            }
        }
    }
}

// MARK: - KXBanner

/// Every banner style inline, and the `kxBanner(isPresented:banner:)` presenter.
struct KXGalleryBannerPage: View {
    @State private var isOfflineBannerPresented = false
    @State private var lastEvent: String?

    var body: some View {
        KXGalleryPage(topic: .banner) {
            KXGalleryDemo("Default messages", note: "Without a message each style uses its catalog text.") {
                VStack(spacing: KXSpacing.s) {
                    ForEach(KXBanner.Style.allCases, id: \.self) { style in
                        KXBanner(style)
                    }
                }
            }
            KXGalleryDemo("Action and close button") {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    KXBanner(.error) {
                        lastEvent = "Retry tapped"
                    }
                    KXBanner(.info, message: "Die Lieferung erfolgt per E-Mail.", onDismiss: {
                        lastEvent = "Dismiss tapped"
                    })
                    KXBanner(
                        .success,
                        message: "In den Warenkorb gelegt.",
                        actionTitle: "Zum Warenkorb",
                        action: { lastEvent = "Custom action tapped" },
                        onDismiss: { lastEvent = "Dismiss tapped" }
                    )
                    KXGalleryEventLabel(lastEvent)
                }
            }
            KXGalleryDemo(
                "Presenter",
                note: "kxBanner(isPresented:banner:) slides the banner in at the top of the modified view."
            ) {
                VStack(alignment: .leading, spacing: KXSpacing.s) {
                    KXButton(isOfflineBannerPresented ? "Hide offline banner" : "Show offline banner", style: .secondary) {
                        isOfflineBannerPresented.toggle()
                    }
                    KXColor.surface
                        .frame(height: 160)
                        .overlay {
                            Text(verbatim: "Screen content")
                                .kxFont(.footnote)
                                .foregroundStyle(KXColor.textSecondary)
                        }
                        .kxBanner(isPresented: isOfflineBannerPresented) {
                            KXBanner(.offline, onDismiss: {
                                isOfflineBannerPresented = false
                            })
                        }
                        .clipShape(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Feedback components, light") {
    NavigationStack {
        KXGallerySkeletonPage()
    }
}

#Preview("Feedback components, dark") {
    NavigationStack {
        KXGalleryBannerPage()
    }
    .preferredColorScheme(.dark)
}

#Preview("Feedback components, accessibility size") {
    NavigationStack {
        KXGalleryEmptyStatePage()
    }
    .dynamicTypeSize(.accessibility2)
}
#endif
