// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ai-swift-ui",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "AISwiftUI",
            targets: ["AISwiftUI"]
        ),
    ],
    targets: [
        .target(
            name: "AISwiftUI",
            path: "Sources/AISwiftUI"
        ),
        .testTarget(
            name: "AISwiftUITests",
            dependencies: ["AISwiftUI"],
            path: "Tests/AISwiftUITests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
