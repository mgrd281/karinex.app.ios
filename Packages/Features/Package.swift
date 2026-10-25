// swift-tools-version: 6.0
import PackageDescription

/// One library per feature. A feature depends only on the shared layers
/// (`Core`, `DesignSystem`, `ShopifyKit`, `BackendKit`, `CommerceUI`), never on another
/// feature; the App target composes them.
let featureNames = [
    "HomeFeature",
    "CatalogFeature",
    "SearchFeature",
    "CartFeature",
    "AccountFeature",
    "ProductFeature",
    "CheckoutFeature",
    "LicensesFeature",
    "SupportFeature",
    "LegalFeature",
    "SettingsFeature",
]

/// Extra dependencies of single features. Only `CheckoutFeature` may import
/// Shopify Checkout Kit; every other module stays free of it.
let featureExtraDependencies: [String: [Target.Dependency]] = [
    "CheckoutFeature": [
        .product(name: "ShopifyCheckoutSheetKit", package: "checkout-sheet-kit-swift"),
    ],
]

/// The dependencies every feature shares.
let sharedFeatureDependencies: [Target.Dependency] = [
    .product(name: "Core", package: "Core"),
    .product(name: "DesignSystem", package: "DesignSystem"),
    .product(name: "ShopifyKit", package: "ShopifyKit"),
    .product(name: "BackendKit", package: "Backend"),
    .byName(name: "CommerceUI"),
]

let package = Package(
    name: "Features",
    defaultLocalization: "de",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "CommerceUI", targets: ["CommerceUI"]),
    ] + featureNames.map { .library(name: $0, targets: [$0]) },
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../ShopifyKit"),
        .package(path: "../Backend"),
        .package(url: "https://github.com/kean/Nuke", from: "13.2.0"),
        .package(url: "https://github.com/Shopify/checkout-sheet-kit-swift", from: "3.9.2"),
    ],
    targets: [
        // Shared commerce state and UI used by several features (cart, market, prices,
        // product cards, images, rich text, routes). Not a feature: features import it, it
        // imports no feature.
        .target(
            name: "CommerceUI",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignTokens", package: "DesignSystem"),
                .product(name: "ShopifyKit", package: "ShopifyKit"),
                .product(name: "BackendKit", package: "Backend"),
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
            ],
            resources: [.process("Resources")]
        ),
    ] + featureNames.map { name in
        .target(
            name: name,
            dependencies: sharedFeatureDependencies + (featureExtraDependencies[name] ?? []),
            resources: [.process("Resources")]
        )
    } + [
        .testTarget(
            name: "CommerceUITests",
            dependencies: [
                .byName(name: "CommerceUI"),
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "DesignTokens", package: "DesignSystem"),
                .product(name: "ShopifyKit", package: "ShopifyKit"),
                .product(name: "BackendKit", package: "Backend"),
            ]
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: featureNames.map { .byName(name: $0) } + [
                .byName(name: "CommerceUI"),
                .product(name: "Core", package: "Core"),
                .product(name: "ShopifyKit", package: "ShopifyKit"),
                .product(name: "BackendKit", package: "Backend"),
            ]
        ),
    ]
)
