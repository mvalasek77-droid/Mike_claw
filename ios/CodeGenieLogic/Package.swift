// swift-tools-version:5.9
import PackageDescription

// The app's rules, without its screens.
//
// Every file under Sources/CodeGenieLogic is a symlink to the same file
// in the app target, so there is one copy of the logic and these tests
// exercise exactly what ships. The package has no UI dependencies, so
// `swift test` runs on macOS and Linux alike — including in CI, where
// there is no simulator.
let package = Package(
    name: "CodeGenieLogic",
    targets: [
        .target(name: "CodeGenieLogic"),
        .testTarget(name: "CodeGenieLogicTests", dependencies: ["CodeGenieLogic"]),
    ]
)
