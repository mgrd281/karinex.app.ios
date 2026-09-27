import Foundation

/// Masks personal data and secrets in free text before it is logged.
///
/// `redact(_:)` replaces, in this order:
///
/// 1. values of credential headers and cookies (`Authorization`, `Proxy-Authorization`,
///    `X-Shopify-Storefront-Access-Token`, `Shopify-Storefront-Private-Token`,
///    `X-Shopify-Customer-Access-Token`, `X-Shopify-Access-Token`, `Cookie`, `Set-Cookie`),
/// 2. `Bearer <token>` credentials,
/// 3. values of unambiguous secret fields in JSON or form bodies (`access_token`,
///    `refresh_token`, `id_token`, `code_verifier`, `client_secret`, `password`, and their
///    camelCase spellings),
/// 4. values of sensitive URL query and fragment items (`access_token`, `refresh_token`,
///    `id_token`, `code`, `state`, `nonce`, `code_verifier`, `key`, `cart`, `email`, `token`,
///    `client_secret`, `password`),
/// 5. the identifying part of Shopify GIDs that carry cart tokens or personal data
///    (`Cart`, `CartLine`, `Checkout`, `Customer`, `CustomerAddress`, `MailingAddress`),
///    keeping the type prefix: `gid://shopify/Cart/<redacted>`. Other GIDs such as
///    `gid://shopify/Product/123` are kept because they identify public catalog data,
/// 6. cart and checkout tokens in web paths (`/cart/c/<token>`, `/checkouts/cn/<token>`),
/// 7. Shopify access tokens (`shpat_`, `shpca_`, `shcat_`, `shpss_`, `shppa_`, `shpua_`,
///    `atkn_` prefixes),
/// 8. JSON Web Tokens (three base64url segments, the first starting with `eyJ`),
/// 9. email addresses (also percent-encoded as `%40`),
/// 10. Microsoft-style product keys (`XXXXX-XXXXX-XXXXX-XXXXX-XXXXX`),
/// 11. long opaque secrets: runs of 32 or more hexadecimal characters, and base64 or base64url
///     runs of 32 or more characters that mix upper case, lower case and digits and do not
///     read like words (so product handles, file names and operation names are kept).
///
/// Every match is replaced with `<redacted>`. Prices, sentences, product handles, product
/// GIDs, image URLs, status codes and durations pass through unchanged.
public enum Redactor {
    /// The text that replaces every redacted value.
    public static let replacement = "<redacted>"

    // MARK: - Public API

    /// Returns `text` with all personal data and secrets replaced by `<redacted>`.
    public static func redact(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for rule in rules {
            result = rule.apply(to: result)
        }
        return result
    }

    /// Returns `url` as a string with every query and fragment value replaced by `<redacted>`
    /// (item names are kept), user info masked, and the remaining parts passed through
    /// `redact(_:)`.
    ///
    /// ```swift
    /// Redactor.redact(url: URL(string: "https://shop.example/callback?code=abc&state=xyz")!)
    /// // "https://shop.example/callback?code=<redacted>&state=<redacted>"
    /// ```
    public static func redact(url: URL) -> String {
        redact(urlString: url.absoluteString)
    }

    // MARK: - URL handling

    /// Implementation of `redact(url:)` on the URL string.
    static func redact(urlString: String) -> String {
        var remainder = Substring(urlString)

        var fragment: Substring?
        if let hashIndex = remainder.firstIndex(of: "#") {
            fragment = remainder[remainder.index(after: hashIndex)...]
            remainder = remainder[..<hashIndex]
        }
        var query: Substring?
        if let questionIndex = remainder.firstIndex(of: "?") {
            query = remainder[remainder.index(after: questionIndex)...]
            remainder = remainder[..<questionIndex]
        }

        var base = String(remainder)
        if let schemeSeparator = base.range(of: "://") {
            let authorityStart = schemeSeparator.upperBound
            let authorityEnd = base[authorityStart...].firstIndex(of: "/") ?? base.endIndex
            if let userInfoEnd = base[authorityStart..<authorityEnd].lastIndex(of: "@") {
                base.replaceSubrange(authorityStart..<userInfoEnd, with: replacement)
            }
        }

        var result = redact(base)
        if let query {
            result += "?" + redactItemValues(query)
        }
        if let fragment {
            result += "#" + redactItemValues(fragment)
        }
        return result
    }

