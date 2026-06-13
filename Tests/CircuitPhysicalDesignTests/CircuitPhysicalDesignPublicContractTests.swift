import CoreGraphics
import Foundation
import Testing
import CircuitPhysicalDesign
import CircuitStudioCore
import LayoutAutoGen
import LayoutCore
import LayoutEngine
import LayoutTech
import LayoutVerify

@Suite("CircuitPhysicalDesign Public Contract")
struct CircuitPhysicalDesignPublicContractTests {

    @Test(.timeLimit(.minutes(1)))
    func synthesizerUsesRegisteredPlacementAndRoutingEnginesWithoutAppTarget() throws {
        let catalog = CircuitPhysicalDesignDefaults.layoutEngineCatalog()
            .registering(
                PlacementEngineRegistration(
                    descriptor: descriptor(
                        id: "test-fixed-placement",
                        role: .placement,
                        summary: "Places all instances at a deterministic sentinel coordinate."
                    ),
                    makeEngine: { _ in FixedPlacementEngine() }
                )
            )
            .registering(
                RoutingEngineRegistration(
                    descriptor: descriptor(
                        id: "test-sentinel-routing",
                        role: .routing,
                        summary: "Reports a sentinel unrouted net to prove routing engine selection."
                    ),
                    makeEngine: { SentinelRoutingEngine() }
                )
            )

        let output = try CircuitLayoutSynthesizer(layoutEngineCatalog: catalog).generate(
            from: singleResistorSchematic(),
            catalog: .standard(),
            placementStrategy: .registered("test-fixed-placement"),
            routingStrategy: .registered("test-sentinel-routing")
        )

        let topCellID = try #require(output.document.topCellID)
        let topCell = try #require(output.document.cell(withID: topCellID))
        let instance = try #require(topCell.instances.first { $0.name == "R1" })

        #expect(instance.transform.translation == FixedPlacementEngine.translation)
        #expect(output.unroutedNets == [SentinelRoutingEngine.unroutedNetName])
        #expect(output.drcResult.violations.allSatisfy { $0.severity != .error })
    }

    @Test(.timeLimit(.minutes(1)))
    func availabilityUsesDeviceCellProviderWithoutProjectOrAppState() {
        let deviceCatalog = customPassiveDeviceCatalog()
        let document = SchematicDocument(components: [
            PlacedComponent(
                deviceKindID: "test_device",
                name: "X1",
                position: .zero
            ),
        ])

        let empty = CircuitLayoutAvailability.evaluate(
            document: SchematicDocument(),
            catalog: deviceCatalog,
            deviceCellEngines: DeviceOnlyProvider(registrations: []),
            activeCellName: "TOP"
        )
        #expect(!empty.isAvailable)
        #expect(empty.code == .emptySchematic)

        let unsupported = CircuitLayoutAvailability.evaluate(
            document: document,
            catalog: deviceCatalog,
            deviceCellEngines: DeviceOnlyProvider(registrations: []),
            activeCellName: "TOP"
        )
        #expect(!unsupported.isAvailable)
        #expect(unsupported.code == .unsupportedPhysicalDevice)
        #expect(unsupported.reason?.contains("X1") == true)

        let supported = CircuitLayoutAvailability.evaluate(
            document: document,
            catalog: deviceCatalog,
            deviceCellEngines: DeviceOnlyProvider(registrations: [
                deviceRegistration(canonicalKindID: "test_device"),
            ]),
            activeCellName: "TOP"
        )
        #expect(supported.isAvailable)
        #expect(supported.code == .none)
        #expect(supported.help.contains("No schematic wires"))
    }

    @Test(.timeLimit(.minutes(1)))
    func synthesizerUsesRegisteredDeviceCellGeneratorForCustomPhysicalDevice() throws {
        let catalog = CircuitPhysicalDesignDefaults.layoutEngineCatalog()
            .registering(deviceRegistration(canonicalKindID: "test_device"))
        let output = try CircuitLayoutSynthesizer(layoutEngineCatalog: catalog).generate(
            from: SchematicDocument(components: [
                PlacedComponent(
                    deviceKindID: "test_device",
                    name: "X1",
                    position: .zero
                ),
            ]),
            catalog: customPassiveDeviceCatalog()
        )

        let topCellID = try #require(output.document.topCellID)
        let topCell = try #require(output.document.cell(withID: topCellID))
        let instance = try #require(topCell.instances.first { $0.name == "X1" })
        let deviceCell = try #require(output.document.cell(withID: instance.cellID))

        #expect(deviceCell.name == "test-device")
        #expect(deviceCell.pins.map(\.name).sorted() == ["A", "B"])
    }

