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
            ]
        ),
        .testTarget(
            name: "CircuitStudioCoreTests",
            dependencies: ["CircuitStudioCore", "SchematicEditor"]
        ),
    ]
)
