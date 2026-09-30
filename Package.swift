// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShixinDiskHealth",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "ShixinDiskHealthCore", targets: ["ShixinDiskHealthCore"]),
        .executable(name: "ShixinDiskHealth", targets: ["ShixinDiskHealth"]),
        .executable(name: "ShixinDiskHealthPrivilegedHelper", targets: ["ShixinDiskHealthPrivilegedHelper"]),
        .executable(name: "ShixinDiskHealthSelfTest", targets: ["ShixinDiskHealthSelfTest"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(
            name: "ShixinDiskHealthCore",
            path: "Sources/ShixinDiskHealthCore"
        ),
        .executableTarget(
            name: "ShixinDiskHealth",
            dependencies: ["ShixinDiskHealthCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/ShixinDiskHealth",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "ShixinDiskHealthPrivilegedHelper",
            dependencies: ["ShixinDiskHealthCore"],
            path: "Sources/ShixinDiskHealthPrivilegedHelper"
        ),
        .executableTarget(
            name: "ShixinDiskHealthSelfTest",
            dependencies: ["ShixinDiskHealthCore"],
            path: "Sources/ShixinDiskHealthSelfTest"
        ),
        .testTarget(
            name: "ShixinDiskHealthUpdateTests",
            dependencies: ["ShixinDiskHealth", "ShixinDiskHealthCore"],
            path: "Tests/ShixinDiskHealthUpdateTests"
        )
    ]
)
