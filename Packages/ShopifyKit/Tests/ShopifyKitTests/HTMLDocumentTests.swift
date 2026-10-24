import Foundation
@testable import ShopifyKit
import Testing

// MARK: - Helpers

/// The visible text of inlines, with `\n` for line breaks.
private func text(_ inlines: [HTMLInline]) -> String {
    inlines.map { inline in
        switch inline {
        case let .text(value), let .code(value): value
        case let .strong(children), let .emphasis(children), let .link(_, children): text(children)
        case .lineBreak: "\n"
        }
    }.joined()
}

/// The visible text of blocks, one block per line.
private func text(_ blocks: [HTMLBlock]) -> String {
    blocks.map { block in
        switch block {
        case let .heading(_, inlines), let .paragraph(inlines): text(inlines)
        case let .list(_, items): items.map(text).joined(separator: "\n")
        case let .table(rows): rows.map { $0.map { text($0.inlines) }.joined(separator: " | ") }.joined(separator: "\n")
        case let .quote(children): text(children)
        case let .image(_, alt): alt ?? ""
        case .rule: "---"
        }
    }.joined(separator: "\n")
}

/// Every link of the blocks with its visible text.
private func links(_ blocks: [HTMLBlock]) -> [(url: URL, text: String)] {
    func inlineLinks(_ inlines: [HTMLInline]) -> [(url: URL, text: String)] {
        inlines.flatMap { inline -> [(url: URL, text: String)] in
            switch inline {
            case let .link(url, children): [(url, text(children))] + inlineLinks(children)
            case let .strong(children), let .emphasis(children): inlineLinks(children)
            case .text, .code, .lineBreak: []
            }
        }
    }
    return blocks.flatMap { block -> [(url: URL, text: String)] in
        switch block {
        case let .heading(_, inlines), let .paragraph(inlines): inlineLinks(inlines)
        case let .list(_, items): items.flatMap(links)
        case let .table(rows): rows.flatMap { $0.flatMap { inlineLinks($0.inlines) } }
        case let .quote(children): links(children)
        case .image, .rule: []
        }
    }
}

/// Every block, including those nested in lists and quotes.
private func allBlocks(_ blocks: [HTMLBlock]) -> [HTMLBlock] {
    blocks.flatMap { block -> [HTMLBlock] in
        switch block {
        case let .list(_, items): [block] + items.flatMap(allBlocks)
        case let .quote(children): [block] + allBlocks(children)
        default: [block]
        }
    }
}

