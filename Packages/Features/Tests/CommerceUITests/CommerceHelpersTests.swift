@testable import CommerceUI
import DesignTokens
import Foundation
import ShopifyKit
import SwiftUI
import Testing

@Suite("CommerceUI helpers")
struct CommerceHelpersTests {
    // MARK: LoadState

    @Test("LoadState: empty values, accessors and map")
    func loadState() {
        #expect(LoadState<[Int]>(collection: []) == .empty)
        #expect(LoadState(collection: [1, 2]) == .loaded([1, 2]))
        #expect(LoadState<Int>(nil) == .empty)
        #expect(LoadState(3, isEmpty: { $0 == 0 }) == .loaded(3))
        #expect(LoadState(0, isEmpty: { $0 == 0 }) == .empty)

        let failed = LoadState<Int>.failed(UserFacingError(kind: .server))
        #expect(failed.error?.kind == .server)
        #expect(failed.value == nil)
        #expect(LoadState<Int>.idle.isLoading)
        #expect(LoadState<Int>.loading.isLoading)
        #expect(!LoadState.loaded(1).isLoading)
        #expect(LoadState.loaded(2).map { $0 * 2 } == .loaded(4))
        #expect(LoadState<Int>.loading.map { $0 * 2 } == .loading)
    }

    // MARK: Images

    @Test("CDN widths: rendered width times scale, rounded up to the step, clamped", arguments: [
        (164.0, 3.0, 600),
        (164.0, 2.0, 360),
        (120.0, 1.0, 120),
        (0.0, 2.0, 120),
        (1000.0, 3.0, 2048),
        (CGFloat.infinity, 2.0, 2048),
    ])
    func pixelWidth(points: CGFloat, scale: CGFloat, expected: Int) {
        #expect(KXImagePipeline.pixelWidth(pointWidth: points, scale: scale) == expected)
    }

    @Test("Image requests carry the WebP Accept header and the CDN width")
    func imageRequest() throws {
        let image = try ShopifyImage(
            url: #require(URL(string: "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Windows-11-Pro.webp?v=1787442708"))
        )
        let request = KXImagePipeline.request(for: image, pointWidth: 164, scale: 3)
        let urlRequest = try #require(request.urlRequest)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == ShopifyImage.acceptHeader)
        let components = try #require(urlRequest.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(components.queryItems?.first { $0.name == "width" }?.value == "600")
        #expect(components.queryItems?.first { $0.name == "v" }?.value == "1787442708")
    }

    @Test("Only Shopify CDN URLs get a width parameter")
    func cdnDetection() throws {
        #expect(try KXImagePipeline.isShopifyCDN(#require(URL(string: "https://cdn.shopify.com/s/files/a.webp"))))
        #expect(try KXImagePipeline.isShopifyCDN(#require(URL(string: "https://www.karinex.de/cdn/shop/files/a.webp"))))
        let other = try #require(URL(string: "https://example.com/a.png"))
        #expect(!KXImagePipeline.isShopifyCDN(other))
        #expect(KXImagePipeline.request(for: other, pixelWidth: 600).urlRequest?.url == other)
    }

    // MARK: Rich text

    @Test("Only web links become tappable in rich text")
    func richTextLinks() throws {
        let web = try #require(URL(string: "https://www.karinex.de/blogs/guides"))
        let mail = try #require(URL(string: "mailto:kundenservice@karinex.de"))
        let string = RichTextStyle.attributedString(for: [
            .text("Siehe "),
            .link(url: web, [.text("Ratgeber")]),
            .text(" oder "),
            .link(url: mail, [.text("E-Mail")]),
        ])
        let links = string.runs.compactMap(\.link)
        #expect(links == [web])
        #expect(String(string.characters) == "Siehe Ratgeber oder E-Mail")
        #expect(string.runs.allSatisfy { $0.underlineStyle == nil })
        #expect(string.runs.contains { $0.link == web && $0.inlinePresentationIntent == .stronglyEmphasized })
    }

