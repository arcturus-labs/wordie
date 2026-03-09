// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Wordie",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Wordie",
            path: "Sources/Wordie"
        ),
        .testTarget(
            name: "WordieTests",
            dependencies: ["Wordie"],
            path: "Tests/WordieTests"
        )
    ]
)
