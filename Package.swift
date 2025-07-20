// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RinhaBackend",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        // 🔴 Redis Swift client for high-performance state management
        .package(url: "https://github.com/vapor/redis.git", from: "4.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "RinhaBackend",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Redis", package: "redis"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RinhaBackendTests",
            dependencies: [
                .target(name: "RinhaBackend"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
] }
