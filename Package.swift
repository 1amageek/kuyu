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
        .executable(
            name: "kuyu-model-preview",
            targets: ["KuyuModelPreview"]
        ),
        .executable(
            name: "kuyu-simulator-preview",
            targets: ["KuyuSimulatorPreview"]
        ),
    ],
    dependencies: [
        .package(path: "../kuyu-core"),
        .package(path: "../embodiment-contract"),
        .package(path: "../kuyu-physics"),
        .package(path: "../kuyu-scenarios"),
        .package(path: "../kuyu-training"),
        .package(path: "../kuyu-mlx"),
        .package(url: "https://github.com/apple/swift-log", from: "1.13.1"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.1"),
    ],
    targets: [
        .target(
            name: "KuyuUI",
            dependencies: [
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "EmbodimentContract", package: "embodiment-contract"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
                .product(name: "KuyuTraining", package: "kuyu-training"),
                .product(name: "KuyuMLX", package: "kuyu-mlx"),
                .product(name: "KuyuMLXReferenceQuadrotor", package: "kuyu-mlx"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Configuration", package: "swift-configuration"),
            ],
            resources: [
                .copy("Resources/Models")
            ],
            swiftSettings: [
                // Ship the RealityKit 3D inspector as the baseline renderer (kuyu/SPEC.md
                // "Visual Inspection (Required)"). The `#else` 2D fallback remains for
                // environments that explicitly undefine this flag (e.g. headless builds).
                .define("KUYU_USE_REALITYVIEW")
            ]
        ),
        .executableTarget(
            name: "KuyuCLI",
            dependencies: [
                "KuyuUI",
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "EmbodimentContract", package: "embodiment-contract"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
                .product(name: "KuyuTraining", package: "kuyu-training"),
                .product(name: "KuyuMLX", package: "kuyu-mlx"),
                .product(name: "KuyuMLXCore", package: "kuyu-mlx"),
                .product(name: "KuyuMLXReferenceQuadrotor", package: "kuyu-mlx"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "KuyuModelPreview",
            dependencies: [
                "KuyuUI"
            ]
        ),
        .executableTarget(
            name: "KuyuSimulatorPreview",
            dependencies: [
                "KuyuUI"
            ]
        ),
        .testTarget(
            name: "kuyuTests",
            dependencies: [
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "EmbodimentContract", package: "embodiment-contract"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
                .product(name: "KuyuTraining", package: "kuyu-training"),
                .product(name: "KuyuMLX", package: "kuyu-mlx"),
                "KuyuUI",
            ]
        ),
    ]
)
