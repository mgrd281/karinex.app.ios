import Foundation
@testable import ShopifyKit
import Testing

@Suite("ContextInjector")
struct ContextInjectorTests {
    private let directive = "@inContext(country: DE, language: DE)"

    // MARK: - Placement

    @Test("Anonymous query keyword")
    func anonymousQuery() throws {
        let result = try ContextInjector.inject(directive, into: "query { shop { name } }")
        #expect(result == "query @inContext(country: DE, language: DE) { shop { name } }")
    }

    @Test("Shorthand query without keyword gets one")
    func shorthandQuery() throws {
        let result = try ContextInjector.inject(directive, into: "{ shop { name } }")
        #expect(result == "query @inContext(country: DE, language: DE) { shop { name } }")
    }

    @Test("Named query")
    func namedQuery() throws {
        let result = try ContextInjector.inject(directive, into: "query Shop { shop { name } }")
        #expect(result == "query Shop @inContext(country: DE, language: DE) { shop { name } }")
    }

    @Test("Named query without space before the selection set")
    func namedQueryWithoutSpace() throws {
        let result = try ContextInjector.inject(directive, into: "query Shop{shop{name}}")
        #expect(result == "query Shop @inContext(country: DE, language: DE) {shop{name}}")
    }

    @Test("Variables with default values containing parentheses, braces and hashes")
    func variablesWithDefaults() throws {
        let document = """
            query Search($query: String = "a (b) {c} #d", $input: CartInput = {lines: [{quantity: 1}]}, $first: Int = 10) {
              search(query: $query, first: $first) { totalCount }
            }
            """
        let result = try ContextInjector.inject(directive, into: document)
        #expect(result.contains("$first: Int = 10) @inContext(country: DE, language: DE) {\n  search("))
        #expect(result.components(separatedBy: "@inContext").count == 2)
    }

    @Test("Block strings with quotes and braces in default values")
    func blockStrings() throws {
        let document = #"query Q($note: String = """a "quoted" { brace \""" end""") { shop { name } }"#
        let result = try ContextInjector.inject(directive, into: document)
        #expect(result.hasSuffix(#"end""") @inContext(country: DE, language: DE) { shop { name } }"#))
    }

    @Test("Comments before and inside the operation are skipped")
    func comments() throws {
        let document = """
            # query Fake { fake }
            query Real( # a comment with ( and {
              $handle: String! # another { comment
            ) {
              product(handle: $handle) { title }
            }
            """
        let result = try ContextInjector.inject(directive, into: document)
        #expect(result.contains("# query Fake { fake }\nquery Real("))
        #expect(result.contains(") @inContext(country: DE, language: DE) {\n  product("))
    }

    @Test("Fragments before the operation are skipped")
    func fragmentFirst() throws {
        let document = """
            fragment ImageFields on Image @deprecatedFragment(reason: "x") { url altText }
            query Product { product(handle: "a") { featuredImage { ...ImageFields } } }
            """
        let result = try ContextInjector.inject(directive, into: document)
        #expect(result.contains("fragment ImageFields on Image @deprecatedFragment(reason: \"x\") { url altText }"))
        #expect(result.contains("query Product @inContext(country: DE, language: DE) { product("))
    }

    @Test("Mutations")
    func mutation() throws {
        let document = "mutation CartCreate($input: CartInput!) { cartCreate(input: $input) { cart { id } } }"
        let result = try ContextInjector.inject(directive, into: document)
        let expected = "mutation CartCreate($input: CartInput!) @inContext(country: DE, language: DE) "
            + "{ cartCreate(input: $input) { cart { id } } }"
        #expect(result == expected)
    }

    @Test("Existing directives are kept, the new one follows them")
    func existingDirectives() throws {
        let result = try ContextInjector.inject(directive, into: "query Q @cached(ttl: 60) @live { shop { name } }")
        #expect(result == "query Q @cached(ttl: 60) @live @inContext(country: DE, language: DE) { shop { name } }")
    }

    @Test("Non-ASCII text in strings and comments is preserved")
    func unicode() throws {
        let document = "# Überschrift ✓\nquery Q($q: String = \"Schlüssel · Ärger\") { shop { name } }"
        let result = try ContextInjector.inject(directive, into: document)
        let expected = "# Überschrift ✓\nquery Q($q: String = \"Schlüssel · Ärger\") "
            + "@inContext(country: DE, language: DE) { shop { name } }"
        #expect(result == expected)
    }

