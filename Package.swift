// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "firebreak",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FirebreakCore", targets: ["FirebreakCore"]),
        .executable(name: "firebreak", targets: ["firebreak"])
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
        .testTarget(
            name: "FirebreakCoreTests",
            dependencies: ["FirebreakCore"],
            path: "Tests/FirebreakCoreTests"
        )
    ]
)
