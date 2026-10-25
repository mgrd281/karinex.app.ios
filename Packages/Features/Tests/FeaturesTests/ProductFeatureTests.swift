import CommerceUI
import Core
import Foundation
@testable import ProductFeature
import ShopifyKit
import Testing

// MARK: - View model: loading

@MainActor
@Suite("Product detail loading")
struct ProductDetailLoadingTests {
    private func makeModel(
        catalog: ProductStubCatalogRepository,
        cart: ProductStubCartRepository = ProductStubCartRepository()
    ) -> ProductDetailViewModel {
        let store = CartStore(repository: cart, store: InMemoryKeyValueStore(), appVersion: "0.1.0")
        return ProductDetailViewModel(handle: ProductFixtures.handle, catalog: catalog, cartStore: store)
    }

    @Test("A loaded product preselects its variant and hides empty metafield sections")
    func loadsTokenlessProduct() async throws {
        let catalog = ProductStubCatalogRepository(product: ProductFixtures.product())
        let model = makeModel(catalog: catalog)

        await model.load()

        let content = try #require(model.content)
        #expect(content.product.handle == ProductFixtures.handle)
        #expect(model.selectedVariant?.id == ShopifyID("gid://shopify/ProductVariant/1"))
        #expect(!model.showsVariantPicker)
        #expect(content.facts.isEmpty)
        #expect(content.faq.isEmpty)
        #expect(content.activation == nil)
        #expect(!content.description.isEmpty)
        #expect(content.images.count == 1)
        #expect(model.fulfillment == .digital)
        #expect(await catalog.requestedHandles == [ProductFixtures.handle])
    }

    @Test("The comparison row loads RELATED recommendations, without the product itself, at most six")
    func comparison() async {
        let recommendations = [ProductFixtures.summary(0, id: ProductFixtures.productID)]
            + (1...8).map { ProductFixtures.summary($0) }
            + [ProductFixtures.summary(1)]
        let catalog = ProductStubCatalogRepository(product: ProductFixtures.product(), recommendations: recommendations)
        let model = makeModel(catalog: catalog)

        await model.load()

        #expect(model.comparison.value?.map(\.handle) == (1...6).map { "product-\($0)" })
        let requests = await catalog.recommendationRequests
        #expect(requests.count == 1)
        #expect(requests.first?.productID == ProductFixtures.productID)
        #expect(requests.first?.intent == .related)
    }

    @Test("Without recommendations the comparison row is empty, which hides it")
    func emptyComparison() async {
        let catalog = ProductStubCatalogRepository(product: ProductFixtures.product(), recommendations: [])
        let model = makeModel(catalog: catalog)

        await model.load()

        #expect(model.comparison == .empty)
    }

    @Test("A failing comparison row never blocks the product")
    func comparisonFailure() async {
        let catalog = ProductStubCatalogRepository(product: ProductFixtures.product())
        await catalog.failNextRecommendations(with: ShopifyError.network(.offline))
        let model = makeModel(catalog: catalog)

        await model.load()

        #expect(model.content != nil)
        #expect(model.comparison.error?.kind == .offline)

        await model.loadComparison()
        #expect(model.comparison == .empty)
    }

    @Test("A product that does not exist in the market is the empty state")
    func notFound() async {
        let catalog = ProductStubCatalogRepository(product: nil)
        let model = makeModel(catalog: catalog)

        await model.load()

        #expect(model.state.isLoading == false)
        #expect(model.content == nil)
        #expect(model.state.error == nil)
        #expect(model.comparison == .empty)
        #expect(model.selectedVariant == nil)
    }

    @Test("A failed first load shows the error; retrying loads the product")
    func failureAndRetry() async {
        let catalog = ProductStubCatalogRepository(product: ProductFixtures.product())
        await catalog.failNextProduct(with: ShopifyError.network(.offline))
        let model = makeModel(catalog: catalog)

        await model.load()
        #expect(model.state.error?.kind == .offline)

        await model.load()
        #expect(model.content != nil)
        #expect(model.actionError == nil)
    }

    @Test("A failed reload keeps the product on screen and reports the failure in the banner")
    func failedReload() async {
        let catalog = ProductStubCatalogRepository(product: ProductFixtures.product())
        let model = makeModel(catalog: catalog)
        await model.load()

        await catalog.failNextProduct(with: ShopifyError.network(.timeout))
        await model.load()

        #expect(model.content != nil)
        #expect(model.actionError?.kind == .timeout)
    }
}

