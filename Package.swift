// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoCI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AutoCICore"),
        .executableTarget(name: "auto-ci", dependencies: ["AutoCICore"]),
        .testTarget(name: "AutoCICoreTests", dependencies: ["AutoCICore"]),
    ]
)
