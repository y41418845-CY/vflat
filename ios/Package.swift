// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vFlat",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "vFlat", targets: ["vFlat"])
    ],
    targets: [
        .target(
            name: "vFlat",
            path: "Sources"
        )
    ]
)
