import CoreGraphics
import DesignSystem
import DesignTokens
import Foundation
import Nuke
import ShopifyKit
import SwiftUI
import UIKit

// MARK: - ProductPanelTint

/// The two colors of a panel tinted by a product photo: the panel color at the top and its
/// deepened lower end (``DesignTokens/TintToken``). Light text tokens of the dark appearance are
/// readable on both.
public struct ProductPanelTint: Sendable, Hashable {
    /// The color at the top of the panel.
    public let top: Color
    /// The darker color at the bottom of the panel.
    public let bottom: Color

    /// The panel colors for a ``DesignTokens/TintToken`` panel color.
    public init(color: RGBAColor) {
        top = KXColor.fixed(color)
        bottom = KXColor.fixed(TintToken.deepened(color))
    }
}

// MARK: - ProductImageTint

/// The panel color of a product photo (``DesignTokens/TintToken``): loads a small version of the
/// photo through the shared image pipeline, samples its pixels and keeps the result per URL, so
/// a card asks only once per launch.
///
/// A photo without a clear color, and a photo that cannot be loaded, give `nil`; cards then use
/// the neutral dark panel. Failures are not remembered, so a later card may try again.
///
/// ```swift
/// .task(id: product.featuredImage?.url) {
///     tint = await ProductImageTint.shared.panel(for: product.featuredImage)
/// }
/// ```
public actor ProductImageTint {
    /// The tint shared by every screen.
    public static let shared = ProductImageTint()

    /// The width in pixels of the photo that is sampled; small enough to be cheap, large enough
    /// for the product's colors.
    static let sampledPixelWidth = 120
    /// The side of the square the photo is drawn into before its pixels are read.
    static let sampleSide = 24

    private let pipeline: ImagePipeline
    private var panels: [URL: RGBAColor?] = [:]

    /// Creates a tint loader.
    ///
    /// - Parameter pipeline: The image pipeline, the app's shared one by default.
    public init(pipeline: ImagePipeline = .shared) {
        self.pipeline = pipeline
    }

    /// The panel colors of `image`, or `nil` when it has no clear color or cannot be loaded.
    public func panel(for image: ShopifyImage?) async -> ProductPanelTint? {
        await panelColor(for: image).map(ProductPanelTint.init(color:))
    }

    /// The panel color of `image`, or `nil` when it has none or cannot be loaded.
    public func panelColor(for image: ShopifyImage?) async -> RGBAColor? {
        guard let url = image?.url else { return nil }
        if let known = panels[url] {
            return known
        }
        let request = KXImagePipeline.request(for: url, pixelWidth: Self.sampledPixelWidth, priority: .low)
        guard let photo = try? await pipeline.image(for: request) else { return nil }
        let panel = TintToken.panel(fromSamples: Self.samples(of: photo, side: Self.sampleSide))
        panels[url] = panel
        return panel
    }

    /// The colors of `image` drawn into a `side` by `side` square, one sample per pixel, with
    /// premultiplied alpha undone. Empty when the image has no bitmap.
    nonisolated static func samples(of image: UIImage, side: Int) -> [RGBAColor] {
        guard let cgImage = image.cgImage, side > 0 else { return [] }
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * bytesPerRow)
        let isDrawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard isDrawn else { return [] }
        return stride(from: 0, to: pixels.count, by: 4).map { index in
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0 else { return RGBAColor(red: 0, green: 0, blue: 0, alpha: 0) }
            return RGBAColor(
                red: min(Double(pixels[index]) / 255 / alpha, 1),
                green: min(Double(pixels[index + 1]) / 255 / alpha, 1),
                blue: min(Double(pixels[index + 2]) / 255 / alpha, 1),
                alpha: alpha
            )
        }
    }
}
