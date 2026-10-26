// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "firebreak",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FirebreakCore", targets: ["FirebreakCore"]),
        .executable(name: "firebreak", targets: ["firebreak"]),
        .executable(name: "FirebreakApp", targets: ["FirebreakApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FirebreakNative",
            dependencies: [],
            path: "Sources/FirebreakNative",
            publicHeadersPath: "include"
        ),
        .target(
            name: "FirebreakCore",
            dependencies: ["FirebreakNative"],
            path: "Sources/FirebreakCore"
        ),
        .executableTarget(
            name: "firebreak",
            dependencies: ["FirebreakCore"],
            path: "Sources/firebreak"
        ),
        .executableTarget(
            name: "FirebreakApp",
            dependencies: ["FirebreakCore"],
            path: "Sources/FirebreakApp",
            exclude: ["Info.plist", "AppIcon.icns", "AppIcon.png", "Firebreak.entitlements", "Firebreak-AppStore.entitlements"]
        ),
        .testTarget(
            name: "FirebreakCoreTests",
            dependencies: ["FirebreakCore"],
            path: "Tests/FirebreakCoreTests"
        )
    ]
)
