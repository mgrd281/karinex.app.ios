import Foundation

/// An image on the Shopify CDN (Storefront `Image`).
public struct ShopifyImage: Sendable, Hashable, Codable {
    /// The `Accept` header to send when loading CDN images.
    ///
    /// This header is the WebP switch: the Shopify CDN ignores a `format=webp` query parameter
    /// but negotiates the format from `Accept`, so `image/webp` first yields WebP (about half
    /// the bytes of the original in tests on 2026-09-26) while other formats stay acceptable.
    public static let acceptHeader = "image/webp,image/*;q=0.8"

    /// The original image URL (usually with a `v` cache-busting parameter).
    public let url: URL
    /// The merchant's alternative text, used as the accessibility label.
    public let altText: String?
    /// The original width in pixels, if known.
    public let width: Int?
    /// The original height in pixels, if known.
    public let height: Int?

    /// Creates an image value.
    public init(url: URL, altText: String? = nil, width: Int? = nil, height: Int? = nil) {
        self.url = url
        self.altText = altText
        self.width = width
        self.height = height
    }

    /// The URL of a CDN rendition `width` pixels wide.
    ///
    /// Adds or replaces the `width` query item and keeps every other query item (such as the
    /// `v` cache buster) exactly as it was. Pass pixels, not points: multiply by the display
    /// scale. Values below 1 are treated as 1.
    public func url(width: Int) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.percentEncodedQueryItems ?? []).filter { $0.name != "width" }
        items.append(URLQueryItem(name: "width", value: String(max(width, 1))))
        components.percentEncodedQueryItems = items
        return components.url ?? url
    }

    /// Width divided by height, or `nil` when either is unknown or zero.
    public var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }
}
