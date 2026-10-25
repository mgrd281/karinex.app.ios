// swift-tools-version: 6.0
import PackageDescription

/// The client of the KARINEX backend (BFF) on the fulfillment service: remote app config,
/// order delivery status, license keys, invoices, account deletion and device registration
/// (PROMPT.md 12). Foundation only, so it builds and tests on Linux like Core and ShopifyKit.
let package = Package(
    name: "Backend",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "BackendKit", targets: ["BackendKit"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "BackendKit",
            dependencies: [
                .product(name: "Core", package: "Core"),
            ]
        ),
        .testTarget(
            name: "BackendKitTests",
            dependencies: ["BackendKit"]
        ),
    ]
)
