// swift-tools-version: 6.0
import PackageDescription

/// Records the Storefront API fixtures of `Packages/ShopifyKit/Tests/ShopifyKitTests/Fixtures`
/// from the live store with the real `StorefrontClient`.
///
///     swift run fixture-recorder --output ../../Packages/ShopifyKit/Tests/ShopifyKitTests/Fixtures
let package = Package(
    name: "FixtureRecorder",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "fixture-recorder", targets: ["fixture-recorder"]),
    ],
    dependencies: [
        .package(path: "../../Packages/Core"),
        .package(path: "../../Packages/ShopifyKit"),
    ],
    targets: [
        .target(
            name: "FixtureRecording",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "ShopifyKit", package: "ShopifyKit"),
            ]
        ),
        .executableTarget(
            name: "fixture-recorder",
            dependencies: ["FixtureRecording"]
        ),
        .testTarget(
            name: "FixtureRecordingTests",
            dependencies: ["FixtureRecording"]
        ),
    ]
)
