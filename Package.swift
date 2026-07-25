// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot
        .appendingPathComponent("docs")
        .appendingPathComponent("workspace-packages.json")
        .path
)

func workspaceDependency(named name: String, revision: String) -> Package.Dependency {
    let siblingManifest = workspaceRoot
        .appendingPathComponent(name)
        .appendingPathComponent("Package.swift")

    if isLSIWorkspace,
       FileManager.default.fileExists(atPath: siblingManifest.path) {
        return .package(path: "../\(name)")
    }

    return .package(
        url: "https://github.com/1amageek/\(name).git",
        revision: revision
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
        workspaceDependency(
            named: "Xcircuite",
            revision: "62bf4ea335e0c63d26b1b25fd185f1469e17aebd"
        ),
        workspaceDependency(
            named: "CircuiteFoundation",
            revision: "7abcac83517935c9b9f7553d7016d62cffde259d"
        ),
        workspaceDependency(
            named: "DesignFlowKernel",
            revision: "6bbe1a24bc7e0a983da747844d8b2db1c80fefd4"
        ),
        workspaceDependency(
            named: "SignoffToolSupport",
            revision: "6bf675eecb27e3bd3440c5ce8a85c85c510fc3cb"
        ),
        workspaceDependency(
            named: "CoreSpice",
            revision: "dec08bf9dc955b0845800765be0b6172d64b1609"
        ),
        workspaceDependency(
            named: "semiconductor-layout",
            revision: "692a056d21b6e292c29215f76c3ae225215d03c2"
        ),
        workspaceDependency(
            named: "PEXEngine",
            revision: "ba10c1fe0b847d5816faef4eae67c64a19d61e1e"
        ),
        workspaceDependency(
            named: "DRCEngine",
            revision: "e6a0fa2c5b64de1b4ef81e651bd1bb77ecc77299"
        ),
        workspaceDependency(
            named: "LVSEngine",
            revision: "f79b52da83146c108e0a122f4581fe93fae59527"
        ),
        workspaceDependency(
            named: "TimingEngine",
            revision: "2b8f0df3e359fca274edc8ede176457de40e1648"
        ),
        workspaceDependency(
            named: "ReleaseEngine",
            revision: "be52779216b055914fe02063862941c88a227498"
        ),
        .package(
            url: "https://github.com/1amageek/swift-artifact.git",
            exact: "0.17.0"
        ),
        workspaceDependency(
            named: "swift-openvaf",
            revision: "9d2cb7607b825d36b1be92565d4dc6caedea0999"
        ),
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
