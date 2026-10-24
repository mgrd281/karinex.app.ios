import Foundation
import Nuke
import ShopifyKit

// MARK: - KXImagePipeline

/// The image loading setup of the app: one shared Nuke pipeline with a bounded memory cache
/// and a 150 MB disk cache, and the request builder that every product image uses.
///
/// Call ``configure()`` once at launch, before the first image loads (the App target does it
/// in its composition root). Requests always carry `ShopifyImage.acceptHeader`, because the
/// Shopify CDN only serves WebP through content negotiation, and the CDN `width` parameter in
/// pixels (rendered width times display scale, rounded up to ``widthStep``), so the same image
/// at nearly the same size shares one cache entry.
public enum KXImagePipeline {
    /// The disk cache size limit: 150 MB.
    public static let diskCacheSizeLimit = 150 * 1024 * 1024
    /// The upper bound of the memory cache: 64 MB (less on devices where Nuke's default is lower).
    public static let memoryCacheCostLimit = 64 * 1024 * 1024
    /// The name of the disk cache directory in `Library/Caches`.
    public static let diskCacheName = "de.karinex.images"
    /// Requested pixel widths are rounded up to a multiple of this value.
    public static let widthStep = 120
    /// The largest pixel width requested from the CDN.
    public static let maximumPixelWidth = 2048

    /// Replaces `ImagePipeline.shared` with the KARINEX pipeline: original data in a 150 MB
    /// disk cache (`Library/Caches/de.karinex.images`), decoded images in a memory cache of at
    /// most ``memoryCacheCostLimit``, no `URLCache` in between.
    public static func configure() {
        ImagePipeline.shared = makePipeline()
    }

    /// Builds a pipeline with the KARINEX configuration without installing it.
    public static func makePipeline() -> ImagePipeline {
        var configuration = ImagePipeline.Configuration.withDataCache(name: diskCacheName, sizeLimit: diskCacheSizeLimit)
        configuration.imageCache = ImageCache(costLimit: min(ImageCache.defaultCostLimit, memoryCacheCostLimit))
        return ImagePipeline(configuration: configuration)
    }

    // MARK: Requests

    /// The CDN pixel width for an image rendered `pointWidth` points wide at `scale`: rounded
    /// up to a multiple of ``widthStep`` and clamped to `widthStep...maximumPixelWidth`.
    public static func pixelWidth(pointWidth: CGFloat, scale: CGFloat) -> Int {
        let pixels = max(pointWidth, 1) * max(scale, 1)
        guard pixels.isFinite else { return maximumPixelWidth }
        let steps = (pixels / CGFloat(widthStep)).rounded(.up)
        return min(max(Int(steps) * widthStep, widthStep), maximumPixelWidth)
    }

    /// The request for `url` at `pixelWidth`: the CDN `width` parameter on Shopify CDN URLs and
    /// the WebP `Accept` header on every request.
    public static func request(for url: URL, pixelWidth: Int?, priority: ImageRequest.Priority = .normal) -> ImageRequest {
        let sizedURL = pixelWidth.flatMap { isShopifyCDN(url) ? ShopifyImage(url: url).url(width: $0) : nil } ?? url
        var urlRequest = URLRequest(url: sizedURL)
        urlRequest.setValue(ShopifyImage.acceptHeader, forHTTPHeaderField: "Accept")
        return ImageRequest(urlRequest: urlRequest, priority: priority)
    }

    /// Whether `url` points to the Shopify CDN (`cdn.shopify.com` or a shop domain's
    /// `/cdn/shop/` path), which honours the `width` parameter. Other hosts get the URL unchanged.
    public static func isShopifyCDN(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "cdn.shopify.com" || url.path.hasPrefix("/cdn/shop/")
    }

    /// The request for `image` rendered `pointWidth` points wide at `scale`.
    public static func request(
        for image: ShopifyImage,
        pointWidth: CGFloat,
        scale: CGFloat,
        priority: ImageRequest.Priority = .normal
    ) -> ImageRequest {
        request(for: image.url, pixelWidth: pixelWidth(pointWidth: pointWidth, scale: scale), priority: priority)
    }
}

// MARK: - ProductImagePrefetcher

/// Prefetches product images into the memory cache for rows and grids that are about to
/// appear, with exactly the requests ``ProductImage`` will make (same width, same header), so
/// the prefetched entries are hits.
///
/// Keep one per list (for example in a view model or `@State`) and call ``prefetch(_:pointWidth:scale:)``
/// when the next page or row is known. Prefetching stops when the prefetcher is released.
public final class ProductImagePrefetcher: Sendable {
    private let prefetcher: ImagePrefetcher

    /// Creates a prefetcher on `pipeline` (the shared one by default).
    public init(pipeline: ImagePipeline = .shared) {
        prefetcher = ImagePrefetcher(pipeline: pipeline, destination: .memoryCache, maxConcurrentRequestCount: 2)
    }

    /// Starts prefetching `images` as rendered `pointWidth` points wide at `scale`. `nil`
    /// entries are skipped.
    public func prefetch(_ images: [ShopifyImage?], pointWidth: CGFloat, scale: CGFloat) {
        prefetcher.startPrefetching(with: requests(images, pointWidth: pointWidth, scale: scale))
    }

    /// Stops prefetching `images` (for example rows that scrolled far away).
    public func cancel(_ images: [ShopifyImage?], pointWidth: CGFloat, scale: CGFloat) {
        prefetcher.stopPrefetching(with: requests(images, pointWidth: pointWidth, scale: scale))
    }

    /// Stops every running prefetch.
    public func cancelAll() {
        prefetcher.stopPrefetching()
    }

    private func requests(_ images: [ShopifyImage?], pointWidth: CGFloat, scale: CGFloat) -> [ImageRequest] {
        images.compactMap { image in
            image.map { KXImagePipeline.request(for: $0, pointWidth: pointWidth, scale: scale, priority: .low) }
        }
    }
}
