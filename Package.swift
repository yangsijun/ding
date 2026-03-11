// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ding",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "ding",
            dependencies: [
                "DingCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ding"
        ),
        .target(
            name: "DingCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/DingCore"
        ),
        .testTarget(
            name: "DingTests",
            dependencies: ["DingCore"],
            path: "Tests/DingTests"
        ),
    ]
)
