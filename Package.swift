// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCPermissionCenter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CCPermissionCenter",
            path: "Sources/CCPermissionCenter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ccpc-hook",
            path: "Sources/ccpc-hook",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
