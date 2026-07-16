// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "CircuitStudio",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CircuitStudioCore", targets: ["CircuitStudioCore"]),
        .library(name: "CircuitSignoff", targets: ["CircuitSignoff"]),
        .library(name: "SchematicEditor", targets: ["SchematicEditor"]),
        .library(name: "WaveformViewer", targets: ["WaveformViewer"]),
        .library(name: "CircuitArtifactRenderer", targets: ["CircuitArtifactRenderer"]),
        .library(name: "CircuitPhysicalDesign", targets: ["CircuitPhysicalDesign"]),
        .library(name: "CircuitStudioApp", targets: ["CircuitStudioApp"]),
        .library(name: "SignoffCLICore", targets: ["SignoffCLICore"]),
        .executable(name: "circuit-studio-flow-runner", targets: ["CircuitStudioFlowRunner"]),
        .executable(name: "signoff", targets: ["SignoffRunner"]),
    ],
    dependencies: [
        .package(path: "../Xcircuite"),
        .package(path: "../CircuiteFoundation"),
        .package(path: "../DesignFlowKernel"),
        .package(path: "../SignoffToolSupport"),
        .package(path: "../CoreSpice"),
        .package(path: "../semiconductor-layout"),
        .package(path: "../PEXEngine"),
        .package(
            url: "https://github.com/1amageek/swift-artifact.git",
            exact: "0.17.0"
        ),
        .package(path: "../swift-openvaf"),
        .package(
            url: "https://github.com/1amageek/mac-component.git",
            revision: "d3aee65b8dd73a838bcfba124e7c1afe520b97bb"
        ),
        .package(
            url: "https://github.com/1amageek/database-framework.git",
            exact: "26.0629.0",
            traits: ["SQLite"]
        ),
    ],
    targets: [
        .target(
            name: "CircuitStudioCore",
            dependencies: [
                .product(name: "CoreSpice", package: "CoreSpice"),
                .product(name: "CoreSpiceIO", package: "CoreSpice"),
                .product(name: "PEXEngine", package: "PEXEngine"),
                .product(name: "SignoffToolSupport", package: "SignoffToolSupport"),
                .product(name: "OpenVAFSupport", package: "swift-openvaf"),
                .product(name: "VerilogACompiler", package: "swift-openvaf"),
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
            name: "CircuitArtifactRenderer",
            dependencies: [
                "CircuitStudioCore",
                "WaveformViewer",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "CoreSpiceIO", package: "CoreSpice"),
                .product(name: "ArtifactCore", package: "swift-artifact"),
                .product(name: "ArtifactRenderer", package: "swift-artifact"),
                .product(name: "ArtifactView", package: "swift-artifact"),
            ]
        ),
        .target(
            name: "CircuitPhysicalDesign",
            dependencies: [
                "CircuitStudioCore",
                .product(name: "LayoutAutoGen", package: "semiconductor-layout"),
                .product(name: "LayoutCore", package: "semiconductor-layout"),
                .product(name: "LayoutTech", package: "semiconductor-layout"),
                .product(name: "LayoutVerify", package: "semiconductor-layout"),
                .product(name: "LayoutEngine", package: "semiconductor-layout"),
            ]
        ),
        .target(
            name: "Activity",
            dependencies: [
                .product(name: "Database", package: "database-framework"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "Xcircuite", package: "Xcircuite"),
            ]
        ),
        .target(
            name: "CircuitSignoff",
            dependencies: [
                "CircuitStudioCore",
                .product(name: "PEXEngine", package: "PEXEngine"),
                .product(name: "SignoffToolSupport", package: "SignoffToolSupport"),
            ],
            resources: [
                .copy("Resources/drc.tcl"),
                .copy("Resources/lvs.tcl"),
                .copy("Resources/extract_lvs.tcl"),
                .copy("Resources/materialize_cell.tcl"),
            ]
        ),
        .target(
            name: "CircuitStudioApp",
            dependencies: [
                "Activity",
                "CircuitSignoff",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "Xcircuite", package: "Xcircuite"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "PEXEngine", package: "PEXEngine"),
                .product(name: "SignoffToolSupport", package: "SignoffToolSupport"),
                "CircuitStudioCore",
                "CircuitPhysicalDesign",
                "CircuitArtifactRenderer",
                "SchematicEditor",
                "WaveformViewer",
                .product(name: "ArtifactView", package: "swift-artifact"),
                .product(name: "ArtifactNativeRenderer", package: "swift-artifact"),
                .product(name: "LayoutEditor", package: "semiconductor-layout"),
                .product(name: "LayoutAutoGen", package: "semiconductor-layout"),
                .product(name: "LayoutCore", package: "semiconductor-layout"),
                .product(name: "LayoutTech", package: "semiconductor-layout"),
                .product(name: "LayoutIO", package: "semiconductor-layout"),
                .product(name: "LayoutVerify", package: "semiconductor-layout"),
                .product(name: "LayoutEngine", package: "semiconductor-layout"),
                .product(name: "MacComponent", package: "mac-component"),
            ],
            resources: [
                .copy("Resources/antenna.tcl"),
                .copy("Resources/density.tcl"),
                .copy("Resources/layout-technology-catalog.json"),
                .copy("Resources/sky130-layout-tech.json"),
                .copy("Resources/sky130-tech-translation-profile.json"),
                .copy("Resources/sky130-standard-cell-layout-profile.json"),
                .copy("Resources/standard-cell-layout-profile-catalog.json"),
                .copy("Resources/sky130-layout-routing-profile.json"),
                .copy("Resources/sky130-signoff-rule-classification-profile.json"),
                .copy("Resources/timing-model-profile-catalog.json"),
                .copy("Resources/sky130-level1-device-model-profile.json"),
                .copy("Resources/sky130-level1-device-model-profile-ss.json"),
                .copy("Resources/sky130-level1-device-model-profile-ff.json"),
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
        .target(
            name: "SignoffCLICore",
            dependencies: [
                "CircuitSignoff",
                .product(name: "PEXEngine", package: "PEXEngine"),
            ],
            path: "Sources/SignoffRunner"
        ),
        .executableTarget(
            name: "SignoffRunner",
            dependencies: ["SignoffCLICore"],
            path: "Sources/SignoffRunnerEntry"
        ),
        .testTarget(
            name: "CircuitArtifactRendererTests",
            dependencies: [
                "CircuitArtifactRenderer",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "ArtifactCore", package: "swift-artifact"),
                .product(name: "ArtifactRenderer", package: "swift-artifact"),
            ]
        ),
        .testTarget(
            name: "CircuitStudioCoreTests",
            dependencies: [
                "CircuitStudioCore",
                "CircuitPhysicalDesign",
                "SchematicEditor",
                "WaveformViewer",
                "CircuitStudioApp",
                "CircuitSignoff",
                .product(name: "LayoutEditor", package: "semiconductor-layout"),
                .product(name: "LayoutCore", package: "semiconductor-layout"),
                .product(name: "LayoutEngine", package: "semiconductor-layout"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "Xcircuite", package: "Xcircuite"),
                .product(name: "OpenVAFSupport", package: "swift-openvaf"),
                .product(name: "VerilogACompiler", package: "swift-openvaf"),
                .product(name: "PEXEngine", package: "PEXEngine"),
                .product(name: "SignoffToolSupport", package: "SignoffToolSupport"),
            ],
            resources: [
                .copy("Fixtures/virtual_pdk.json"),
                .copy("Fixtures/technology-package.json"),
                .copy("Fixtures/pdk"),
                .copy("Fixtures/signoff"),
                .copy("Fixtures/layout"),
                .copy("Fixtures/pex"),
                .copy("Fixtures/magic"),
                .copy("Fixtures/lvs"),
            ]
        ),
        .testTarget(
            name: "SignoffCLITests",
            dependencies: [
                "CircuitSignoff",
                "SignoffCLICore",
            ],
            resources: [
                .copy("Fixtures/magic"),
                .copy("Fixtures/lvs"),
            ]
        ),
        .testTarget(
            name: "CircuitPhysicalDesignTests",
            dependencies: [
                "CircuitPhysicalDesign",
                "CircuitStudioCore",
                .product(name: "LayoutAutoGen", package: "semiconductor-layout"),
                .product(name: "LayoutCore", package: "semiconductor-layout"),
                .product(name: "LayoutEngine", package: "semiconductor-layout"),
                .product(name: "LayoutTech", package: "semiconductor-layout"),
                .product(name: "LayoutVerify", package: "semiconductor-layout"),
            ]
        ),
        .testTarget(
            name: "ActivityTests",
            dependencies: [
                "Activity",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
            ]
        ),
    ]
)
