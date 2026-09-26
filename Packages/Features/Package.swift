// swift-tools-version: 6.0
import PackageDescription

/// One library per feature. A feature depends only on the shared layers
/// (`Core`, `DesignSystem`, `ShopifyKit`), never on another feature; the App
/// target composes them. New features (Product, Checkout, Licenses, Support,
/// Legal, Settings) are added here in the phase that implements them.
let featureNames = [
    "HomeFeature",
    "CatalogFeature",
    "SearchFeature",
    "CartFeature",
    "AccountFeature",
]

let package = Package(
    name: "Features",
    defaultLocalization: "de",
    platforms: [
        .iOS(.v17),
    ],
    products: featureNames.map { .library(name: $0, targets: [$0]) },
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../ShopifyKit"),
    ],
    targets: featureNames.map { name in
        .target(
            name: name,
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "ShopifyKit", package: "ShopifyKit"),
            ],
            resources: [.process("Resources")]
        )
    } + [
        .testTarget(
            name: "FeaturesTests",
            dependencies: featureNames.map { .byName(name: $0) }
        ),
    ]
)
