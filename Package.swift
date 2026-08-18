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
    targets: [
        .target(
            name: "ShixinDiskHealthCore",
            path: "Sources/ShixinDiskHealthCore"
        ),
        .executableTarget(
            name: "ShixinDiskHealth",
            dependencies: ["ShixinDiskHealthCore"],
            path: "Sources/ShixinDiskHealth",
            resources: [
                .copy("Resources")
            ]
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
        )
    ]
)