// MARK: - View model: variants and fulfillment

@MainActor
@Suite("Product variants and fulfillment")
struct ProductVariantTests {
    private func load(_ product: Product) async -> ProductDetailViewModel {
        let store = CartStore(repository: ProductStubCartRepository(), store: InMemoryKeyValueStore(), appVersion: "0.1.0")
        let model = ProductDetailViewModel(
            handle: product.handle,
            catalog: ProductStubCatalogRepository(product: product),
            cartStore: store
        )
        await model.load()
        return model
    }

    @Test("Variant chips appear only with more than one variant; the first available variant is preselected")
    func picker() async {
        let product = ProductFixtures.product(variants: [
            ProductFixtures.variant(1, title: "1 PC", availableForSale: false),
            ProductFixtures.variant(2, title: "3 PC"),
        ])
        let model = await load(product)

        #expect(model.showsVariantPicker)
        #expect(model.selectedVariant?.title == "3 PC")
        #expect(model.isPurchasable)

        model.selectVariant(ShopifyID("gid://shopify/ProductVariant/1"))
        #expect(model.selectedVariant?.title == "1 PC")
        #expect(!model.isPurchasable)

        model.selectVariant(ShopifyID("gid://shopify/ProductVariant/404"))
        #expect(model.selectedVariant?.title == "1 PC")
    }

    @Test("The selection survives a reload")
    func selectionSurvivesReload() async {
        let product = ProductFixtures.product(variants: [ProductFixtures.variant(1), ProductFixtures.variant(2)])
        let model = await load(product)

        model.selectVariant(ShopifyID("gid://shopify/ProductVariant/2"))
        await model.load()

        #expect(model.selectedVariantID == ShopifyID("gid://shopify/ProductVariant/2"))
    }

    @Test("Digital variants: order, pay, key by e-mail, and the right of withdrawal notice")
    func digital() async {
        let model = await load(ProductFixtures.product())

        #expect(model.fulfillment == .digital)
        #expect(model.fulfillment.steps == [.order, .pay, .emailDelivery])
        #expect(model.fulfillment.showsDigitalContentNotice)
    }

    @Test("Physical variants: order, pay, shipping, and no digital content notice")
    func physical() async {
        let model = await load(ProductFixtures.product(variants: [ProductFixtures.variant(1, requiresShipping: true)]))

        #expect(model.fulfillment == .physical)
        #expect(model.fulfillment.steps == [.order, .pay, .shipping])
        #expect(!model.fulfillment.showsDigitalContentNotice)
    }

    @Test("The gallery finds the image of a variant by URL")
    func variantImage() {
        let second = ShopifyImage(url: URL(fileURLWithPath: "/second.webp"))
        let product = ProductFixtures.product(images: [
            ShopifyImage(url: URL(fileURLWithPath: "/first.webp")),
            second,
        ])
        let content = ProductDetailContent(product: product)

        #expect(content.imageIndex(of: ShopifyImage(url: second.url)) == 1)
        #expect(content.imageIndex(of: ShopifyImage(url: URL(fileURLWithPath: "/other.webp"))) == nil)
        #expect(content.imageIndex(of: nil) == nil)
    }

    @Test("Without any image the gallery is empty and shows the placeholder")
    func galleryFallback() {
        let empty = ProductDetailContent(product: ProductFixtures.product(images: []))
        #expect(empty.images.isEmpty)
    }
}

// MARK: - View model: cart

@MainActor
@Suite("Product add to cart")
struct ProductCartTests {
    private struct Setup {
        let model: ProductDetailViewModel
        let store: CartStore
        let cart: ProductStubCartRepository
    }

    private func setUp(_ product: Product = ProductFixtures.product()) async -> Setup {
        let cart = ProductStubCartRepository()
        let store = CartStore(repository: cart, store: InMemoryKeyValueStore(), appVersion: "0.1.0")
        let model = ProductDetailViewModel(
            handle: product.handle,
            catalog: ProductStubCatalogRepository(product: product),
            cartStore: store
        )
        await model.load()
        return Setup(model: model, store: store, cart: cart)
    }

