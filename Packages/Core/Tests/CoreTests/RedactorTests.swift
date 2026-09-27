@testable import Core
import Foundation
import Testing

@Suite("Redactor")
struct RedactorTests {
    // MARK: - Patterns

    @Test("Masks email addresses")
    func emails() {
        #expect(Redactor.redact("Login for kundin.muster+app@example-mail.de failed") == "Login for <redacted> failed")
        #expect(Redactor.redact("email=anna%40example.com") == "email=<redacted>")
        #expect(Redactor.redact("Contact: A.B@Sub.Example.CO.UK.") == "Contact: <redacted>.")
    }

    @Test("Masks bearer tokens")
    func bearer() {
        #expect(Redactor.redact("using Bearer abc.DEF-123_xyz~/+= now") == "using Bearer <redacted> now")
        #expect(Redactor.redact("bearer tok3n") == "bearer <redacted>")
    }

    @Test("Masks credential header values")
    func headers() {
        #expect(
            Redactor.redact("X-Shopify-Storefront-Access-Token: 0f1e2d3c4b5a69788796a5b4c3d2e1f0")
                == "X-Shopify-Storefront-Access-Token: <redacted>"
        )
        #expect(
            Redactor.redact(#"["Authorization": "Bearer shcat_abc", "Accept": "application/json"]"#)
                == #"["Authorization": "<redacted>", "Accept": "application/json"]"#
        )
        #expect(Redactor.redact(#"{"authorization":"Basic dXNlcjpwYXNz"}"#) == #"{"authorization":"<redacted>"}"#)
        #expect(Redactor.redact("Cookie: _session=abc; cart=xyz") == "Cookie: <redacted>")
    }

    @Test("Masks Shopify access tokens", arguments: ["shpat_", "shpca_", "shcat_", "atkn_", "shpss_", "shppa_", "shpua_"])
    func shopifyTokens(prefix: String) {
        #expect(Redactor.redact("token \(prefix)AbC123_def-456 rotated") == "token <redacted> rotated")
    }

    @Test("Masks JSON Web Tokens")
    func jwt() {
        let jwt = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(Redactor.redact("id token \(jwt) received") == "id token <redacted> received")
        #expect(Redactor.redact("unsigned eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0. end") == "unsigned <redacted> end")
    }

    @Test("Masks long hex secrets")
    func hexSecrets() {
        #expect(Redactor.redact("token=0123456789abcdef0123456789ABCDEF done") == "token=<redacted> done")
        #expect(Redactor.redact("sha 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08") == "sha <redacted>")
    }

    @Test("Masks long base64 secrets")
    func base64Secrets() {
        #expect(Redactor.redact("verifier dBjftJeZ4CVPmB92K27uhbUJU1p1rwW1gFWFOEjXk2Q ok") == "verifier <redacted> ok")
        #expect(Redactor.redact("blob c2VjcmV0LXZhbHVlLXRoYXQtaXMtbG9uZy1lbm91Z2g= ok") == "blob <redacted> ok")
        #expect(Redactor.redact("url-safe Z2NwLWV1cm9wZS13ZXN0NDowMUpBQ0tYTlhIWk5ZRjc1_TU1WN0pNVjc2 ok") == "url-safe <redacted> ok")
    }

    @Test("Masks Microsoft product keys")
    func productKeys() {
        #expect(Redactor.redact("Key XXXXX-00000-XXXXX-00000-XXXXX delivered") == "Key <redacted> delivered")
        #expect(Redactor.redact("key: abcd1-efgh2-ijkl3-mnop4-qrst5") == "key: <redacted>")
    }

    @Test("Masks cart and checkout tokens in GIDs, keeping the type")
    func cartGIDs() {
        #expect(
            Redactor.redact("cart gid://shopify/Cart/Z2NwLWV1cm9wZS13ZXN0NDowMUpBQ0tY?key=4f2a9c created")
                == "cart gid://shopify/Cart/<redacted>?key=<redacted> created"
        )
        #expect(Redactor.redact("gid://shopify/Checkout/abc123def") == "gid://shopify/Checkout/<redacted>")
        #expect(
            Redactor.redact("line gid://shopify/CartLine/0d1c7e5b-4a09-4b3c-9d2e?cart=Z2NwLWV1")
                == "line gid://shopify/CartLine/<redacted>?cart=<redacted>"
        )
        #expect(Redactor.redact("gid%3A%2F%2Fshopify%2FCart%2Fc1-abc%3Fkey") == "gid%3A%2F%2Fshopify%2FCart%2F<redacted>%3Fkey")
    }

    @Test("Masks customer GIDs")
    func customerGIDs() {
        #expect(Redactor.redact("customer gid://shopify/Customer/7212345678901") == "customer gid://shopify/Customer/<redacted>")
        #expect(
            Redactor.redact("gid://shopify/MailingAddress/123?model_name=CustomerAddress")
                == "gid://shopify/MailingAddress/<redacted>?model_name=CustomerAddress"
        )
    }

    @Test("Masks cart tokens in checkout URLs")
    func checkoutPaths() {
        #expect(
            Redactor.redact("https://www.karinex.de/cart/c/Z2NwLWV1cm9wZS13ZXN0NDowMUpB?key=abc")
                == "https://www.karinex.de/cart/c/<redacted>?key=<redacted>"
        )
        #expect(Redactor.redact("https://www.karinex.de/checkouts/cn/hWN1-abc/de") == "https://www.karinex.de/checkouts/cn/<redacted>/de")
    }

    @Test(
        "Masks sensitive query items",
        arguments: ["access_token", "refresh_token", "id_token", "code", "state", "nonce", "code_verifier", "key"]
    )
    func queryItems(name: String) {
        #expect(
            Redactor.redact("GET https://shop.example/callback?\(name)=s3cr3t&locale=de")
                == "GET https://shop.example/callback?\(name)=<redacted>&locale=de"
        )
        #expect(Redactor.redact("GET https://shop.example/cb?a=1&\(name)=s3cr3t") == "GET https://shop.example/cb?a=1&\(name)=<redacted>")
    }

    @Test("Masks secret fields in JSON and form bodies")
    func secretFields() {
        #expect(
            Redactor.redact(#"{"access_token": "abc", "expires_in": 3600, "refresh_token":"def"}"#)
                == #"{"access_token": "<redacted>", "expires_in": 3600, "refresh_token":"<redacted>"}"#
        )
        #expect(
            Redactor.redact("grant_type=authorization_code&code_verifier=xyz&client_id=abc")
                == "grant_type=authorization_code&code_verifier=<redacted>&client_id=abc"
        )
        #expect(Redactor.redact("customerAccessToken: abc123") == "customerAccessToken: <redacted>")
    }

    @Test("Masks OAuth values in URL fragments")
    func fragments() {
        #expect(Redactor.redact("karinex://auth#access_token=abc&state=xyz") == "karinex://auth#access_token=<redacted>&state=<redacted>")
    }

    @Test("Masks sensitive items of a percent-encoded URL nested in a query")
    func percentEncodedNestedQuery() {
        #expect(
            Redactor.redact("login https://shop.example/auth?return_to=%2Fcallback%3Fcode%3Dabc123%26state%3Dxyz%26locale%3Dde")
                == "login https://shop.example/auth?return_to=%2Fcallback%3Fcode%3D<redacted>%26state%3D<redacted>%26locale%3Dde"
        )
        #expect(
            Redactor.redact("next=%2Fcb%3faccess_token%3dsecret%252F123%23frag")
                == "next=%2Fcb%3faccess_token%3d<redacted>%23frag"
        )
    }

    @Test("Masks customer access tokens and token exchange fields in snake case")
    func tokenExchangeFields() {
        #expect(Redactor.redact("customer_access_token=abc123") == "customer_access_token=<redacted>")
        #expect(
            Redactor.redact(#"{"subject_token":"abc","actor_token": "def"}"#)
                == #"{"subject_token":"<redacted>","actor_token": "<redacted>"}"#
        )
        #expect(
            Redactor.redact("POST /oauth/token?grant_type=x&subject_token=abc&client_id=1")
                == "POST /oauth/token?grant_type=x&subject_token=<redacted>&client_id=1"
        )
    }

    // MARK: - No false positives

    @Test(
        "Leaves ordinary text untouched",
        arguments: [
            "Ihr Warenkorb ist leer.",
            "Preis 29,90 €, statt 149,99 €",
            "CHF 29.00",
            "Microsoft Office 2024 Professional Plus Download kaufen",
            "Windows 11 Pro kaufen, Dauerlizenz 1 PC, Download",
            "gid://shopify/Product/9876543210",
            "gid://shopify/ProductVariant/51234567890123",
            "gid://shopify/Collection/612345678901",
            "gid://shopify/Order/6123456789012",
            "product office-2024-professional-plus-key fetched",
            "handle microsoft-office-2024-standard-fur-mac-key-sofort-download",
            "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Office_2024_Professional_Plus.webp?width=600",
            "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Windows-11-Pro-Key-Download-kaufen..webp?v=1787442708",
            "ProductByHandleQueryWithMetafieldsAndCollections status=200 duration=84ms cost=5",
            "CollectionProducts status=503 attempt=2 retryAfter=1.5",
            "error code THROTTLED on path product.metafields",
            "request 123e4567-e89b-12d3-a456-426614174000 finished",
            "@inContext(country: DE, language: PT_PT)",
            "Support Mo. bis So., 06:00 bis 23:00 Uhr",
            "Image logo@2x.png failed to load",
            "asset icon@3x.jpeg, badge@2x.webp",
            "Retry-After: 120",
            "sku 4260712033710",
            "",
        ]
    )
    func noFalsePositives(text: String) {
        #expect(Redactor.redact(text) == text)
    }

    @Test("Is idempotent")
    func idempotent() {
        let once = Redactor.redact("a@b.de Bearer xyz gid://shopify/Cart/abc?key=1 shpat_123 XXXXX-00000-XXXXX-00000-XXXXX")
        #expect(Redactor.redact(once) == once)
        #expect(!once.contains("a@b.de"))
        #expect(!once.contains("xyz"))
        #expect(!once.contains("shpat_"))
    }

    // MARK: - URLs

    @Test("redact(url:) masks every query and fragment value")
    func redactURL() throws {
        let url = try #require(URL(string: "https://shop.example/authorize?client_id=abc&scope=openid%20email&state=xyz&flag#frag=1"))
        #expect(
            Redactor.redact(url: url)
                == "https://shop.example/authorize?client_id=<redacted>&scope=<redacted>&state=<redacted>&flag#frag=<redacted>"
        )
    }

    @Test("redact(url:) removes user info and masks path tokens")
    func redactURLUserInfo() throws {
        let url = try #require(URL(string: "https://user:pass@www.karinex.de/cart/c/Z2NwLWV1cm9wZS13?key=abc"))
        #expect(Redactor.redact(url: url) == "https://<redacted>@www.karinex.de/cart/c/<redacted>?key=<redacted>")
    }

    @Test("redact(url:) keeps URLs without query untouched")
    func redactURLWithoutQuery() throws {
        let url = try #require(URL(string: "https://45dv93-bk.myshopify.com/api/2026-07/graphql.json"))
        #expect(Redactor.redact(url: url) == "https://45dv93-bk.myshopify.com/api/2026-07/graphql.json")
    }

    // MARK: - Heuristic

    @Test("The opaque secret heuristic separates tokens from identifiers")
    func heuristic() {
        #expect(Redactor.looksLikeOpaqueSecret("Z2NwLWV1cm9wZS13ZXN0NDowMUpBQ0tYTlhIWk5ZRjc1"))
        #expect(Redactor.looksLikeOpaqueSecret("0123456789abcdef0123456789abcdef"))
        #expect(!Redactor.looksLikeOpaqueSecret("Windows-11-Pro-Key-Download-kaufen-Dauerlizenz"))
        #expect(!Redactor.looksLikeOpaqueSecret("ProductByHandleQueryWithMetafields2026"))
        #expect(!Redactor.looksLikeOpaqueSecret("short"))
    }
}