    @Test("Rich text keeps bold, italic and code as presentation intents")
    func richTextIntents() {
        let string = RichTextStyle.attributedString(for: [
            .strong([.text("fett "), .emphasis([.text("kursiv")])]),
            .code("KEY"),
            .lineBreak,
        ])
        let intents = string.runs.map(\.inlinePresentationIntent)
        #expect(intents.contains(.stronglyEmphasized))
        #expect(intents.contains([.stronglyEmphasized, .emphasized]))
        #expect(intents.contains(.code))
        #expect(String(string.characters) == "fett kursivKEY\n")
    }

    @Test("Blank paragraphs and heading levels")
    func richTextStyleRules() {
        #expect(RichTextStyle.isBlank([.text("  "), .lineBreak]))
        #expect(!RichTextStyle.isBlank([.strong([.text("Hinweis")])]))
        #expect(RichTextStyle.headingStyle(level: 1) == .title2)
        #expect(RichTextStyle.headingStyle(level: 3) == .title3)
        #expect(RichTextStyle.headingStyle(level: 5) == .headline)
    }
}

// MARK: - Cart bag

@Suite("Cart bag icon")
struct CartBagIconTests {
    @Test("The figure beside the bag is the count up to 99, then 99+, and nothing for an empty cart")
    func figure() {
        #expect(CartBagIcon.figure(for: 0).isEmpty)
        #expect(CartBagIcon.figure(for: -1).isEmpty)
        #expect(CartBagIcon.figure(for: 1) == "1")
        #expect(CartBagIcon.figure(for: 99) == "99")
        #expect(CartBagIcon.figure(for: 100) == "99+")
    }

    @MainActor
    @Test("The bag's outline fills its grid and keeps its proportions in any rect")
    func shape() {
        let size = CartBagShape.designSize
        let fitted = CartBagShape().path(in: CGRect(origin: .zero, size: size)).boundingRect
        #expect(abs(fitted.minX) < 0.05)
        #expect(abs(fitted.minY) < 0.05)
        #expect(abs(fitted.maxX - size.width) < 0.05)
        #expect(abs(fitted.maxY - size.height) < 0.05)

        let wide = CartBagShape().path(in: CGRect(x: 0, y: 0, width: 60, height: 44)).boundingRect
        #expect(abs(wide.height - 44) < 0.1)
        #expect(abs(wide.width - 44 * CartBagShape.aspectRatio) < 0.1)
        #expect(abs(wide.midX - 30) < 0.1)
    }
}

// MARK: - Product row cards

@Suite("Product row card sizes")
struct ProductRowCardSizeTests {
    @Test("Regular cards are 164 points wide with square photos, large ones 184 with portrait photos")
    func sizes() {
        #expect(ProductRowCardSize.regular.width(textScale: 1) == 164)
        #expect(ProductRowCardSize.regular.imageAspectRatio == 1)
        #expect(ProductRowCardSize.large.width(textScale: 1) == 184)
        #expect(ProductRowCardSize.large.imageAspectRatio == 0.75)
    }

    @Test("A large card's photo is half again as tall as a regular one")
    func largePhotoHeight() {
        let regular = ProductRowCardSize.regular.width(textScale: 1) / ProductRowCardSize.regular.imageAspectRatio
        let large = ProductRowCardSize.large.width(textScale: 1) / ProductRowCardSize.large.imageAspectRatio
        #expect(regular == 164)
        #expect((245...246).contains(large))
    }

    @Test("Cards grow with the text size up to their widest")
    func dynamicType() {
        for size in ProductRowCardSize.allCases {
            #expect(size.width(textScale: 1.2) > size.width(textScale: 1))
            #expect(size.width(textScale: 10) == size.maximumWidth)
        }
        #expect(ProductRowCardSize.large.maximumWidth > ProductRowCardSize.regular.maximumWidth)
    }
}
