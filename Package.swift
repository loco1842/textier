// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "textier",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Textier", targets: ["Textier"]),
        .library(name: "TextierCore", targets: ["TextierCore"]),
    ],
    targets: [
        .target(name: "TextierCore"),
        .executableTarget(name: "Textier", dependencies: ["TextierCore"]),
        .testTarget(name: "TextierCoreTests", dependencies: ["TextierCore"]),
        .testTarget(name: "TextierAppTests", dependencies: ["Textier", "TextierCore"]),
    ]
)