    @Test(.timeLimit(.minutes(1)))
    func synthesizerRequiresPostRouteVerifierCapability() throws {
        do {
            _ = try CircuitLayoutSynthesizer(layoutEngineCatalog: LayoutEngineCatalog.standard()).generate(
                from: singleResistorSchematic(),
                catalog: .standard()
            )
            Issue.record("Expected layout generation to fail when the catalog has no post-route verifier.")
        } catch let error as LayoutEngineCatalogError {
            #expect(error == .missingPostRouteVerifier)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func layoutTrustEvaluationUsesCanonicalLayoutDocumentWithoutAppTechnology() throws {
        let netID = UUID(uuidString: "00000000-0000-0000-0000-000000001001")!
        let topCell = LayoutCell(
            name: "TOP",
            shapes: [
                rect("M1", -0.20, -0.20, 0.40, 0.40, netID: netID),
                rect("M2", -0.20, -0.20, 0.40, 0.40, netID: netID),
            ],
            vias: [
                LayoutVia(viaDefinitionID: "VIA1", position: LayoutPoint(x: 0, y: 0), netID: netID),
            ],
            nets: [
                LayoutNet(id: netID, name: "sig"),
            ]
        )
        let document = LayoutDocument(name: "trust", cells: [topCell], topCellID: topCell.id)

        let report = try LayoutTrustEvaluationService().evaluate(
            document: document,
            tech: .standard()
        )

        #expect(report.passed)
        #expect(report.topCellName == "TOP")
        #expect(report.ownedShapeCount == 3)
        #expect(report.unownedShapeCount == 0)
        #expect(report.netAwareReport.passed)
        #expect(report.ownershipMap.records.map(\.elementKind).sorted() == ["shape", "shape", "via"])
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

    private func customPassiveDeviceCatalog() -> DeviceCatalog {
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
        return catalog
    }

    private func deviceRegistration(canonicalKindID: String) -> DeviceCellEngineRegistration {
        DeviceCellEngineRegistration(
            descriptor: descriptor(
                id: "test-device-cell",
                role: .deviceCellGeneration,
                summary: "Generates a test passive device cell."
            ),
            supportedCanonicalDeviceKindIDs: [canonicalKindID],
            makeGenerator: { TestDeviceCellGenerator(supportedKindID: canonicalKindID) }
        )
    }

    private func descriptor(
        id: String,
        role: LayoutEngineRole,
        summary: String
    ) -> LayoutEngineDescriptor {
        LayoutEngineDescriptor(
            id: id,
            name: id,
            version: "1.0",
            role: role,
            summary: summary,
            isDeterministic: true,
            source: "test"
        )
    }

    private func rect(
        _ layerName: String,
        _ x: Double,
        _ y: Double,
        _ width: Double,
        _ height: Double,
        netID: UUID
    ) -> LayoutShape {
        LayoutShape(
            layer: LayoutLayerID(name: layerName, purpose: "drawing"),
            netID: netID,
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: x, y: y),
                size: LayoutSize(width: width, height: height)
            ))
        )
    }
}

private struct DeviceOnlyProvider: DeviceCellEngineProviding {
    private let registrations: [DeviceCellEngineRegistration]

    init(registrations: [DeviceCellEngineRegistration]) {
        self.registrations = registrations
    }

    var deviceCellEngines: [LayoutEngineDescriptor] {
        registrations.map(\.descriptor).sorted { $0.id < $1.id }
    }

    func deviceCellGenerator(canonicalDeviceKindID: String) -> (any DeviceCellGenerator)? {
        for registration in registrations.reversed()
        where registration.supports(canonicalDeviceKindID: canonicalDeviceKindID) {
            return registration.makeGenerator()
        }
        return nil
    }
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
    let supportedKindID: String

    var supportedDeviceKindIDs: [String] {
        [supportedKindID]
    }

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
