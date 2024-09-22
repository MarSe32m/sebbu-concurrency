// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "sebbu-concurrency",
    platforms: [.macOS("15.0"), .iOS("18.0")],
    products: [
        .library(
            name: "SebbuConcurrency",
            targets: ["SebbuConcurrency"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MarSe32m/sebbu-ts-ds.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-collections.git", branch: "main"),
    ],
    targets: [
        .target(name: "ConcurrencyRuntimeC"),
        .target(
            name: "SebbuConcurrency",
            dependencies: [.product(name: "SebbuTSDS", package: "sebbu-ts-ds"),
                           .product(name: "DequeModule", package: "swift-collections"),
                           .target(name: "ConcurrencyRuntimeC")]),
        .executableTarget(name: "DevelopmentTesting",
                          dependencies: [
                            .target(name: "SebbuConcurrency")
                          ]//,
        //swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "SebbuConcurrencyTests",
            dependencies: ["SebbuConcurrency"]),
    ]
)
