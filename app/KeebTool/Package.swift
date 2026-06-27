// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeebTool",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeebTool",
            path: "Sources/KeebTool",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Cocoa"),
            ]
        )
    ]
)