    @Test("In den Warenkorb adds the selected variant once and shows a confirmation")
    func add() async {
        let setup = await setUp()

        let added = await setup.model.addToCart()

        #expect(added)
        #expect(await setup.cart.addedVariantIDs == [ShopifyID("gid://shopify/ProductVariant/1")])
        #expect(await setup.cart.createCount == 1)
        #expect(setup.store.itemCount == 1)
        #expect(setup.model.confirmation?.id == 1)
        #expect(setup.model.successfulAddCount == 1)
        #expect(!setup.model.isAddingToCart)
        #expect(setup.model.actionError == nil)
    }

    @Test("Each add is its own confirmation; dismissing an older one keeps the newer one")
    func confirmations() async {
        let setup = await setUp()

        await setup.model.addToCart()
        await setup.model.addToCart()

        #expect(setup.model.confirmation?.id == 2)
        setup.model.dismissConfirmation(1)
        #expect(setup.model.confirmation?.id == 2)
        setup.model.dismissConfirmation(2)
        #expect(setup.model.confirmation == nil)
        #expect(setup.store.itemCount == 2)
    }

    @Test("A failed add explains why and shows no confirmation")
    func failure() async {
        let setup = await setUp()
        await setup.cart.failNextAdd(with: ShopifyError.network(.offline))

        let added = await setup.model.addToCart()

        #expect(!added)
        #expect(setup.model.confirmation == nil)
        #expect(setup.model.successfulAddCount == 0)
        #expect(setup.model.actionError?.kind == .offline)
        #expect(setup.store.itemCount == 0)
    }

    @Test("Jetzt kaufen adds the variant without the confirmation, so the checkout can open")
    func buyNow() async {
        let setup = await setUp()

        let added = await setup.model.buyNow()

        #expect(added)
        #expect(setup.model.confirmation == nil)
        #expect(setup.model.successfulAddCount == 1)
        #expect(await setup.cart.addedVariantIDs.count == 1)
    }

    @Test("An unavailable variant is never added")
    func unavailable() async {
        let setup = await setUp(ProductFixtures.product(variants: [ProductFixtures.variant(1, availableForSale: false)]))

        #expect(await setup.model.addToCart() == false)
        #expect(await setup.model.buyNow() == false)
        #expect(await setup.cart.addedVariantIDs.isEmpty)
        #expect(setup.model.actionError == nil)
    }

    @Test("Nothing is added before the product has loaded")
    func notLoaded() async {
        let cart = ProductStubCartRepository()
        let store = CartStore(repository: cart, store: InMemoryKeyValueStore(), appVersion: "0.1.0")
        let model = ProductDetailViewModel(
            handle: ProductFixtures.handle,
            catalog: ProductStubCatalogRepository(product: nil),
            cartStore: store
        )

        #expect(await model.addToCart() == false)
        #expect(await cart.addedVariantIDs.isEmpty)
    }
}

// MARK: - Content from metafields

@Suite("Product content from metafields")
struct ProductMetafieldContentTests {
    @Test("Key facts follow the order of PROMPT.md 6.3 and show the store's values")
    func facts() {
        let metafields = [
            Metafield(namespace: "custom", key: "mpn", type: "single_line_text_field", value: "79P-00001"),
            Metafield(namespace: "karinex", key: "sprachen", type: "list.single_line_text_field", value: #"["Deutsch","Englisch"]"#),
            Metafield(namespace: "karinex", key: "lizenztyp", type: "single_line_text_field", value: "Dauerlizenz"),
            Metafield(namespace: "karinex", key: "architektur", type: "single_line_text_field", value: "  "),
        ]
        let content = ProductDetailContent(product: ProductFixtures.product(metafields: metafields))

        #expect(content.facts.map(\.kind) == [.licenseType, .languages, .mpn])
        #expect(content.facts.map(\.value) == ["Dauerlizenz", "Deutsch, Englisch", "79P-00001"])
    }

    @Test("Without metafields there are no facts, so the table is hidden")
    func noFacts() {
        #expect(ProductFact.facts(from: ProductMetafields([])).isEmpty)
    }

    @Test("The FAQ comes from karinex.faq; answers may be HTML")
    func faq() throws {
        let json = #"[{"question":"Wie erhalte ich den Schlüssel?","answer":"<p>Per <strong>E-Mail</strong>.</p>"},"#
            + #"{"question":"Leer","answer":"   "}]"#
        let content = ProductDetailContent(product: ProductFixtures.product(metafields: [
            Metafield(namespace: "karinex", key: "faq", type: "json", value: json),
        ]))

        let item = try #require(content.faq.first)
        #expect(content.faq.count == 1)
        #expect(item.question == "Wie erhalte ich den Schlüssel?")
        #expect(!item.answer.isEmpty)
    }

    @Test("The activation section renders custom.details_content rich text")
    func activation() throws {
        let richText = #"{"type":"root","children":[{"type":"heading","level":3,"children":[{"type":"text","value":"Aktivierung"}]},"#
            + #"{"type":"paragraph","children":[{"type":"text","value":"Datei > Konto","bold":true}]}]}"#
        let content = ProductDetailContent(product: ProductFixtures.product(metafields: [
            Metafield(namespace: "custom", key: "details_content", type: "rich_text_field", value: richText),
        ]))

        let activation = try #require(content.activation)
        #expect(activation.blocks == [
            .heading(level: 3, inlines: [.text("Aktivierung")]),
            .paragraph([.strong([.text("Datei > Konto")])]),
        ])
    }
}

