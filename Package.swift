// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vzy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "vzy", targets: ["vzy"]),
        .library(name: "VZYKit", targets: ["VZYKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "VZYKitObjC",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Virtualization"),
            ]
        ),
        .target(
            name: "VZYKit",
            dependencies: ["VZYKitObjC"]
        ),
        .executableTarget(
            name: "vzy",
            dependencies: [
                "VZYKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "VZYKitTests",
            dependencies: ["VZYKit"]
        ),
    ]
)
