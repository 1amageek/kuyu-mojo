// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "kuyu-mojo",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .library(
      name: "KuyuMojoCore",
      targets: ["KuyuMojoCore"]
    ),
    .library(
      name: "KuyuMojoDynamics",
      targets: ["KuyuMojoDynamics"]
    ),
    .library(
      name: "KuyuManasMojoAdapter",
      targets: ["KuyuManasMojoAdapter"]
    ),
    .library(
      name: "KuyuMojoTrainingRuntime",
      targets: ["KuyuMojoTrainingRuntime"]
    ),
    .library(
      name: "KuyuMojoAcceleratorRuntime",
      targets: ["KuyuMojoAcceleratorRuntime"]
    ),
    .executable(
      name: "kuyu-mojo-accelerator-acceptance-fixture",
      targets: ["KuyuMojoAcceleratorAcceptanceFixture"]
    ),
  ],
  dependencies: [
    .package(path: "../kuyu-core"),
    .package(path: "../kuyu-physics"),
    .package(path: "../kuyu-training"),
    .package(path: "../manas"),
    .package(
      url: "https://github.com/1amageek/swift-mojo.git",
      revision: "d5f58340bdb6c69152a4ad8710dd8c5266b14e90"
    ),
  ],
  targets: [
    .binaryTarget(
      name: "SwiftMojo_KuyuMojoDynamics_ABI",
      path: "Generated/KuyuMojoDynamics/SwiftMojo_KuyuMojoDynamics_ABI.xcframework"
    ),
    .binaryTarget(
      name: "SwiftMojo_KuyuMojoDynamics_ABI_Linux",
      path: "Generated/KuyuMojoDynamics/SwiftMojo_KuyuMojoDynamics_ABI.artifactbundle"
    ),
    .target(
      name: "KuyuMojoCore",
      dependencies: [
        .product(name: "MojoRuntime", package: "swift-mojo")
      ]
    ),
    .target(
      name: "KuyuMojoDynamics",
      dependencies: [
        "KuyuMojoCore",
        .product(name: "KuyuCore", package: "kuyu-core"),
        .product(name: "KuyuPhysics", package: "kuyu-physics"),
        .product(name: "Mojo", package: "swift-mojo"),
        .target(
          name: "SwiftMojo_KuyuMojoDynamics_ABI",
          condition: .when(platforms: [.macOS])
        ),
        .target(
          name: "SwiftMojo_KuyuMojoDynamics_ABI_Linux",
          condition: .when(platforms: [.linux])
        ),
      ],
      plugins: [
        .plugin(
          name: "MojoBuildPlugin",
          package: "swift-mojo"
        )
      ]
    ),
    .target(
      name: "KuyuManasMojoAdapter",
      dependencies: [
        "KuyuMojoCore",
        "KuyuMojoAcceleratorRuntime",
        .product(name: "KuyuTrainingContracts", package: "kuyu-training"),
        .product(name: "KuyuTrainingValidation", package: "kuyu-training"),
        .product(name: "ManasLearningContracts", package: "manas"),
        .product(name: "ManasMojoModels", package: "manas"),
        .product(name: "ManasMojoRuntime", package: "manas"),
        .product(name: "ManasMojoOptimizer", package: "manas"),
        .product(name: "Mojo", package: "swift-mojo"),
      ]
    ),
    .target(
      name: "KuyuMojoTrainingRuntime",
      dependencies: [
        "KuyuMojoCore",
        .product(
          name: "KuyuTrainingRuntime",
          package: "kuyu-training"
        ),
      ]
    ),
    .target(
      name: "KuyuMojoAcceleratorRuntime",
      dependencies: [
        "KuyuMojoCore",
        .product(name: "Mojo", package: "swift-mojo"),
        .product(name: "MojoRuntime", package: "swift-mojo"),
      ]
    ),
    .executableTarget(
      name: "KuyuMojoAcceleratorAcceptanceFixture",
      dependencies: ["KuyuMojoCore", "KuyuMojoDynamics"]
    ),
    .testTarget(
      name: "KuyuMojoDynamicsTests",
      dependencies: [
        "KuyuMojoDynamics",
        "KuyuMojoCore",
        .product(name: "KuyuCore", package: "kuyu-core"),
        .product(name: "KuyuPhysics", package: "kuyu-physics"),
      ]
    ),
    .testTarget(
      name: "KuyuMojoCoreTests",
      dependencies: [
        "KuyuMojoCore",
        .product(name: "MojoRuntime", package: "swift-mojo"),
      ]
    ),
    .testTarget(
      name: "KuyuManasMojoAdapterTests",
      dependencies: [
        "KuyuManasMojoAdapter",
        "KuyuMojoAcceleratorRuntime",
        "KuyuMojoCore",
        .product(name: "KuyuTrainingContracts", package: "kuyu-training"),
        .product(name: "KuyuTrainingValidation", package: "kuyu-training"),
        .product(name: "ManasLearningContracts", package: "manas"),
        .product(name: "ManasMojoModels", package: "manas"),
        .product(name: "ManasMojoRuntime", package: "manas"),
        .product(name: "ManasMojoOptimizer", package: "manas"),
        .product(name: "Mojo", package: "swift-mojo"),
        .product(name: "MojoRuntime", package: "swift-mojo"),
      ]
    ),
    .testTarget(
      name: "KuyuMojoTrainingRuntimeTests",
      dependencies: [
        "KuyuMojoTrainingRuntime",
        "KuyuMojoCore",
        .product(name: "KuyuTraining", package: "kuyu-training"),
        .product(name: "MojoRuntime", package: "swift-mojo"),
      ]
    ),
    .testTarget(
      name: "KuyuMojoAcceleratorRuntimeTests",
      dependencies: [
        "KuyuMojoAcceleratorRuntime",
        "KuyuMojoCore",
        .product(name: "Mojo", package: "swift-mojo"),
        .product(name: "MojoRuntime", package: "swift-mojo"),
      ]
    ),
  ]
)
