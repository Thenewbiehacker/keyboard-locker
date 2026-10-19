// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyboardLocker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeyboardLocker",
            path: "Sources/KeyboardLocker",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
