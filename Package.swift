// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AerialDrop",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "AerialDrop", targets: ["AerialDrop"])
    ],
    targets: [
        .executableTarget(
            name: "AerialDrop",
            path: "Sources/AerialDrop"
        ),
        .testTarget(
            name: "AerialDropTests",
            dependencies: ["AerialDrop"],
            path: "Tests/AerialDropTests"
        )
    ]
)