    /// Replaces the value of every `name=value` item; items without `=` go through `redact(_:)`.
    private static func redactItemValues(_ component: Substring) -> String {
        component
            .split(separator: "&", omittingEmptySubsequences: false)
            .map { item -> String in
                guard let equalsIndex = item.firstIndex(of: "=") else {
                    return redact(String(item))
                }
                return String(item[..<equalsIndex]) + "=" + replacement
            }
            .joined(separator: "&")
    }

    // MARK: - Rules

    private static let secretHeaderNames = [
        "authorization", "proxy-authorization", "x-shopify-storefront-access-token",
        "shopify-storefront-private-token", "x-shopify-customer-access-token", "x-shopify-access-token",
        "set-cookie", "cookie",
    ]

    private static let secretFieldNames = [
        "access_token", "refresh_token", "id_token", "code_verifier", "client_secret", "password",
        "accessToken", "refreshToken", "idToken", "codeVerifier", "clientSecret", "customerAccessToken",
    ]

    private static let sensitiveQueryItemNames = [
        "access_token", "refresh_token", "id_token", "code_verifier", "client_secret", "password",
        "code", "state", "nonce", "key", "cart", "email", "token",
    ]

    private static let sensitiveGIDTypes = [
        "CartLine", "Cart", "Checkout", "CustomerAddress", "Customer", "MailingAddress",
    ]

    private static let shopifyTokenPrefixes = ["shpat", "shpca", "shcat", "shpss", "shppa", "shpua", "atkn"]

    private static let rules: [RedactionRule] = [
        // 1. Credential headers, in header lines, dictionary descriptions and JSON.
        RedactionRule(
            pattern: #"(?i)\b("# + secretHeaderNames.joined(separator: "|") + #")("?\s*[:=]\s*"?)([^"\r\n,}\]]+)"#,
            template: "$1$2" + replacement
        ),
        // 2. Bearer credentials.
        RedactionRule(
            pattern: #"(?i)\b(bearer)\s+[A-Za-z0-9\-._~+/]+=*"#,
            template: "$1 " + replacement
        ),
        // 3. Secret fields in JSON or form bodies.
        RedactionRule(
            pattern: #"(?i)(?<![A-Za-z0-9_])("?(?:"# + secretFieldNames.joined(separator: "|")
                + #")"?\s*[:=]\s*"?)([^"\s&,}<]+)"#,
            template: "$1" + replacement
        ),
        // 4. Sensitive query and fragment items.
        RedactionRule(
            pattern: #"(?i)([?&#;](?:"# + sensitiveQueryItemNames.joined(separator: "|") + #")=)([^&#\s"'<>]+)"#,
            template: "$1" + replacement
        ),
        // 5. GIDs carrying cart tokens or personal data, also percent-encoded.
        RedactionRule(
            pattern: #"(?i)(gid(?::|%3A)(?://|%2F%2F)shopify(?:/|%2F)(?:"# + sensitiveGIDTypes.joined(separator: "|")
                + #")(?:/|%2F))([^\s"'?&#%,;)\]}<>]+)"#,
            template: "$1" + replacement
        ),
        // 6. Cart and checkout tokens in web paths.
        RedactionRule(
            pattern: #"(?i)(/cart/c/|/checkouts/(?:cn|co|ac|c)/)([A-Za-z0-9_\-]+)"#,
            template: "$1" + replacement
        ),
        // 7. Shopify access tokens.
        RedactionRule(
            pattern: #"\b(?:"# + shopifyTokenPrefixes.joined(separator: "|") + #")_[A-Za-z0-9_\-.]+"#,
            template: replacement
        ),
        // 8. JSON Web Tokens.
        RedactionRule(
            pattern: #"\beyJ[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]*"#,
            template: replacement
        ),
        // 9. Email addresses, plain or percent-encoded.
        RedactionRule(
            pattern: #"(?i)[A-Z0-9._%+\-]+(?:@|%40)[A-Z0-9\-]+(?:\.[A-Z0-9\-]+)*\.[A-Z]{2,}"#,
            template: replacement
        ),
        // 10. Microsoft-style product keys.
        RedactionRule(
            pattern: #"(?i)\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}\b"#,
            template: replacement
        ),
        // 11. Long opaque hex or base64 secrets.
        RedactionRule(
            pattern: #"(?<![A-Za-z0-9_+\-])[A-Za-z0-9_+\-]{32,}={0,2}(?![A-Za-z0-9_+=\-])"#,
            replacement: { match in looksLikeOpaqueSecret(match) ? replacement : nil }
        ),
    ]

