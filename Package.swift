// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tmrc",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "tmrc", targets: ["tmrc"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "tmrc",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/tmrc",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "tmrcTests",
            dependencies: [
                "tmrc",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/tmrcTests"
        ),
    ]
)