private func matches(_ pattern: String, in text: String) -> [[String]] {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.matches(in: text, range: range).map { match in
        (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
    }
}

// MARK: - Recorded store content

@Suite("HTMLDocument with recorded store content")
struct HTMLDocumentFixtureTests {
    static let productFixtures = [Fixture.productDE, Fixture.productCHFR]

    private func description(_ name: String) throws -> (html: String, baseURL: URL?) {
        let product = try #require(try Fixture.decode(ProductByHandleQuery.ResponseData.self, from: name).product)
        return (product.descriptionHtml, product.onlineStoreUrl)
    }

    private func articleHTML() throws -> String {
        try #require(try Fixture.decode(ArticleQuery.ResponseData.self, from: Fixture.articleGuide).blog?.articleByHandle?.contentHtml)
    }

    @Test("Office 2024 description: headings, list and paragraphs without markup", arguments: productFixtures)
    func officeDescription(name: String) throws {
        let (html, baseURL) = try description(name)
        let document = HTMLDocument(html: html, baseURL: baseURL)
        let blocks = allBlocks(document.blocks)

        let headings = blocks.compactMap { block -> (Int, String)? in
            if case let .heading(level, inlines) = block { return (level, text(inlines)) }
            return nil
        }
        #expect(headings.count == matches(#"<h[1-6][\s>]"#, in: html).count)
        #expect(headings.first?.0 == 1)
        #expect(headings.first?.1.contains("Office 2024 Professional Plus") == true)
        #expect(Set(headings.map(\.0)) == [1, 2, 3])

        let lists = blocks.compactMap { block -> [[HTMLBlock]]? in
            if case let .list(false, items) = block { return items }
            return nil
        }
        #expect(lists.count == 1)
        #expect(lists.first?.count == 3)

        let plain = text(document.blocks)
        #expect(!plain.contains("<"))
        #expect(!plain.contains("style="))
        #expect(!plain.contains("&amp;"))
        #expect(!plain.contains("  "))
        #expect(plain.contains("Microsoft Office 2024 Professional Plus"))
        if name == Fixture.productDE {
            #expect(plain.contains("Dauerlizenz (LTSC)"))
        }
        #expect(document == HTMLDocument(html: html, baseURL: baseURL))
    }

    @Test("Links: only http(s); relative ones resolved; other schemes become plain text", arguments: productFixtures)
    func officeLinks(name: String) throws {
        let (html, baseURL) = try description(name)
        let document = HTMLDocument(html: html, baseURL: baseURL)
        let found = links(document.blocks)
        #expect(found.allSatisfy { $0.url.scheme == "https" || $0.url.scheme == "http" })
        #expect(found.allSatisfy { $0.url.host != nil })
        #expect(found.contains { $0.url.absoluteString == "https://www.karinex.de/collections/microsoft-office" })

        // The store links a support channel with a URL scheme that would start an action on
        // the device. It must stay visible as text, without a link.
        let anchors = matches(#"<a\s[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#, in: html)
        let actionAnchors = anchors.filter { anchor in
            let href = anchor[1].lowercased()
            return !(href.hasPrefix("http://") || href.hasPrefix("https://") || href.hasPrefix("/"))
        }
        #expect(!actionAnchors.isEmpty)
        #expect(found.count == anchors.count - actionAnchors.count)
        let plain = text(document.blocks)
        for anchor in actionAnchors {
            let label = anchor[2].replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!label.isEmpty)
            #expect(plain.contains(label))
            #expect(!found.contains { $0.text.contains(label) })
        }
    }

    @Test("Without a base URL relative links stay relative")
    func relativeLinksWithoutBase() throws {
        let (html, _) = try description(Fixture.productDE)
        let found = links(HTMLDocument(html: html).blocks)
        #expect(found.contains { $0.url.absoluteString == "/collections/microsoft-office" && $0.url.scheme == nil })
        #expect(found.allSatisfy { $0.url.scheme == nil || $0.url.scheme == "https" })
    }

    @Test("Guide article: style and script dropped, image, tables with header row, inline code")
    func article() throws {
        let html = try articleHTML()
        let document = HTMLDocument(
            html: html,
            baseURL: URL(string: "https://www.karinex.de/blogs/guides/windows-11-kompatibilitaet-pruefen")
        )
        let plain = text(document.blocks)
        #expect(html.contains("<style"))
        #expect(html.contains("<script"))
        #expect(!plain.contains("kx-editorial"))
        #expect(!plain.contains("schema.org"))
        #expect(!plain.contains("{"))

        guard case let .image(url, alt)? = document.blocks.first(where: { if case .image = $0 { true } else { false } }) else {
            Issue.record("no image")
            return
        }
        #expect(url.host == "cdn.shopify.com")
        #expect(alt?.isEmpty == false)

        let tables = document.blocks.compactMap { block -> [[HTMLTableCell]]? in
            if case let .table(rows) = block { return rows }
            return nil
        }
        #expect(tables.count == matches("<table", in: html).count)
        let requirements = try #require(tables.first)
        #expect(requirements.count == 9)
        #expect(requirements.allSatisfy { $0.count == 3 })
        let headerFlags = requirements[0].map(\.isHeader)
        #expect(headerFlags == [true, true, true])
        #expect(requirements[0].map { text($0.inlines) } == ["Bauteil", "Microsoft-Minimum", "So prüfen Sie es"])
        #expect(requirements.dropFirst().allSatisfy { row in row.allSatisfy { !$0.isHeader } })
        #expect(text(requirements[1][0].inlines) == "Prozessor")
        #expect(requirements.contains { row in row.contains { $0.inlines.first == .code("msinfo32") } })

        let headings = document.blocks.filter { if case .heading = $0 { true } else { false } }
        #expect(headings.contains(.heading(level: 2, inlines: [.text("Wie prüfe ich TPM 2.0 und Secure Boot manuell?")])))
        #expect(document.blocks.contains { block in
            if case let .paragraph(inlines) = block {
                return inlines.contains(.code("tpm.msc")) && inlines.contains(.strong([.text("Windows-Taste + R")]))
            }
            return false
        })
    }

    @Test("Truncated store HTML never crashes and keeps the text before the cut", arguments: [0, 1, 2])
    func truncated(source: Int) throws {
        let html = source < 2 ? try description(Self.productFixtures[source]).html : try articleHTML()
        let scalars = Array(html.unicodeScalars)
        var lengths = Array(stride(from: 0, to: scalars.count, by: 97))
        lengths.append(scalars.count - 1)
        for length in lengths {
            var prefix = String.UnicodeScalarView()
            prefix.append(contentsOf: scalars[0..<length])
            let document = HTMLDocument(html: String(prefix), baseURL: URL(string: "https://www.karinex.de/"))
            #expect(!text(document.blocks).contains("<div"))
        }
    }

    @Test("Randomly damaged store HTML never crashes")
    func damaged() throws {
        let html = try articleHTML() + description(Fixture.productDE).html
        var scalars = Array(html.unicodeScalars)
        var generator = SplitMix64(seed: 0x4B58)
        let noise: [Unicode.Scalar] = ["<", ">", "&", "\"", "'", "/", "=", "#", ";", "!", "-", "\u{0}", "\u{FFFF}"]
        for round in 0..<40 {
            for _ in 0..<200 {
                let index = Int(generator.next() % UInt64(scalars.count))
                switch generator.next() % 3 {
                case 0: scalars[index] = noise[Int(generator.next() % UInt64(noise.count))]
                case 1: scalars.remove(at: index)
                default: scalars.insert(noise[Int(generator.next() % UInt64(noise.count))], at: index)
                }
            }
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars)
            let document = HTMLDocument(html: String(view), baseURL: round.isMultiple(of: 2) ? nil : URL(string: "https://www.karinex.de/"))
            #expect(links(document.blocks).allSatisfy { $0.url.scheme == nil || $0.url.scheme == "http" || $0.url.scheme == "https" })
        }
    }
}

