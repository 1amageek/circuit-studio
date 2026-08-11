// swift-tools-version: 6.3
import PackageDescription

func releasedDependency(named name: String, exactVersion: Version) -> Package.Dependency {
    .package(
        url: "https://github.com/1amageek/\(name).git",
        exact: exactVersion
    )
}

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
        releasedDependency(
            named: "Xcircuite",
            exactVersion: "26.812.0"
        ),
        releasedDependency(
            named: "CircuiteFoundation",
            exactVersion: "26.812.0"
        ),
        releasedDependency(
            named: "DesignFlowKernel",
            exactVersion: "26.812.0"
        ),
        releasedDependency(
            named: "SignoffToolSupport",
            exactVersion: "26.812.0"
        ),
        releasedDependency(
            named: "CoreSpice",
            exactVersion: "26.812.0"
        ),
        releasedDependency(
            named: "semiconductor-layout",
            exactVersion: "26.812.0"
        ),
        releasedDependency(
            named: "PEXEngine",
            exactVersion: "26.812.0"
        ),
        releasedDependency(
            named: "DRCEngine",
            exactVersion: "26.812.0"
        ),
        releasedDependency(
            named: "LVSEngine",
            exactVersion: "26.812.0"
        ),
        releasedDependency(
            named: "TimingEngine",
            exactVersion: "26.812.0"
        ),
        releasedDependency(
            named: "ReleaseEngine",
            exactVersion: "26.812.0"
        ),
        .package(
            url: "https://github.com/1amageek/swift-artifact.git",
            exact: "0.17.0"
        ),
        releasedDependency(
            named: "swift-openvaf",
            exactVersion: "26.812.0"
        ),
        .package(
            url: "https://github.com/1amageek/mac-component.git",
            exact: "0.1.0"
        ),
        .package(
            url: "https://github.com/1amageek/database-framework.git",
            exact: "26.0809.1",
            traits: ["SQLite"]
        ),
        .package(
            url: "https://github.com/1amageek/database-kit.git",
            exact: "26.0809.4"
        ),
    ],
    targets: [
        .target(
            name: "CircuitStudioCore",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
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
                "CircuitSignoff",
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
                .product(name: "DatabaseKitFoundation", package: "database-kit"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "Xcircuite", package: "Xcircuite"),
            ]
        ),
        .target(
            name: "CircuitSignoff",
            dependencies: [
                "CircuitStudioCore",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
                .product(name: "DRCAdapters", package: "DRCEngine"),
                .product(name: "DRCCore", package: "DRCEngine"),
                .product(name: "DRCPersistence", package: "DRCEngine"),
                .product(name: "LVSAdapters", package: "LVSEngine"),
                .product(name: "LVSCore", package: "LVSEngine"),
                .product(name: "LVSExtractionAdapters", package: "LVSEngine"),
                .product(name: "LVSPersistence", package: "LVSEngine"),
                .product(name: "PEXEngine", package: "PEXEngine"),
                .product(name: "PEXPersistence", package: "PEXEngine"),
                .product(name: "SignoffToolSupport", package: "SignoffToolSupport"),
            ],
            resources: [
                .copy("Resources/materialize_cell.tcl"),
            ]
        ),
        .target(
            name: "CircuitStudioApp",
            dependencies: [
                "Activity",
                "CircuitSignoff",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFileSystem", package: "CircuiteFoundation"),
                .product(name: "Xcircuite", package: "Xcircuite"),
                .product(name: "XcircuiteFlowCLISupport", package: "Xcircuite"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "DRCAdapters", package: "DRCEngine"),
                .product(name: "DRCCore", package: "DRCEngine"),
                .product(name: "LVSAdapters", package: "LVSEngine"),
                .product(name: "LVSCore", package: "LVSEngine"),
                .product(name: "STAEngine", package: "TimingEngine"),
                .product(name: "TimingEngine", package: "TimingEngine"),
                .product(name: "TimingCore", package: "TimingEngine"),
                .product(name: "ReleaseCore", package: "ReleaseEngine"),
                .product(name: "SignoffEngine", package: "ReleaseEngine"),
                .product(name: "TapeoutEngine", package: "ReleaseEngine"),
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
                .product(name: "DRCAdapters", package: "DRCEngine"),
                .product(name: "LVSAdapters", package: "LVSEngine"),
                .product(name: "LVSCore", package: "LVSEngine"),
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
            name: "CircuitSignoffTests",
            dependencies: [
                "CircuitSignoff",
                .product(name: "DRCCore", package: "DRCEngine"),
                .product(name: "LVSCore", package: "LVSEngine"),
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
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFileSystem", package: "CircuiteFoundation"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "DRCAdapters", package: "DRCEngine"),
                .product(name: "DRCCore", package: "DRCEngine"),
                .product(name: "LVSAdapters", package: "LVSEngine"),
                .product(name: "LVSCore", package: "LVSEngine"),
                .product(name: "LVSExtractionAdapters", package: "LVSEngine"),
                .product(name: "STAEngine", package: "TimingEngine"),
                .product(name: "TimingEngine", package: "TimingEngine"),
                .product(name: "TimingCore", package: "TimingEngine"),
                .product(name: "ReleaseCore", package: "ReleaseEngine"),
                .product(name: "SignoffEngine", package: "ReleaseEngine"),
                .product(name: "TapeoutEngine", package: "ReleaseEngine"),
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
