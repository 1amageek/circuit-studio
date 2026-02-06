// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CircuitStudio",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CircuitStudioCore", targets: ["CircuitStudioCore"]),
        .library(name: "SchematicEditor", targets: ["SchematicEditor"]),
        .library(name: "WaveformViewer", targets: ["WaveformViewer"]),
        .library(name: "CircuitStudioApp", targets: ["CircuitStudioApp"]),
        .library(name: "LayoutCore", targets: ["LayoutCore"]),
        .library(name: "LayoutTech", targets: ["LayoutTech"]),
        .library(name: "LayoutVerify", targets: ["LayoutVerify"]),
        .library(name: "LayoutIO", targets: ["LayoutIO"]),
        .library(name: "LayoutIntegration", targets: ["LayoutIntegration"]),
        .library(name: "LayoutEditor", targets: ["LayoutEditor"]),
    ],
    dependencies: [
        .package(path: "../CoreSpice"),
    ],
    targets: [
        .target(
            name: "CircuitStudioCore",
            dependencies: [
                .product(name: "CoreSpice", package: "CoreSpice"),
                .product(name: "CoreSpiceIO", package: "CoreSpice"),
            ]
        ),
        .target(
            name: "LayoutCore",
            dependencies: []
        ),
        .target(
            name: "LayoutTech",
            dependencies: ["LayoutCore"]
        ),
        .target(
            name: "LayoutVerify",
            dependencies: ["LayoutCore", "LayoutTech"]
        ),
        .target(
            name: "LayoutIO",
            dependencies: ["LayoutCore", "LayoutTech"]
        ),
        .target(
            name: "LayoutIntegration",
            dependencies: ["LayoutCore", "LayoutTech", "LayoutIO", "LayoutVerify"]
        ),
        .target(
            name: "LayoutEditor",
            dependencies: ["LayoutCore", "LayoutTech", "LayoutVerify", "LayoutIO", "LayoutIntegration"]
        ),
        .target(
            name: "SchematicEditor",
            dependencies: ["CircuitStudioCore"]
        ),
        .target(
            name: "WaveformViewer",
            dependencies: ["CircuitStudioCore"]
        ),
        .target(
            name: "CircuitStudioApp",
            dependencies: [
                "CircuitStudioCore",
                "SchematicEditor",
                "WaveformViewer",
                "LayoutEditor",
            ]
        ),
        .testTarget(
            name: "CircuitStudioCoreTests",
            dependencies: ["CircuitStudioCore", "SchematicEditor"],
            resources: [
                .process("Tests/CircuitStudioCoreTests/Fixtures")
            ]
        ),
    ]
)
