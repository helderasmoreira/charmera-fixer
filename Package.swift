// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CharmeraFixer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CharmeraFixer"),
        .testTarget(name: "CharmeraFixerTests", dependencies: ["CharmeraFixer"]),
    ],
    swiftLanguageModes: [.v5]
)
