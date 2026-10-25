import SwiftUI

extension View {
    /// Presents product photography on the light grey photo background (`imageBackground`), the
    /// way fashion retail apps show their products.
    ///
    /// The photo is multiplied onto the tile, so the white studio background of a shot takes the
    /// tile color and the product sits in the tile without a visible white box. Colors of the
    /// product itself change by only a few percent. The tile stays light in dark mode, because the
    /// store's photos are shot on white.
    ///
    /// Image views inside the tile (``KXProductImage`` and the app's remote product images) read
    /// ``EnvironmentValues/kxIsInPhotoTile`` and leave the plain tile visible while loading
    /// instead of drawing a skeleton.
    ///
    /// ```swift
    /// ProductImage(product.featuredImage, isDecorative: true)
    ///     .kxPhotoTile()
    ///     .aspectRatio(1, contentMode: .fit)
    /// ```
    public func kxPhotoTile() -> some View {
        environment(\.kxIsInPhotoTile, true)
            .blendMode(.multiply)
            .background(KXColor.imageBackground)
            .compositingGroup()
    }
}

// MARK: - Environment

private struct KXPhotoTileKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the view is drawn inside a ``SwiftUICore/View/kxPhotoTile()``. Image views use it
    /// to show only the tile while loading, and the `imageIcon` symbol when a photo is missing.
    public var kxIsInPhotoTile: Bool {
        get { self[KXPhotoTileKey.self] }
        set { self[KXPhotoTileKey.self] = newValue }
    }
}
