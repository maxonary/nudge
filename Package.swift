// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NudgeAgentCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NudgeAgentCore", targets: ["NudgeAgentCore"])
    ],
    targets: [
        .target(
            name: "NudgeAgentCore",
            path: "Nudge/AgentAttention/Core"
        ),
        .testTarget(
            name: "NudgeAgentCoreTests",
            dependencies: ["NudgeAgentCore"],
            path: "Tests/NudgeAgentCoreTests"
        )
    ]
)
