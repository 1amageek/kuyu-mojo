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
    ],
    dependencies: [
        .package(path: "../kuyu-core"),
        .package(path: "../kuyu-physics"),
        .package(
            url: "https://github.com/1amageek/swift-mojo.git",
            revision: "438e2ab3aa23e2e140ba643b96910f918411d83f"
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
            name: "KuyuMojoCore"
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
        .testTarget(
            name: "KuyuMojoDynamicsTests",
            dependencies: [
                "KuyuMojoDynamics",
                "KuyuMojoCore",
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
            ]
        ),
    ]
)
