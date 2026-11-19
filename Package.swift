// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AerialDrop",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "AerialDrop", targets: ["AerialDrop"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "AerialDrop",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/AerialDrop",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "AerialDropTests",
            dependencies: ["AerialDrop"],
            path: "Tests/AerialDropTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
