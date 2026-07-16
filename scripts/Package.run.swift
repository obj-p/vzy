// swift-tools-version: 6.0
import PackageDescription

// Run-only manifest staged as Package.swift in the release tarball's
// libexec tree. `vzy run` script builds resolve this instead of the
// repo manifest, so they never fetch swift-argument-parser (a
// dependency of the already-built CLI, not of VZYKit) and the tarball
// needs no Tests/ or Sources/vzy.
let package = Package(
    name: "vzy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VZYKit", targets: ["VZYKit"]),
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
    ]
)
