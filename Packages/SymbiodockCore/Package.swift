// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SymbiodockCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SymbiodockCore", targets: ["SymbiodockCore"]),
    ],
    targets: [
        .target(name: "SymbiodockCore"),
        .testTarget(name: "SymbiodockCoreTests", dependencies: ["SymbiodockCore"]),
    ]
)
