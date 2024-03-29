// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "sebbu-concurrency",
    platforms: [.macOS("14.0"), .iOS("17.0")],
    products: [
        .library(
            name: "SebbuConcurrency",
            targets: ["SebbuConcurrency"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MarSe32m/sebbu-ts-ds.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-collections.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.1.0")
    ],
    targets: [
        .target(name: "ConcurrencyRuntimeC"),
        .target(
            name: "SebbuConcurrency",
            dependencies: [.product(name: "SebbuTSDS", package: "sebbu-ts-ds"),
                           .product(name: "DequeModule", package: "swift-collections"),
                           .product(name: "Atomics", package: "swift-atomics", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .linux])),
                           .target(name: "ConcurrencyRuntimeC")],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-disable-availability-checking"])]),
        .executableTarget(name: "DevelopmentTesting",
                          dependencies: [
                            .target(name: "SebbuConcurrency")
                          ]),
        .testTarget(
            name: "SebbuConcurrencyTests",
            dependencies: ["SebbuConcurrency"]),
    ]
)
