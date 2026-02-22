// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CCXcodeConnect",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "XcodeConnectCore", targets: ["XcodeConnectCore"]),
        .executable(name: "cc-xcode-connect", targets: ["cc-xcode-connect"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "XcodeConnectCore",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "cc-xcode-connect",
            dependencies: [
                "XcodeConnectCore",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "XcodeConnectCoreTests",
            dependencies: ["XcodeConnectCore"]
        ),
    ]
)
