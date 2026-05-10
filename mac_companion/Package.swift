// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodeGenieCompanion",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "codegenie-companion", targets: ["CodeGenieCompanion"]),
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