// MARK: - Rich text conversion

@Suite("Product rich text")
struct ProductRichTextTests {
    @Test("Lists, links and inline text become blocks; only web links stay links")
    func conversion() throws {
        let web = try #require(URL(string: "https://www.karinex.de/blogs/guides"))
        let nodes = [
            RichTextNode(type: "list", listType: "ordered", children: [
                RichTextNode(type: "list-item", children: [RichTextNode(type: "text", value: "Office öffnen")]),
                RichTextNode(type: "list-item", children: [
                    RichTextNode(type: "link", url: web.absoluteString, children: [RichTextNode(type: "text", value: "Anleitung")]),
                ]),
            ]),
            RichTextNode(type: "paragraph", children: [
                RichTextNode(type: "link", url: "mailto:kundenservice@karinex.de", children: [
                    RichTextNode(type: "text", value: "E-Mail", italic: true),
                ]),
            ]),
            RichTextNode(type: "paragraph", children: [RichTextNode(type: "text", value: "   ")]),
        ]

        #expect(ProductRichText.blocks(nodes) == [
            .list(ordered: true, items: [
                [.paragraph([.text("Office öffnen")])],
                [.paragraph([.link(url: web, [.text("Anleitung")])])],
            ]),
            .paragraph([.emphasis([.text("E-Mail")])]),
        ])
    }

    @Test("Plain text becomes one paragraph per line; blank text is no document")
    func plainText() {
        let document = ProductRichText.document(for: .plainText("Erste Zeile\n\nZweite Zeile"), baseURL: nil)
        #expect(document?.blocks == [.paragraph([.text("Erste Zeile")]), .paragraph([.text("Zweite Zeile")])])
        #expect(ProductRichText.document(for: .plainText(" \n "), baseURL: nil) == nil)
    }

    @Test("Only http and https count as web links")
    func webURLs() {
        #expect(ProductRichText.webURL("https://www.karinex.de") != nil)
        #expect(ProductRichText.webURL("HTTP://karinex.de") != nil)
        #expect(ProductRichText.webURL("mailto:kundenservice@karinex.de") == nil)
        #expect(ProductRichText.webURL("javascript:alert(1)") == nil)
        #expect(ProductRichText.webURL(nil) == nil)
    }
}

// MARK: - Strings

@Suite("Product strings")
struct ProductStringTests {
    /// Every key of the ProductFeature catalog.
    static let keys = [
        "product.share", "product.loading", "product.empty.title", "product.empty.message",
        "product.gallery.image", "product.gallery.open.hint", "product.gallery.zoom.hint", "product.gallery.close",
        "product.availability.available", "product.availability.unavailable",
        "product.delivery.digital", "product.delivery.physical", "product.variant.title",
        "product.facts.title", "product.facts.license_type", "product.facts.architecture", "product.facts.device_count",
        "product.facts.delivery_form", "product.facts.activation_method", "product.facts.languages",
        "product.facts.support_status", "product.facts.mpn",
        "product.process.title", "product.process.order.title", "product.process.order.detail",
        "product.process.pay.title", "product.process.pay.detail", "product.process.email.title",
        "product.process.email.detail", "product.process.shipping.title", "product.process.shipping.detail",
        "product.description.title", "product.activation.title", "product.comparison.title", "product.comparison.eyebrow",
        "product.faq.title", "product.refund.title", "product.refund.scope", "product.refund.unactivated",
        "product.refund.statutory", "product.notice.title", "product.notice.digital",
        "product.cart.add", "product.cart.buy_now", "product.cart.added", "product.cart.show",
        "product.gallery.position %lld %lld",
    ]

