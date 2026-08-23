// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "kuyu-app",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .library(
      name: "KuyuTrainingApplication",
      targets: ["KuyuTrainingApplication"]
    ),
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
      name: "kuyu-inspection-preview",
      targets: ["KuyuInspectionPreview"]
    ),
  ],
  dependencies: [
    .package(path: "../kuyu-core"),
    .package(path: "../kuyu-physics"),
    .package(path: "../kuyu-scenarios"),
    .package(path: "../kuyu-training"),
    .package(path: "../kuyu-mojo"),
    .package(
      url: "https://github.com/apple/swift-argument-parser",
      from: "1.8.1"
    ),
  ],
  targets: [
    .target(
      name: "KuyuTrainingApplication",
      dependencies: [
        .product(name: "KuyuTraining", package: "kuyu-training")
      ]
    ),
    .target(
      name: "KuyuUI",
      dependencies: [
        "KuyuTrainingApplication",
        .product(name: "KuyuCore", package: "kuyu-core"),
        .product(name: "KuyuPhysics", package: "kuyu-physics"),
        .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
        .product(name: "KuyuTrainingContracts", package: "kuyu-training"),
      ],
      resources: [
        .copy("Resources/Models")
      ],
      swiftSettings: [
        .define("KUYU_USE_REALITYVIEW")
      ]
    ),
    .executableTarget(
      name: "KuyuCLI",
      dependencies: [
        "KuyuTrainingApplication",
        .product(name: "KuyuCore", package: "kuyu-core"),
        .product(name: "KuyuMojoTrainingRuntime", package: "kuyu-mojo"),
        .product(name: "KuyuPhysics", package: "kuyu-physics"),
        .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
        .product(name: "KuyuTrainingContracts", package: "kuyu-training"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .executableTarget(
      name: "KuyuInspectionPreview",
      dependencies: [
        "KuyuTrainingApplication",
        "KuyuUI",
        .product(name: "KuyuMojoTrainingRuntime", package: "kuyu-mojo"),
      ]
    ),
    .executableTarget(
      name: "KuyuModelPreview",
      dependencies: ["KuyuUI"]
    ),
    .testTarget(
      name: "KuyuApplicationTests",
      dependencies: [
        "KuyuTrainingApplication",
        .product(name: "KuyuTrainingContracts", package: "kuyu-training"),
      ]
    ),
  ]
)
