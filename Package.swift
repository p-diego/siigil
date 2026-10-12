// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Siigil",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Siigil"),
        .testTarget(name: "SiigilTests", dependencies: ["Siigil"]),
    ],
    swiftLanguageModes: [.v5]
)
