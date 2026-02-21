// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "XcodeIDEAdapter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IDEAdapterCore", targets: ["IDEAdapterCore"]),
        .executable(name: "xcode-ide-adapter", targets: ["xcode-ide-adapter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(
            name: "IDEAdapterCore",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),
        .executableTarget(
            name: "xcode-ide-adapter",
            dependencies: ["IDEAdapterCore"]
        ),
    ]
)