    @Test("Every product text exists in German and English, without dashes", arguments: ["de", "en"])
    func complete(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: ProductFeatureResources.bundle)
        for key in Self.keys {
            let value = strings(key)
            #expect(value != key, "\(key) is missing in \(language)")
            #expect(!value.isEmpty)
            #expect(!containsForbiddenDash(value), "\(key) contains a dash in \(language)")
        }
    }

    @Test("The buttons read In den Warenkorb, Jetzt kaufen and Zum Warenkorb")
    func buttons() throws {
        let german = try LocalizedStrings(language: "de", in: ProductFeatureResources.bundle)
        #expect(german("product.cart.add") == "In den Warenkorb")
        #expect(german("product.cart.buy_now") == "Jetzt kaufen")
        #expect(german("product.cart.show") == "Zum Warenkorb")
        #expect(german("product.process.title") == "So läuft es ab")
    }

    @Test("The timeline names Bestellen, Bezahlen and the key by e-mail, or shipping for physical goods")
    func timeline() throws {
        let german = try LocalizedStrings(language: "de", in: ProductFeatureResources.bundle)
        #expect(ProductFulfillment.digital.steps.map { $0.title(in: german.bundle) } == ["Bestellen", "Bezahlen", "Schlüssel per E-Mail"])
        #expect(ProductFulfillment.physical.steps.map { $0.title(in: german.bundle) } == ["Bestellen", "Bezahlen", "Versand"])
        #expect(ProductProcessStep.emailDelivery.detail(in: german.bundle).contains("Minuten"))
        #expect(ProductProcessStep.pay.detail(in: german.bundle) == "Mit Apple Pay, Kreditkarte oder Klarna.")
    }

    @Test("The refund conditions state the business rule next to the promise")
    func refundConditions() throws {
        let german = try LocalizedStrings(language: "de", in: ProductFeatureResources.bundle)
        let clauses = ProductRefundClause.allCases.map { $0.text(in: german.bundle) }

        #expect(german("product.refund.title") == "100 Tage Geld-zurück")
        #expect(clauses[0].contains("nur für aktivierte Lizenzschlüssel und für physische Ware"))
        #expect(clauses[1].contains("nicht aktivierte Lizenzschlüssel werden nicht freiwillig erstattet"))
        #expect(clauses[2].contains("gesetzlichen Gewährleistungsrechte"))
        #expect(clauses[2].contains("unberührt"))
    }

    @Test("The German digital-content notice cites § 356 Abs. 5 BGB; English describes the rule without it")
    func digitalNotice() throws {
        let german = try LocalizedStrings(language: "de", in: ProductFeatureResources.bundle)
        let english = try LocalizedStrings(language: "en", in: ProductFeatureResources.bundle)

        #expect(german("product.notice.digital").contains("§ 356 Abs. 5 BGB"))
        #expect(german("product.notice.digital").contains("Widerrufsrecht"))
        #expect(english("product.notice.digital").contains("right of withdrawal"))
        #expect(!english("product.notice.digital").contains("BGB"))
    }

    @Test("Fact labels exist for every fact kind")
    func factLabels() throws {
        let german = try LocalizedStrings(language: "de", in: ProductFeatureResources.bundle)
        #expect(ProductFact.Kind.allCases.map { $0.label(in: german.bundle) } == [
            "Lizenztyp", "Architektur", "Geräteanzahl", "Lieferform", "Aktivierungsart", "Sprachen", "Support-Status",
            "Herstellernummer (MPN)",
        ])
    }

    @Test("No product text names other payment methods or makes license claims", arguments: ["de", "en"])
    func noClaims(language: String) throws {
        let strings = try LocalizedStrings(language: language, in: ProductFeatureResources.bundle)
        for key in Self.keys {
            let value = strings(key).lowercased()
            #expect(!value.contains("original"))
            #expect(!value.contains("legal"))
            #expect(!value.contains("geprüft"))
            #expect(!value.contains("bewertung"))
        }
    }
}
