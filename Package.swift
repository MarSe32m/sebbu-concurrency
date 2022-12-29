// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "sebbu-concurrency",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .library(
            name: "SebbuConcurrency",
            targets: ["SebbuConcurrency"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MarSe32m/sebbu-ts-ds.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-collections.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-atomics.git", branch: "main")
    ],
    targets: [
        .target(
            name: "SebbuConcurrency",
            dependencies: [.product(name: "SebbuTSDS", package: "sebbu-ts-ds"),
                           .product(name: "DequeModule", package: "swift-collections"),
                           .product(name: "Atomics", package: "swift-atomics", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .linux]))]),
        .testTarget(
            name: "SebbuConcurrencyTests",
            dependencies: ["SebbuConcurrency"]),
    ]
)
