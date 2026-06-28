import Foundation
import CircuitPhysicalDesign
import LayoutCore
import LayoutTech
import Testing
@testable import CircuitStudioApp

@Suite("Maze router")
struct MazeRouterTests {

    @Test("Empty net lists are rejected explicitly")
    func emptyNetList() throws {
        #expect(throws: MazeRouter.MazeError.self) {
            _ = try MazeRouter().route([])
        }
    }

    @Test("Invalid grid configuration is rejected before coordinate math")
    func invalidGridConfiguration() throws {
        #expect(throws: MazeRouter.MazeError.self) {
            _ = try MazeRouter(pitch: 0.0).route([
                MazeRouter.Net(name: "n0", pins: [
                    LayoutPoint(x: 0.0, y: 0.0),
                    LayoutPoint(x: 1.0, y: 1.0),
                ]),
            ])
        }

        #expect(throws: MazeRouter.MazeError.self) {
            _ = try MazeRouter(maxOrderingPasses: 0).route([
                MazeRouter.Net(name: "n0", pins: [
                    LayoutPoint(x: 0.0, y: 0.0),
                    LayoutPoint(x: 1.0, y: 1.0),
                ]),
            ])
        }
    }

    @Test("Invalid net identities are rejected before routing")
    func invalidNetIdentities() throws {
        #expect(throws: MazeRouter.MazeError.self) {
            _ = try MazeRouter().route([
                MazeRouter.Net(name: "", pins: [LayoutPoint(x: 0.0, y: 0.0)]),
            ])
        }

        #expect(throws: MazeRouter.MazeError.self) {
            _ = try MazeRouter().route([
                MazeRouter.Net(name: "n0", pins: [LayoutPoint(x: 0.0, y: 0.0)]),
                MazeRouter.Net(name: "n0", pins: [LayoutPoint(x: 1.0, y: 0.0)]),
            ])
        }

        #expect(throws: MazeRouter.MazeError.self) {
            _ = try MazeRouter().route([
                MazeRouter.Net(name: "n0", pins: []),
            ])
        }
    }

    @Test("Routes a diagonal net across profile routing layers")
    func routesDiagonalNet() throws {
        let profile = try bundledRoutingProfile()
        let nets = [
            MazeRouter.Net(name: "n0", pins: [
                LayoutPoint(x: 0.0, y: 0.0),
                LayoutPoint(x: 2.0, y: 2.0),
            ]),
        ]

        let shapes = try MazeRouter(pitch: 1.0, margin: 0.0).route(nets)
        let layers = Set(shapes.map(\.layer.name))

        #expect(!shapes.isEmpty)
        #expect(layers.contains(profile.layerReference(for: .horizontalRouting).name))
        #expect(layers.contains(profile.layerReference(for: .verticalRouting).name))
        #expect(layers.contains(profile.layerReference(for: .turnCut).name))
    }

    @Test("Routes with injected routing profile layers")
    func routesWithInjectedRoutingProfileLayers() throws {
        let profile = try customRoutingProfile()
        let defaultProfile = try bundledRoutingProfile()
        let shapes = try MazeRouter(
            profile: profile,
            layoutTechnology: customRoutingTechnology(for: profile),
            pitch: 1.0,
            margin: 0.0
        ).route([
            MazeRouter.Net(name: "n0", pins: [
                LayoutPoint(x: 0.0, y: 0.0),
                LayoutPoint(x: 2.0, y: 2.0),
            ]),
        ])
        let layers = Set(shapes.map(\.layer.name))

        #expect(layers.contains("TEST_H"))
        #expect(layers.contains("TEST_V"))
        #expect(layers.contains("TEST_TURN_CUT"))
        #expect(layers.contains("TEST_PIN_CUT"))
        #expect(!layers.contains(defaultProfile.layerReference(for: .horizontalRouting).name))
        #expect(!layers.contains(defaultProfile.layerReference(for: .turnCut).name))
    }

    @Test("Emitted geometry is net-tagged and passes net-aware physical evaluation")
    func emittedGeometryPassesNetAwareEvaluation() throws {
        let shapes = try MazeRouter(pitch: 1.0, margin: 1.0).route([
            MazeRouter.Net(name: "n0", pins: [
                LayoutPoint(x: 0.0, y: 0.0),
                LayoutPoint(x: 2.0, y: 2.0),
            ]),
            MazeRouter.Net(name: "n1", pins: [
                LayoutPoint(x: 0.0, y: 2.0),
                LayoutPoint(x: 2.0, y: 0.0),
            ]),
        ])

        let profile = try bundledRoutingProfile()
        let technology = try LayoutTechnologyResource.bundled(resourceName: profile.targetTechnologyResourceName)
        let report = NetAwareLayoutEvaluator().evaluateTaggedShapes(shapes, tech: technology)

        #expect(!shapes.isEmpty)
        #expect(shapes.allSatisfy { $0.properties[NetAwareLayoutEvaluator.netNameProperty] != nil })
        #expect(report.passed)
    }

    @Test("Routes crossing multi-layer nets with routing margin")
    func routesCrossingNets() throws {
        let nets = [
            MazeRouter.Net(name: "n0", pins: [
                LayoutPoint(x: 0.0, y: 0.0),
                LayoutPoint(x: 2.0, y: 2.0),
            ]),
            MazeRouter.Net(name: "n1", pins: [
                LayoutPoint(x: 0.0, y: 2.0),
                LayoutPoint(x: 2.0, y: 0.0),
            ]),
        ]

        let shapes = try MazeRouter(pitch: 1.0, margin: 1.0).route(nets)
        let profile = try bundledRoutingProfile()
        let layers = Set(shapes.map(\.layer.name))

        #expect(!shapes.isEmpty)
        #expect(layers.contains(profile.layerReference(for: .horizontalRouting).name))
        #expect(layers.contains(profile.layerReference(for: .verticalRouting).name))
        #expect(layers.contains(profile.layerReference(for: .turnCut).name))
    }

    @Test("Branches from a vertical routing tree segment by placing an explicit turn cut")
    func branchesFromVerticalSegmentWithExplicitTurnCut() throws {
        let shapes = try MazeRouter(pitch: 1.0, margin: 0.0).route([
            MazeRouter.Net(name: "n0", pins: [
                LayoutPoint(x: 0.0, y: 0.0),
                LayoutPoint(x: 0.0, y: 2.0),
                LayoutPoint(x: 2.0, y: 1.0),
            ]),
        ])

        let profile = try bundledRoutingProfile()
        let cutCenters = turnCutCenters(in: shapes, profile: profile)
        #expect(cutCenters.contains { abs($0.x - 0.0) < 1e-6 && abs($0.y - 1.0) < 1e-6 })
    }

    private func turnCutCenters(in shapes: [LayoutShape], profile: LayoutRoutingProfile) -> [LayoutPoint] {
        let turnCutLayer = profile.layerID(for: .turnCut)
        return shapes.compactMap { shape -> LayoutPoint? in
            guard shape.layer == turnCutLayer, case let .rect(rect) = shape.geometry else { return nil }
            return LayoutPoint(
                x: rect.origin.x + rect.size.width / 2,
                y: rect.origin.y + rect.size.height / 2
            )
        }
    }

    private func bundledRoutingProfile() throws -> LayoutRoutingProfile {
        try LayoutRoutingProfile.bundled(resourceName: Sky130LayoutTech.routingProfileResourceName)
    }

    private func customRoutingProfile() throws -> LayoutRoutingProfile {
        try LayoutRoutingProfile(
            profileID: "test.routing",
            targetTechnologyResourceName: "test-tech",
            layers: LayoutRoutingProfile.Layers(
                pinAccessBottom: .init(name: "TEST_PIN", purpose: "drawing"),
                horizontalRouting: .init(name: "TEST_H", purpose: "drawing"),
                verticalRouting: .init(name: "TEST_V", purpose: "drawing"),
                pinAccessCut: .init(name: "TEST_PIN_CUT", purpose: "cut"),
                turnCut: .init(name: "TEST_TURN_CUT", purpose: "cut"),
                powerRouting: .init(name: "TEST_PWR", purpose: "drawing")
            ),
            geometry: LayoutRoutingProfile.Geometry(
                gridPitch: 1.0,
                gridMargin: 0.0,
                maxOrderingPasses: 8,
                mazeWireWidth: 0.30,
                pinBottomPadWidth: 0.37,
                pinTopPadWidth: 0.50,
                pinAccessCutWidth: 0.20,
                turnPadWidth: 0.50,
                turnCutWidth: 0.20,
                interBlockSignalWireWidth: 0.50,
                powerRailHeight: 0.45,
                powerSpineWidth: 0.34,
                powerRowExtension: 0.085,
                powerSpineMargin: 0.60,
                powerSpineLaneSpacing: 0.80
            )
        )
    }

    private func customRoutingTechnology(for profile: LayoutRoutingProfile) -> LayoutTechDatabase {
        let layerIDs: [LayoutLayerID] = [
            profile.layerID(for: .pinAccessBottom),
            profile.layerID(for: .horizontalRouting),
            profile.layerID(for: .verticalRouting),
            profile.layerID(for: .pinAccessCut),
            profile.layerID(for: .turnCut),
            profile.layerID(for: .powerRouting),
        ]
        return LayoutTechDatabase(
            grid: 0.005,
            layers: layerIDs.enumerated().map { offset, layer in
                LayoutLayerDefinition(
                    id: layer,
                    displayName: layer.name,
                    gdsLayer: offset + 1,
                    gdsDatatype: 0,
                    color: .gray
                )
            },
            vias: [
                LayoutViaDefinition(
                    id: "test-pin-access",
                    cutLayer: profile.layerID(for: .pinAccessCut),
                    topLayer: profile.layerID(for: .horizontalRouting),
                    bottomLayer: profile.layerID(for: .pinAccessBottom),
                    cutSize: LayoutSize(width: 0.20, height: 0.20),
                    enclosure: LayoutViaEnclosure(top: 0.05, bottom: 0.05),
                    cutSpacing: 0.20
                ),
                LayoutViaDefinition(
                    id: "test-turn",
                    cutLayer: profile.layerID(for: .turnCut),
                    topLayer: profile.layerID(for: .verticalRouting),
                    bottomLayer: profile.layerID(for: .horizontalRouting),
                    cutSize: LayoutSize(width: 0.20, height: 0.20),
                    enclosure: LayoutViaEnclosure(top: 0.05, bottom: 0.05),
                    cutSpacing: 0.20
                ),
            ],
            layerRules: layerIDs.map { layer in
                LayoutLayerRuleSet(
                    layerID: layer,
                    minWidth: 0.10,
                    minSpacing: 0.10,
                    minArea: 0.0,
                    minDensity: 0.0,
                    maxDensity: 1.0
                )
            }
        )
    }
}
