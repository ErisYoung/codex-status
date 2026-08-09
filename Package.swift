// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexStatus",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexStatusCore", targets: ["CodexStatusCore"]),
        .executable(name: "CodexStatus", targets: ["CodexStatus"]),
        .executable(name: "CodexStatusCoreTestsRunner", targets: ["CodexStatusCoreTestsRunner"])
    ],
    targets: [
        .target(name: "CodexStatusCore"),
        .executableTarget(
            name: "CodexStatus",
            dependencies: ["CodexStatusCore"]
        ),
        .executableTarget(
            name: "CodexStatusCoreTestsRunner",
            dependencies: ["CodexStatusCore"]
        )
    ]
)
