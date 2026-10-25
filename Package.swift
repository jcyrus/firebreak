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
            name: "FirebreakCore",
            dependencies: [],
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
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "FirebreakCoreTests",
            dependencies: ["FirebreakCore"],
            path: "Tests/FirebreakCoreTests"
        )
    ]
)
