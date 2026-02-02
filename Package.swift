// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "kuyu",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "kuyu",
            targets: ["kuyu"]
        ),
        .library(
            name: "KuyuUI",
            targets: ["KuyuUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.0.2"),
        .package(path: "../manas"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "kuyu",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration"),
            ]
        ),
        .target(
            name: "KuyuUI",
            dependencies: [
                "kuyu",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "manas", package: "manas"),
                .product(name: "ManasMLX", package: "manas"),
            ],
            resources: [
                .copy("Resources/Models")
            ]
        ),
        .testTarget(
            name: "kuyuTests",
            dependencies: ["kuyu"]
        ),
    ]
)
