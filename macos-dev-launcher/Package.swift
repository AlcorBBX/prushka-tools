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
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.20.0")
    ],
    targets: [
        .target(
            name: "PrushkaDevCore",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
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
