// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogicCheck",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "LogicCheck", path: "Sources/LogicCheck"),
        .testTarget(name: "LogicCheckTests", dependencies: ["LogicCheck"], path: "Tests/LogicCheckTests")
    ]
)
