// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RsyncGUI",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RsyncGUI", targets: ["RsyncGUI"])
    ],
    targets: [
        .executableTarget(
            name: "RsyncGUI",
            path: "Sources/RsyncGUI"
        ),
        .testTarget(
            name: "RsyncGUITests",
            dependencies: ["RsyncGUI"],
            path: "Tests/RsyncGUITests"
        )
    ]
)
