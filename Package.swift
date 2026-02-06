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
            name: "KuyuCore",
            targets: ["KuyuCore"]
        ),
        .library(
            name: "KuyuProfiles",
            targets: ["KuyuProfiles"]
        ),
        .library(
            name: "KuyuMLX",
            targets: ["KuyuMLX"]
        ),
        .library(
            name: "KuyuUI",
            targets: ["KuyuUI"]
        ),
        .executable(
            name: "kuyu",
            targets: ["KuyuCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(path: "../manas"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "KuyuCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration"),
            ]
        ),
        .target(
            name: "KuyuProfiles",
            dependencies: [
                "KuyuCore",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration"),
            ]
        ),
        .target(
            name: "KuyuMLX",
            dependencies: [
                "KuyuCore",
                "KuyuProfiles",
                .product(name: "ManasCore", package: "manas"),
                .product(name: "ManasMLXModels", package: "manas"),
                .product(name: "ManasMLXRuntime", package: "manas"),
                .product(name: "ManasMLXTraining", package: "manas"),
            ]
        ),
        .target(
            name: "KuyuUI",
            dependencies: [
                "KuyuCore",
                "KuyuProfiles",
                "KuyuMLX",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration"),
            ],
            resources: [
                .copy("Resources/Models")
            ]
        ),
        .executableTarget(
            name: "KuyuCLI",
            dependencies: [
                "KuyuCore",
                "KuyuProfiles",
                "KuyuMLX",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "kuyuTests",
            dependencies: ["KuyuCore", "KuyuProfiles"]
        ),
    ]
)
