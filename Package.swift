// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "kuyu-app",
    platforms: [
        .macOS(.v26)
    ],
    products: [
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
        .package(path: "../kuyu-core"),
        .package(path: "../kuyu-physics"),
        .package(path: "../kuyu-scenarios"),
        .package(path: "../kuyu-training"),
        .package(path: "../kuyu-mlx"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "KuyuUI",
            dependencies: [
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
                .product(name: "KuyuTraining", package: "kuyu-training"),
                .product(name: "KuyuMLX", package: "kuyu-mlx"),
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
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
                .product(name: "KuyuTraining", package: "kuyu-training"),
                .product(name: "KuyuMLX", package: "kuyu-mlx"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "kuyuTests",
            dependencies: [
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
                .product(name: "KuyuTraining", package: "kuyu-training"),
                .product(name: "KuyuMLX", package: "kuyu-mlx"),
                "KuyuUI",
            ]
        ),
    ]
)
