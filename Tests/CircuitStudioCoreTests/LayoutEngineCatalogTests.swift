import CoreGraphics
import Foundation
import CircuitPhysicalDesign
import Testing
import CircuitStudioCore
import LayoutAutoGen
import LayoutCore
import LayoutEngine
import LayoutTech
@testable import CircuitStudioApp

@Suite("Layout Engine Catalog")
struct LayoutEngineCatalogTests {

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func circuitLayoutUsesRegisteredPlacementEngine() throws {
        let registry = CircuitPhysicalDesignDefaults.layoutEngineCatalog().registering(
            PlacementEngineRegistration(
                descriptor: LayoutEngineDescriptor(
                    id: "test-fixed-placement",
                    name: "Test Fixed Placement",
                    version: "1.0",
                    role: .placement,
                    summary: "Places every instance at a fixed coordinate.",
                    isDeterministic: true,
                    source: "test"
                ),
                makeEngine: { _ in FixedPlacementEngine() }
            )
        )

        let output = try CircuitLayoutSynthesizer(layoutEngineCatalog: registry).generate(
            from: singleResistorSchematic(),
            catalog: .standard(),
            placementStrategy: .registered("test-fixed-placement")
        )

        let topCellID = try #require(output.document.topCellID)
        let top = try #require(output.document.cell(withID: topCellID))
        let instance = try #require(top.instances.first { $0.name == "R1" })
        #expect(instance.transform.translation == FixedPlacementEngine.translation)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func circuitLayoutUsesRegisteredRoutingEngine() throws {
        let registry = CircuitPhysicalDesignDefaults.layoutEngineCatalog().registering(
            RoutingEngineRegistration(
                descriptor: LayoutEngineDescriptor(
                    id: "test-routing-sentinel",
                    name: "Test Routing Sentinel",
                    version: "1.0",
                    role: .routing,
                    summary: "Reports a sentinel unrouted net for selection testing.",
                    isDeterministic: true,
                    source: "test"
                ),
                makeEngine: { SentinelRoutingEngine() }
            )
        )

        let output = try CircuitLayoutSynthesizer(layoutEngineCatalog: registry).generate(
            from: singleResistorSchematic(),
            catalog: .standard(),
            routingStrategy: .registered("test-routing-sentinel")
        )

        #expect(output.unroutedNets == [SentinelRoutingEngine.unroutedNetName])
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func unknownRegisteredPlacementEngineFailsBeforeLayoutOutput() throws {
        do {
            _ = try CircuitLayoutSynthesizer().generate(
                from: singleResistorSchematic(),
                catalog: .standard(),
                placementStrategy: .registered("missing-placement")
            )
            Issue.record("Expected unknown placement engine to fail.")
        } catch let error as LayoutEngineCatalogError {
            guard case .unknownPlacementEngine(let id, let availableIDs) = error else {
                Issue.record("Expected an unknown placement engine error.")
                return
            }
            #expect(id == "missing-placement")
            #expect(Set(availableIDs) == Set(["greedy", "optimized"]))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func availabilityUsesRegisteredDeviceCellGenerator() {
        var catalog = DeviceCatalog()
        catalog.register(DeviceKind(
            id: "test_device",
            displayName: "Test Device",
            category: .passive,
            spicePrefix: "X",
            portDefinitions: [
                PortDefinition(id: "A", displayName: "A", position: .zero),
                PortDefinition(id: "B", displayName: "B", position: .zero),
            ],
            parameterSchema: [],
            symbol: SymbolDefinition(
                shape: .ic(width: 40, height: 20),
                size: CGSize(width: 40, height: 20),
                iconName: "square"
            )
        ))
        let document = SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "test_device",
                name: "X1",
                position: .zero
            ),
        ])

        let unavailable = CircuitLayoutAvailability.evaluate(
            document: document,
            catalog: catalog,
            deviceCellEngines: LayoutEngineCatalog.standard(),
            activeCellName: "TOP"
        )
        #expect(!unavailable.isAvailable)
        #expect(unavailable.code == .unsupportedPhysicalDevice)

        let engineCatalog = LayoutEngineCatalog.standard().registering(
            DeviceCellEngineRegistration(
                descriptor: LayoutEngineDescriptor(
                    id: "test-device-generator",
                    name: "Test Device Generator",
                    version: "1.0",
                    role: .deviceCellGeneration,
                    summary: "Generates a synthetic passive device.",
                    isDeterministic: true,
                    source: "test"
                ),
                supportedCanonicalDeviceKindIDs: ["test_device"],
                makeGenerator: { TestDeviceCellGenerator() }
            )
        )

        let available = CircuitLayoutAvailability.evaluate(
            document: document,
            catalog: catalog,
            deviceCellEngines: engineCatalog,
            activeCellName: "TOP"
        )
        #expect(available.isAvailable)
    }
}

private func singleResistorSchematic() -> SchematicDocument {
    SchematicDocument(components: [
        PlacedComponent(
            deviceKindID: "resistor",
            name: "R1",
            position: .zero,
            parameters: ["r": 1000]
        ),
    ])
}

private struct FixedPlacementEngine: PlacementEngine {
    static let translation = LayoutPoint(x: 42, y: 24)

    func place(
        instances: [PlacementInstance],
        nets: [PlacementNet],
        tech: LayoutTechDatabase
    ) throws -> PlacementResult {
        PlacementResult(
            placements: Dictionary(
                uniqueKeysWithValues: instances.map {
                    ($0.id, LayoutTransform(translation: Self.translation))
                }
            ),
            powerRails: [],
            totalBoundingBox: LayoutRect(
                origin: Self.translation,
                size: LayoutSize(width: 20, height: 20)
            )
        )
    }
}

private struct SentinelRoutingEngine: RoutingEngine {
    static let unroutedNetName = "sentinel-unrouted"

    func route(
        nets: [RoutingNet],
        placements: [UUID: LayoutTransform],
        cells: [UUID: LayoutCell],
        obstructions: [LayoutShape],
        tech: LayoutTechDatabase
    ) throws -> RoutingResult {
        RoutingResult(routes: [], unroutedNets: [Self.unroutedNetName])
    }
}

private struct TestDeviceCellGenerator: DeviceCellGenerator {
    let supportedDeviceKindIDs = ["test_device"]

    func generateCell(
        deviceKindID: String,
        instanceName: String,
        parameters: [String: Double],
        tech: LayoutTechDatabase
    ) throws -> LayoutCell {
        LayoutCell(
            name: "test-device",
            pins: [
                LayoutPin(
                    name: "A",
                    position: LayoutPoint(x: 0, y: 0),
                    size: LayoutSize(width: 0.2, height: 0.2),
                    layer: LayoutLayerID(name: "M1", purpose: "drawing")
                ),
                LayoutPin(
                    name: "B",
                    position: LayoutPoint(x: 1, y: 0),
                    size: LayoutSize(width: 0.2, height: 0.2),
                    layer: LayoutLayerID(name: "M1", purpose: "drawing")
                ),
            ]
        )
    }
}
