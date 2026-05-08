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
        .executable(name: "circuit-studio-flow-runner", targets: ["CircuitStudioFlowRunner"]),
    ],
    dependencies: [
        .package(path: "../CoreSpice"),
        .package(path: "../semiconductor-layout"),
        .package(path: "../PEXEngine"),
    ],
    targets: [
        .target(
            name: "CircuitStudioCore",
            dependencies: [
                .product(name: "CoreSpice", package: "CoreSpice"),
                .product(name: "CoreSpiceIO", package: "CoreSpice"),
                .product(name: "PEXEngine", package: "PEXEngine"),
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
                .product(name: "LayoutEditor", package: "semiconductor-layout"),
                .product(name: "LayoutAutoGen", package: "semiconductor-layout"),
                .product(name: "LayoutCore", package: "semiconductor-layout"),
                .product(name: "LayoutTech", package: "semiconductor-layout"),
                .product(name: "LayoutIO", package: "semiconductor-layout"),
                .product(name: "LayoutVerify", package: "semiconductor-layout"),
            ]
        ),
        .executableTarget(
            name: "CircuitStudioFlowRunner",
            dependencies: [
                "CircuitStudioApp",
                "CircuitStudioCore",
                "SchematicEditor",
            ]
        ),
        .testTarget(
            name: "CircuitStudioCoreTests",
            dependencies: [
                "CircuitStudioCore",
                "SchematicEditor",
                "WaveformViewer",
                "CircuitStudioApp",
                .product(name: "PEXEngine", package: "PEXEngine"),
            ],
            resources: [
                .copy("Fixtures/virtual_pdk.json"),
                .copy("Fixtures/technology-package.json"),
                .copy("Fixtures/pdk"),
                .copy("Fixtures/signoff"),
                .copy("Fixtures/layout"),
                .copy("Fixtures/pex")
            ]
        ),
    ]
)
