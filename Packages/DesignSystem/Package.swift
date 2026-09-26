// swift-tools-version: 6.0
import PackageDescription

// `DesignTokens` is pure Swift (no UI frameworks) so its values and the WCAG
// contrast checks can be built and tested on any platform, including Linux CI.
// `DesignSystem` (SwiftUI components) is only declared on Apple platforms.
var products: [Product] = [
    .library(name: "DesignTokens", targets: ["DesignTokens"]),
]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "DesignTokens"),
    .testTarget(name: "DesignTokensTests", dependencies: ["DesignTokens"]),
]

#if !os(Linux)
products.append(.library(name: "DesignSystem", targets: ["DesignSystem"]))
dependencies.append(
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.6")
)
targets.append(contentsOf: [
    .target(
        name: "DesignSystem",
        dependencies: ["DesignTokens"],
        resources: [.process("Resources")]
    ),
    .testTarget(
        name: "DesignSystemTests",
        dependencies: [
            "DesignSystem",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        ],
        exclude: ["__Snapshots__"]
    ),
])
#endif

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "de",
    platforms: [
        .iOS(.v17),
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
