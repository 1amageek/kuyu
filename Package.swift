// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "kuyu",
    platforms: [
        .macOS(.v26)
    ],
    products: [
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
        .package(path: "../kuyu-core"),
        .package(path: "../kuyu-physics"),
        .package(path: "../kuyu-scenarios"),
        .package(path: "../kuyu-training"),
        .package(path: "../kuyu-world-model"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(path: "../manas-training-data"),
        .package(path: "../manas"),
    ],
    targets: [
        .target(
            name: "KuyuMLX",
            dependencies: [
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
                .product(name: "KuyuTraining", package: "kuyu-training"),
                .product(name: "KuyuWorldModel", package: "kuyu-world-model"),
                .product(name: "ManasCore", package: "manas"),
                .product(name: "ManasMLXModels", package: "manas"),
                .product(name: "ManasMLXRuntime", package: "manas"),
                .product(name: "ManasMLXTraining", package: "manas"),
                .product(name: "ManasTrainingData", package: "manas-training-data"),
            ]
        ),
        .target(
            name: "KuyuUI",
            dependencies: [
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
                .product(name: "KuyuTraining", package: "kuyu-training"),
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
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
                .product(name: "KuyuTraining", package: "kuyu-training"),
                "KuyuMLX",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "kuyuTests",
            dependencies: [
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
                .product(name: "ManasMLXModels", package: "manas"),
                "KuyuMLX",
                "KuyuUI",
            ]
        ),
    ]
)