/// A small deterministic generator, so the damage test is reproducible.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

// MARK: - Constructs

@Suite("HTMLDocument constructs")
struct HTMLDocumentConstructTests {
    private let base = URL(string: "https://www.karinex.de/products/x")

    private func blocks(_ html: String) -> [HTMLBlock] {
        HTMLDocument(html: html, baseURL: base).blocks
    }

    @Test("Empty and blank input")
    func empty() {
        #expect(HTMLDocument(html: "").isEmpty)
        #expect(HTMLDocument(html: "  \n\t <p> </p><div></div><!-- c -->").isEmpty)
        #expect(HTMLDocument(blocks: [.rule]).blocks == [.rule])
    }

    @Test("Character references: named, numeric, invalid and unknown")
    func entities() {
        #expect(blocks("<p>Gr&ouml;&szlig;e &amp; Preis &euro; &ndash; &#228;&#xE4;&#XE4; &#65 &copy;</p>")
            == [.paragraph([.text("Größe & Preis € \u{2013} äää A ©")])])
        #expect(blocks("<p>&#0;&#xD800;&#x110000;&#99999999999;</p>") == [.paragraph([.text("\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}")])])
        #expect(blocks("<p>&unknown; &amp &; &# &#x; a&b</p>") == [.paragraph([.text("&unknown; &amp &; &# &#x; a&b")])])
        #expect(blocks("<p>1&nbsp;000</p>") == [.paragraph([.text("1\u{A0}000")])])
    }

    @Test("White space collapses like in a browser, except in pre")
    func whitespace() {
        #expect(blocks("  <p>  a \n\t b  <strong> c </strong> d </p>  ")
            == [.paragraph([.text("a b "), .strong([.text("c")]), .text(" d")])])
        let breaks: [HTMLInline] = [.text("a"), .lineBreak, .text("b"), .lineBreak, .lineBreak, .text("c")]
        #expect(blocks("<p>a<br>b<br><br><br>c<br></p>") == [.paragraph(breaks)])
        #expect(blocks("<p><br> a </p>") == [.paragraph([.text("a")])])
        #expect(blocks("<pre>\n  let x = 1\n    y &lt; 2\n\n</pre>") == [.paragraph([.code("  let x = 1\n    y < 2")])])
        #expect(blocks("<p>run <code> swift\n test </code>now</p>") == [.paragraph([.text("run "), .code("swift test"), .text("now")])])
    }

    @Test("Text directly inside containers becomes paragraphs split by block children")
    func containers() {
        #expect(blocks("<div>one <em>two</em><div>three</div>four</div>")
            == [.paragraph([.text("one "), .emphasis([.text("two")])]), .paragraph([.text("three")]), .paragraph([.text("four")])])
        #expect(blocks("loose <b>text</b>") == [.paragraph([.text("loose "), .strong([.text("text")])])])
    }

    @Test("Headings, rules, quotes and nested inline styles")
    func structure() {
        #expect(blocks("<h1>A</h1><h4> <i>B</i> </h4><hr><blockquote><p>Q</p>R</blockquote>") == [
            .heading(level: 1, inlines: [.text("A")]),
            .heading(level: 4, inlines: [.emphasis([.text("B")])]),
            .rule,
            .quote([.paragraph([.text("Q")]), .paragraph([.text("R")])]),
        ])
        #expect(blocks("<p><strong>a <em>b</em></strong><span>c</span></p>")
            == [.paragraph([.strong([.text("a "), .emphasis([.text("b")])]), .text("c")])])
        #expect(blocks("<h2></h2><p><strong> </strong></p><blockquote> </blockquote>").isEmpty)
    }

    @Test("Lists: ordered, unordered, nested, implicit li ends and stray content")
    func lists() {
        #expect(blocks("<ol><li>One<li>Two<ul><li>Two a</li></ul></li></ol>") == [
            .list(ordered: true, items: [
                [.paragraph([.text("One")])],
                [.paragraph([.text("Two")]), .list(ordered: false, items: [[.paragraph([.text("Two a")])]])],
            ]),
        ])
        #expect(blocks("<ul>stray<li>a</li><li></li><p>more</p></ul>") == [
            .list(ordered: false, items: [[.paragraph([.text("stray")])], [.paragraph([.text("a")]), .paragraph([.text("more")])]]),
        ])
        #expect(blocks("<ul><li> </li></ul>").isEmpty)
    }

    @Test("Tables: header cells, sections, captions, implicit row and cell ends, nested blocks flattened")
    func tables() {
        let html = """
            <table><caption>Cap</caption><colgroup><col></colgroup><thead><tr><th>A<th>B</thead>
            <tbody><tr><td>1<td><p>x</p><p>y</p><tr><td></td><td>z</td></tbody><tfoot><tr><td> </td><td> </td></tfoot></table>
            """
        #expect(blocks(html) == [
            .paragraph([.text("Cap")]),
            .table(rows: [
                [HTMLTableCell(isHeader: true, inlines: [.text("A")]), HTMLTableCell(isHeader: true, inlines: [.text("B")])],
                [
                    HTMLTableCell(isHeader: false, inlines: [.text("1")]),
                    HTMLTableCell(isHeader: false, inlines: [.text("x"), .lineBreak, .text("y")]),
                ],
                [HTMLTableCell(isHeader: false, inlines: []), HTMLTableCell(isHeader: false, inlines: [.text("z")])],
            ]),
        ])
        #expect(blocks("<table><tr><td> </td></tr></table>").isEmpty)
        #expect(blocks("<p>a<table><tr><td>b</td></tr></table>")
            == [.paragraph([.text("a")]), .table(rows: [[HTMLTableCell(isHeader: false, inlines: [.text("b")])]])])
    }

    @Test("Links keep only http(s) and resolve relative references")
    func linkSchemes() {
        func link(_ href: String, base: URL? = URL(string: "https://www.karinex.de/products/x")) -> URL? {
            let document = HTMLDocument(html: "<p><a href=\"\(href)\">label</a></p>", baseURL: base)
            guard case let .paragraph(inlines)? = document.blocks.first else { return nil }
            if inlines == [.text("label")] { return nil }
            guard case let .link(url, children)? = inlines.first, children == [.text("label")] else { return nil }
            return url
        }
        #expect(link("https://example.com/a?b=c")?.absoluteString == "https://example.com/a?b=c")
        #expect(link("HTTP://example.com")?.host == "example.com")
        #expect(link("/collections/windows")?.absoluteString == "https://www.karinex.de/collections/windows")
        #expect(link("../pages/faq")?.absoluteString == "https://www.karinex.de/pages/faq")
        #expect(link("//cdn.example.com/x")?.absoluteString == "https://cdn.example.com/x")
        #expect(link("/collections/windows", base: nil)?.absoluteString == "/collections/windows")
        #expect(link("mailto:support@example.com") == nil)
        #expect(link("sms:+491234") == nil)
        #expect(link("javascript:alert(1)") == nil)
        #expect(link("java\tscript:alert(1)") == nil)
        #expect(link(" JavaScript:alert(1)") == nil)
        #expect(link("whatsapp://send") == nil)
        #expect(link("data:text/html,x") == nil)
        #expect(link("#section") == nil)
        #expect(link("") == nil)
        #expect(link("https://") == nil)
        #expect(blocks("<p><a>no href</a> <a href=\"/x\"></a></p>") == [.paragraph([.text("no href")])])
    }

    @Test("Images need an http(s) source; alt text is optional; inline images move after their paragraph")
    func images() {
        let cdn = "https://cdn.shopify.com/s/files/a.webp?v=1"
        #expect(blocks("<img src=\"\(cdn)\" alt=\" Box \">") == [.image(url: URL(string: cdn)!, alt: "Box")])
        #expect(blocks("<figure><img src='/files/b.png' alt=''><figcaption>Cap</figcaption></figure>")
            == [.image(url: URL(string: "https://www.karinex.de/files/b.png")!, alt: nil), .paragraph([.text("Cap")])])
        #expect(HTMLDocument(html: "<img src=\"/files/b.png\">").isEmpty)
        #expect(blocks("<img src=\"data:image/png;base64,AAAA\"><img>").isEmpty)
        #expect(blocks("<p>before <a href=\"/x\"><img src=\"\(cdn)\"></a> after</p>")
            == [.paragraph([.text("before after")]), .image(url: URL(string: cdn)!, alt: nil)])
    }

    @Test("Scripts, styles, iframes, forms, media and comments are dropped with their content")
    func dropped() {
        let html = """
            <!DOCTYPE html><!-- comment <p>hidden</p> --><style>p { color: red }</style><script>alert("<p>x</p>")</script>
            <iframe src="https://example.com">fallback</iframe><form><input value="v"><button>Go</button><p>in form</p></form>
            <noscript>ns</noscript><svg><text>t</text></svg><video>v</video><SCRIPT type="x">y</SCRIPT ><p>visible</p><?php echo 1 ?>
            """
        #expect(blocks(html) == [.paragraph([.text("visible")])])
        #expect(blocks("<p>a<script>b</p>") == [.paragraph([.text("a")])])
        #expect(blocks("<p>a<!-- unterminated") == [.paragraph([.text("a")])])
    }

    @Test("Malformed markup is recovered")
    func malformed() {
        #expect(blocks("<p>one<p>two</div></span></p>") == [.paragraph([.text("one")]), .paragraph([.text("two")])])
        #expect(blocks("<p>a < b > c</p>") == [.paragraph([.text("a < b > c")])])
        #expect(blocks("<p>x</p><") == [.paragraph([.text("x")]), .paragraph([.text("<")])])
        #expect(blocks("<p>x</p><a href=\"https://exam") == [.paragraph([.text("x")])])
        #expect(blocks("<p>x</p></") == [.paragraph([.text("x")])])
        #expect(blocks("<p>x</></ p>y") == [.paragraph([.text("xy")])])
        #expect(blocks("<p class=a=b c='d' e=\"f\" g>t</P>") == [.paragraph([.text("t")])])
        #expect(blocks("<h2>a<h3>b</h3>") == [.heading(level: 2, inlines: [.text("a")]), .heading(level: 3, inlines: [.text("b")])])
        #expect(blocks("<strong>bold<p>para</p></strong>") == [.paragraph([.strong([.text("bold"), .lineBreak, .text("para")])])])
    }

    @Test("Deep nesting is flattened instead of overflowing the stack")
    func deepNesting() {
        let depth = 20000
        let html = String(repeating: "<div><span>", count: depth) + "deep" + String(repeating: "</span></div>", count: depth)
        #expect(text(HTMLDocument(html: html).blocks) == "deep")
        let unclosed = String(repeating: "<blockquote><ul><li><strong>", count: 5000) + "x"
        #expect(text(HTMLDocument(html: unclosed).blocks).contains("x"))
    }
}
