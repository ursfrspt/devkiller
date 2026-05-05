// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "devkiller",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DevKillerCore", targets: ["DevKillerCore"]),
        .executable(name: "devkillerctl", targets: ["devkillerctl"]),
        .executable(name: "devkillerbar", targets: ["DevKillerBar"])
    ],
    targets: [
        .target(name: "DevKillerCore"),
        .executableTarget(
            name: "devkillerctl",
            dependencies: ["DevKillerCore"]
        ),
        .executableTarget(
            name: "DevKillerBar",
            dependencies: ["DevKillerCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DevKillerCoreTests",
            dependencies: ["DevKillerCore"]
        ),
        .testTarget(
            name: "DevKillerBarTests",
            dependencies: ["DevKillerBar"]
        )
    ]
)
