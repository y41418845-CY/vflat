// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vFlat-iOS",
    defaultLocalization: "zh-Hant",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "vFlatCore",
            targets: ["vFlatCore"]
        ),
        .library(
            name: "vFlatUI",
            targets: ["vFlatUI"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "vFlatCore",
            dependencies: [],
            path: "Sources/Core",
            resources: [
                .process("Metal/Shaders.metal")
            ]
        ),
        .target(
            name: "vFlatUI",
            dependencies: ["vFlatCore"],
            path: "Sources/UI"
        ),
        .target(
            name: "vFlatApp",
            dependencies: ["vFlatCore", "vFlatUI"],
            path: "Sources/vFlatApp"
        ),
        .testTarget(
            name: "DewarpTests",
            dependencies: ["vFlatCore"],
            path: "Tests/DewarpTests"
        )
    ]
)
