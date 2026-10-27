// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PrushkaDev",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PrushkaDev", targets: ["PrushkaDev"])
    ],
    targets: [
        .target(
            name: "PrushkaDevCore",
            path: "Sources/PrushkaDev"
        ),
        .executableTarget(
            name: "PrushkaDev",
            dependencies: ["PrushkaDevCore"],
            path: "Sources/PrushkaDevApp"
        ),
        .testTarget(
            name: "PrushkaDevCoreTests",
            dependencies: ["PrushkaDevCore"],
            path: "Tests/PrushkaDevCoreTests"
        )
    ]
)
