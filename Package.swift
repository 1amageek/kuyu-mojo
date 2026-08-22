// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "kuyu-mojo",
    platforms: [
        .macOS(.v26),
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
            name: "KuyuMojoTrainingRuntime",
            targets: ["KuyuMojoTrainingRuntime"]
        ),
        .executable(
            name: "kuyu-mojo-metal-acceptance-fixture",
            targets: ["KuyuMojoMetalAcceptanceFixture"]
        ),
    ],
    dependencies: [
        .package(path: "../kuyu-core"),
        .package(path: "../kuyu-physics"),
        .package(path: "../kuyu-training"),
        .package(
            url: "https://github.com/1amageek/swift-mojo.git",
            revision: "4a2382cc6e06cd4f5fe9f888474e3fa235a1acc1"
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
                .product(name: "MojoRuntime", package: "swift-mojo"),
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
                ),
            ]
        ),
        .target(
            name: "KuyuMojoTrainingRuntime",
            dependencies: [
                "KuyuMojoCore",
                .product(name: "KuyuTraining", package: "kuyu-training"),
            ]
        ),
        .executableTarget(
            name: "KuyuMojoMetalAcceptanceFixture",
            dependencies: ["KuyuMojoDynamics"]
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
            name: "KuyuMojoTrainingRuntimeTests",
            dependencies: [
                "KuyuMojoTrainingRuntime",
                "KuyuMojoCore",
                .product(name: "KuyuTraining", package: "kuyu-training"),
                .product(name: "MojoRuntime", package: "swift-mojo"),
            ]
        ),
    ]
)
