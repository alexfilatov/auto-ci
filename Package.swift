// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoCI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AutoCICore"),
        .executableTarget(name: "auto-ci", dependencies: ["AutoCICore"]),
        .executableTarget(
            name: "AutoCIApp",
            dependencies: ["AutoCICore"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("UserNotifications")]
        ),
        .testTarget(name: "AutoCICoreTests", dependencies: ["AutoCICore"]),
    ]
)
