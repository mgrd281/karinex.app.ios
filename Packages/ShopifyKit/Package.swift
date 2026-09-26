// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShopifyKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ShopifyKit", targets: ["ShopifyKit"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "ShopifyKit",
            dependencies: [
                .product(name: "Core", package: "Core"),
            ]
        ),
        .testTarget(
            name: "ShopifyKitTests",
            dependencies: ["ShopifyKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
