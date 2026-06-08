// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeGenieTerminalRunner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "codegenie-terminal-runner", targets: ["CodeGenieCompanion"]),
    ],
    targets: [
        .executableTarget(
            name: "CodeGenieCompanion",
            path: "Sources/CodeGenieCompanion"
        ),
        .testTarget(
            name: "CodeGenieCompanionTests",
            dependencies: ["CodeGenieCompanion"],
            path: "Tests/CodeGenieCompanionTests"
        ),
    ]
)