    // MARK: - Opaque secret heuristic

    /// Decides whether a 32+ character run of base64 characters is an opaque secret.
    ///
    /// Pure hexadecimal runs always are (API tokens, hashes). Otherwise the run must mix upper
    /// case, lower case and digits, and its word-like segments must be short on average.
    /// Random tokens switch character classes every one or two characters, while human-made
    /// identifiers such as `Windows-11-Pro-Key-Download-kaufen` or
    /// `ProductByHandleQueryWithMetafields` consist of long words.
    static func looksLikeOpaqueSecret(_ candidate: Substring) -> Bool {
        let body = candidate.prefix(while: { $0 != "=" })
        guard body.count >= 32 else { return false }
        if body.allSatisfy(\.isHexDigit) { return true }

        enum CharacterClass { case upper, lower, digit }
        var hasUpper = false
        var hasLower = false
        var hasDigit = false
        var characters = 0
        var runs = 0
        var previous: CharacterClass?

        for scalar in body.unicodeScalars {
            let current: CharacterClass
            switch scalar {
            case "A"..."Z":
                current = .upper
                hasUpper = true
            case "a"..."z":
                current = .lower
                hasLower = true
            case "0"..."9":
                current = .digit
                hasDigit = true
            default:
                // Separators (`-`, `_`, `+`) end the current run.
                previous = nil
                continue
            }
            characters += 1
            let continuesRun = switch (previous, current) {
            case (.upper?, .lower): true
            case let (previousClass?, currentClass): previousClass == currentClass
            case (nil, _): false
            }
            if !continuesRun { runs += 1 }
            previous = current
        }

        guard hasUpper, hasLower, hasDigit, runs > 0 else { return false }
        let averageRunLength = Double(characters) / Double(runs)
        return averageRunLength < 4
    }
}

// MARK: - RedactionRule

/// A compiled regular expression plus the text that replaces each match.
private struct RedactionRule: @unchecked Sendable {
    // `@unchecked Sendable` is sound: `NSRegularExpression` is immutable and documented as safe
    // to use from multiple threads, and the custom replacement closure is `@Sendable`. Not
    // every SDK marks `NSRegularExpression` as `Sendable`, hence the annotation.

    private enum Replacement {
        /// A template that may reference capture groups (`$1`).
        case template(String)
        /// Computes the replacement for a whole match; `nil` keeps the match unchanged.
        case custom(@Sendable (Substring) -> String?)
    }

    private let regex: NSRegularExpression
    private let replacement: Replacement

    /// A rule that replaces each match with `template`, which may use `$1`-style group references.
    init(pattern: String, template: String) {
        regex = Self.compile(pattern)
        replacement = .template(template)
    }

    /// A rule that asks `replacement` for each whole match; `nil` keeps the match unchanged.
    init(pattern: String, replacement: @escaping @Sendable (Substring) -> String?) {
        regex = Self.compile(pattern)
        self.replacement = .custom(replacement)
    }

    /// Returns `text` with every match replaced.
    func apply(to text: String) -> String {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        switch replacement {
        case let .template(template):
            return regex.stringByReplacingMatches(in: text, options: [], range: fullRange, withTemplate: template)
        case let .custom(transform):
            let matches = regex.matches(in: text, options: [], range: fullRange)
            guard !matches.isEmpty else { return text }
            var result = ""
            var cursor = text.startIndex
            for match in matches {
                guard let matchRange = Range(match.range, in: text),
                      let replacementText = transform(text[matchRange])
                else { continue }
                result += text[cursor..<matchRange.lowerBound]
                result += replacementText
                cursor = matchRange.upperBound
            }
            result += text[cursor...]
            return result
        }
    }

    private static func compile(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            // The patterns are constants covered by unit tests. A broken pattern is a
            // programming error that must never ship silently without redaction.
            preconditionFailure("Invalid redaction pattern: \(pattern)")
        }
    }
}