    @Test(
        "Lexical edge cases: empty and escaped strings, CRLF, inline fragments, a BOM, fragments after the operation",
        arguments: [
            (#"query Q($a: String = "") { x }"#, #"query Q($a: String = "") @inContext(country: DE, language: DE) { x }"#),
            (#"query Q($a: String = "a\"){b") { x }"#, #"query Q($a: String = "a\"){b") @inContext(country: DE, language: DE) { x }"#),
            ("query Q\r\n{\r\n  x\r\n}", "query Q\r\n@inContext(country: DE, language: DE) {\r\n  x\r\n}"),
            ("query Q { ... on Shop { name } }", "query Q @inContext(country: DE, language: DE) { ... on Shop { name } }"),
            ("\u{FEFF}query Q { x }", "\u{FEFF}query Q @inContext(country: DE, language: DE) { x }"),
            (
                #"query Q($f: Float = -1.5e3) @a(b: """x""") { x } fragment F on Shop { name }"#,
                #"query Q($f: Float = -1.5e3) @a(b: """x""") @inContext(country: DE, language: DE) { x } fragment F on Shop { name }"#
            ),
        ]
    )
    func lexicalEdgeCases(document: String, expected: String) throws {
        #expect(try ContextInjector.inject(directive, into: document) == expected)
    }

    @Test("A blank directive leaves the document unchanged")
    func blankDirective() throws {
        let document = "query Q { shop { name } }"
        #expect(try ContextInjector.inject("  ", into: document) == document)
    }

    // MARK: - Errors

    @Test("Documents without an operation")
    func noOperation() {
        #expect(throws: ContextInjectionError.noOperation) {
            try ContextInjector.inject(directive, into: "")
        }
        #expect(throws: ContextInjectionError.noOperation) {
            try ContextInjector.inject(directive, into: "# only a comment\nfragment F on Shop { name }")
        }
        #expect(throws: ContextInjectionError.noOperation) {
            try ContextInjector.inject(directive, into: "subscription S { event { id } }")
        }
    }

    @Test("Operations that already have @inContext")
    func alreadyHasInContext() {
        #expect(throws: ContextInjectionError.alreadyHasInContext) {
            try ContextInjector.inject(directive, into: "query Q @inContext(country: CH) { shop { name } }")
        }
    }

    @Test("Documents with more than one operation")
    func multipleOperations() {
        #expect(throws: ContextInjectionError.multipleOperations) {
            try ContextInjector.inject(directive, into: "query A { shop { name } } query B { shop { name } }")
        }
        #expect(throws: ContextInjectionError.multipleOperations) {
            try ContextInjector.inject(directive, into: "{ shop { name } } mutation M { cartCreate { cart { id } } }")
        }
    }

    @Test(
        "Malformed documents",
        arguments: [
            "query Q { shop { name }",
            "query Q($a: String = \"unterminated) { shop { name } }",
            "query Q($a: String = \"\"\"unterminated block) { shop { name } }",
            "query Q",
            "query Q($a: Int",
            "query Q @ { shop }",
            "query Q } {",
            "type Shop { name: String }",
            "fragment F Shop { name } query Q { shop { name } }",
            "query Q { shop { name } } %",
            "query Q { shop { .. } }",
        ]
    )
    func malformed(document: String) {
        #expect(throws: ContextInjectionError.malformedDocument) {
            try ContextInjector.inject(directive, into: document)
        }
    }

    // MARK: - Shipped documents

    @Test("Every shipped document takes the directive exactly once, before the operation's selection set")
    func shippedDocuments() throws {
        let documents: [(String, String)] = [
            (LocalizationQuery.document, "query Localization @inContext"),
            (ProductByHandleQuery.document, ") @inContext"),
            (CollectionProductsQuery.document, ") @inContext"),
            (CartCreateMutation.document, "mutation CartCreate($input: CartInput!) @inContext"),
        ]
        for (document, expectedFragment) in documents {
            let result = try ContextInjector.inject(germanyContext.directive, into: document)
            #expect(result.components(separatedBy: "@inContext").count == 2)
            #expect(result.contains(expectedFragment))
            #expect(!document.contains("@inContext"))
        }
    }
}
