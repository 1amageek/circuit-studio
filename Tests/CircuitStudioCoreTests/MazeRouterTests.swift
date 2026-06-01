import Foundation
import LayoutCore
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

    @Test("Routes a diagonal net across met3 and met4")
    func routesDiagonalNet() throws {
        let nets = [
            MazeRouter.Net(name: "n0", pins: [
                LayoutPoint(x: 0.0, y: 0.0),
                LayoutPoint(x: 2.0, y: 2.0),
            ]),
        ]

        let shapes = try MazeRouter(pitch: 1.0, margin: 0.0).route(nets)
        let layers = Set(shapes.map(\.layer.name))

        #expect(!shapes.isEmpty)
        #expect(layers.contains("met3"))
        #expect(layers.contains("met4"))
        #expect(layers.contains("via3"))
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

        let report = NetAwareLayoutEvaluator().evaluateTaggedShapes(shapes, tech: Sky130LayoutTech.tech())

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
        let layers = Set(shapes.map(\.layer.name))

        #expect(!shapes.isEmpty)
        #expect(layers.contains("met3"))
        #expect(layers.contains("met4"))
        #expect(layers.contains("via3"))
    }

    @Test("Branches from a met4 tree segment by placing an explicit via3")
    func branchesFromMet4SegmentWithExplicitVia() throws {
        let shapes = try MazeRouter(pitch: 1.0, margin: 0.0).route([
            MazeRouter.Net(name: "n0", pins: [
                LayoutPoint(x: 0.0, y: 0.0),
                LayoutPoint(x: 0.0, y: 2.0),
                LayoutPoint(x: 2.0, y: 1.0),
            ]),
        ])

        let viaCenters = via3Centers(in: shapes)
        #expect(viaCenters.contains { abs($0.x - 0.0) < 1e-6 && abs($0.y - 1.0) < 1e-6 })
    }

    private func via3Centers(in shapes: [LayoutShape]) -> [LayoutPoint] {
        shapes.compactMap { shape in
            guard shape.layer.name == "via3", case let .rect(rect) = shape.geometry else { return nil }
            return LayoutPoint(
                x: rect.origin.x + rect.size.width / 2,
                y: rect.origin.y + rect.size.height / 2
            )
        }
    }
}
