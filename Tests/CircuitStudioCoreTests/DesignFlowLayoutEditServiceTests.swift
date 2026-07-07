import Foundation
import Testing
import LayoutCore
@testable import CircuitStudioApp

/// The structured layout edit commands that give an agent parity with the
/// interactive editor: polygon/via/instance/cell creation, identity-stable
/// shape moves, and net reassignment — each with explicit validation.
@Suite("DesignFlow Layout Edit Commands")
struct DesignFlowLayoutEditServiceTests {
    private let m1 = LayoutLayerID(name: "M1", purpose: "drawing")

    // MARK: - Polygon

    @Test func addPolygonShapeAddsToTargetCell() throws {
        let layout = singleCellLayout()
        let shapeID = UUID()
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(
                kind: .addPolygonShape,
                cellName: "TOP",
                elementID: shapeID,
                layerName: "M1",
                points: [
                    LayoutPoint(x: 0, y: 0),
                    LayoutPoint(x: 2, y: 0),
                    LayoutPoint(x: 2, y: 1),
                    LayoutPoint(x: 0, y: 1),
                ]
            ),
        ])

        let result = try DesignFlowLayoutEditService().apply(script: script, to: layout)

        let cell = try #require(result.layout.cells.first)
        let shape = try #require(cell.shapes.first { $0.id == shapeID })
        guard case .polygon(let polygon) = shape.geometry else {
            Issue.record("Expected polygon geometry, got \(shape.geometry)")
            return
        }
        #expect(polygon.points.count == 4)
        #expect(shape.layer == m1)
        #expect(result.diff.addedShapes == [shapeID])
    }

    @Test func addPolygonShapeRejectsFewerThanThreePoints() throws {
        let layout = singleCellLayout()
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(
                kind: .addPolygonShape,
                cellName: "TOP",
                layerName: "M1",
                points: [LayoutPoint(x: 0, y: 0), LayoutPoint(x: 1, y: 0)]
            ),
        ])

        #expect(throws: DesignFlowLayoutEditError.invalidGeometry(
            "Polygon shape requires at least three points."
        )) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    // MARK: - Via

    @Test func addViaAndRemoveViaRoundTrip() throws {
        var layout = singleCellLayout()
        layout.cells[0].nets = [LayoutNet(name: "out")]
        let viaID = UUID()

        let added = try DesignFlowLayoutEditService().apply(
            script: DesignFlowLayoutEditScript(edits: [
                DesignFlowLayoutEdit(
                    kind: .addVia,
                    cellName: "TOP",
                    elementID: viaID,
                    netName: "out",
                    x: 1.5,
                    y: 2.5,
                    viaDefinitionID: "VIA1"
                ),
            ]),
            to: layout
        )

        let via = try #require(added.layout.cells[0].vias.first)
        #expect(via.id == viaID)
        #expect(via.viaDefinitionID == "VIA1")
        #expect(via.position == LayoutPoint(x: 1.5, y: 2.5))
        #expect(via.netID == added.layout.cells[0].nets.first?.id)
        #expect(added.diff.addedVias == [viaID])

        let removed = try DesignFlowLayoutEditService().apply(
            script: DesignFlowLayoutEditScript(edits: [
                DesignFlowLayoutEdit(kind: .removeVia, cellName: "TOP", elementID: viaID),
            ]),
            to: added.layout
        )
        #expect(removed.layout.cells[0].vias.isEmpty)
        #expect(removed.diff.removedVias == [viaID])
    }

    @Test func addViaRequiresViaDefinitionID() throws {
        let layout = singleCellLayout()
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(kind: .addVia, cellName: "TOP", x: 0, y: 0),
        ])

        #expect(throws: DesignFlowLayoutEditError.missingField("viaDefinitionID", .addVia)) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    // MARK: - Move

    @Test func moveShapeTranslatesEveryGeometryKindAndKeepsIdentity() throws {
        var layout = singleCellLayout()
        let netID = UUID()
        layout.cells[0].nets = [LayoutNet(id: netID, name: "out")]
        let rect = LayoutShape(
            layer: m1,
            netID: netID,
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 2, height: 1)
            )),
            properties: ["purpose": "route"]
        )
        let polygon = LayoutShape(
            layer: m1,
            geometry: .polygon(LayoutPolygon(points: [
                LayoutPoint(x: 0, y: 0),
                LayoutPoint(x: 1, y: 0),
                LayoutPoint(x: 1, y: 1),
            ]))
        )
        let path = LayoutShape(
            layer: m1,
            geometry: .path(LayoutPath(
                points: [LayoutPoint(x: 0, y: 0), LayoutPoint(x: 3, y: 0)],
                width: 0.2
            ))
        )
        layout.cells[0].shapes = [rect, polygon, path]

        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(kind: .moveShape, cellName: "TOP", elementID: rect.id, dx: 1.0, dy: -0.5),
            DesignFlowLayoutEdit(kind: .moveShape, cellName: "TOP", elementID: polygon.id, dx: 1.0, dy: -0.5),
            DesignFlowLayoutEdit(kind: .moveShape, cellName: "TOP", elementID: path.id, dx: 1.0, dy: -0.5),
        ])

        let result = try DesignFlowLayoutEditService().apply(script: script, to: layout)

        let cell = result.layout.cells[0]
        #expect(Set(cell.shapes.map(\.id)) == Set([rect.id, polygon.id, path.id]))

        let movedRect = try #require(cell.shapes.first { $0.id == rect.id })
        guard case .rect(let rectGeometry) = movedRect.geometry else {
            Issue.record("Expected rect geometry, got \(movedRect.geometry)")
            return
        }
        #expect(rectGeometry.origin == LayoutPoint(x: 1.0, y: -0.5))
        #expect(rectGeometry.size == LayoutSize(width: 2, height: 1))
        #expect(movedRect.netID == netID)
        #expect(movedRect.properties == ["purpose": "route"])

        let movedPolygon = try #require(cell.shapes.first { $0.id == polygon.id })
        guard case .polygon(let polygonGeometry) = movedPolygon.geometry else {
            Issue.record("Expected polygon geometry, got \(movedPolygon.geometry)")
            return
        }
        #expect(polygonGeometry.points.first == LayoutPoint(x: 1.0, y: -0.5))

        let movedPath = try #require(cell.shapes.first { $0.id == path.id })
        guard case .path(let pathGeometry) = movedPath.geometry else {
            Issue.record("Expected path geometry, got \(movedPath.geometry)")
            return
        }
        #expect(pathGeometry.points == [LayoutPoint(x: 1.0, y: -0.5), LayoutPoint(x: 4.0, y: -0.5)])
        #expect(pathGeometry.width == 0.2)

        // Moves change content under stable IDs: that is a modification,
        // not an add/remove pair.
        #expect(result.diff.addedShapes.isEmpty)
        #expect(result.diff.removedShapes.isEmpty)
        #expect(Set(result.diff.modifiedShapes) == Set([rect.id, polygon.id, path.id]))
    }

    @Test func moveShapeRejectsUnknownElement() throws {
        let layout = singleCellLayout()
        let missingID = UUID()
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(kind: .moveShape, cellName: "TOP", elementID: missingID, dx: 1, dy: 1),
        ])

        #expect(throws: DesignFlowLayoutEditError.unknownElement(missingID)) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    // MARK: - Net reassignment

    @Test func setAndClearShapeNetEnableNetRemoval() throws {
        var layout = singleCellLayout()
        let netID = UUID()
        layout.cells[0].nets = [LayoutNet(id: netID, name: "out")]
        let shape = LayoutShape(
            layer: m1,
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 1, height: 1)
            ))
        )
        layout.cells[0].shapes = [shape]

        let assigned = try DesignFlowLayoutEditService().apply(
            script: DesignFlowLayoutEditScript(edits: [
                DesignFlowLayoutEdit(kind: .setShapeNet, cellName: "TOP", elementID: shape.id, netName: "out"),
            ]),
            to: layout
        )
        #expect(assigned.layout.cells[0].shapes[0].netID == netID)
        #expect(assigned.diff.modifiedShapes == [shape.id])

        // While the shape references the net, removal must refuse.
        #expect(throws: DesignFlowLayoutEditError.netInUse("out")) {
            try DesignFlowLayoutEditService().apply(
                script: DesignFlowLayoutEditScript(edits: [
                    DesignFlowLayoutEdit(kind: .removeNet, cellName: "TOP", netName: "out"),
                ]),
                to: assigned.layout
            )
        }

        let cleared = try DesignFlowLayoutEditService().apply(
            script: DesignFlowLayoutEditScript(edits: [
                DesignFlowLayoutEdit(kind: .clearShapeNet, cellName: "TOP", elementID: shape.id),
                DesignFlowLayoutEdit(kind: .removeNet, cellName: "TOP", netName: "out"),
            ]),
            to: assigned.layout
        )
        #expect(cleared.layout.cells[0].shapes[0].netID == nil)
        #expect(cleared.layout.cells[0].nets.isEmpty)
        #expect(cleared.diff.removedNets == ["TOP:out"])
    }

    @Test func setShapeNetRejectsUnknownNet() throws {
        var layout = singleCellLayout()
        let shape = LayoutShape(
            layer: m1,
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 1, height: 1)
            ))
        )
        layout.cells[0].shapes = [shape]
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(kind: .setShapeNet, cellName: "TOP", elementID: shape.id, netName: "ghost"),
        ])

        #expect(throws: DesignFlowLayoutEditError.unknownNet("ghost")) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    @Test func setShapeNetRejectsStaleNetIDInsteadOfFallingBackToName() throws {
        var layout = singleCellLayout()
        let shape = LayoutShape(
            layer: m1,
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 1, height: 1)
            ))
        )
        layout.cells[0].nets = [LayoutNet(name: "out")]
        layout.cells[0].shapes = [shape]
        let staleNetID = UUID()
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(
                kind: .setShapeNet,
                cellName: "TOP",
                elementID: shape.id,
                netID: staleNetID,
                netName: "out"
            ),
        ])

        #expect(throws: DesignFlowLayoutEditError.unknownNet(staleNetID.uuidString)) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    @Test func setShapeNetRejectsMismatchedNetIDAndName() throws {
        var layout = singleCellLayout()
        let shape = LayoutShape(
            layer: m1,
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: 0, y: 0),
                size: LayoutSize(width: 1, height: 1)
            ))
        )
        let outNet = LayoutNet(name: "out")
        let vddNet = LayoutNet(name: "vdd")
        layout.cells[0].nets = [outNet, vddNet]
        layout.cells[0].shapes = [shape]
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(
                kind: .setShapeNet,
                cellName: "TOP",
                elementID: shape.id,
                netID: vddNet.id,
                netName: "out"
            ),
        ])

        #expect(throws: DesignFlowLayoutEditError.netReferenceMismatch(id: vddNet.id, name: "out")) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    // MARK: - Cell and instance hierarchy

    @Test func addCellThenInstanceBuildsHierarchy() throws {
        let layout = singleCellLayout()
        let instanceID = UUID()
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(kind: .addCell, cellName: "INV"),
            DesignFlowLayoutEdit(
                kind: .addInstance,
                cellName: "TOP",
                elementID: instanceID,
                x: 4.0,
                y: 2.0,
                instanceName: "inv0",
                referenceCellName: "INV",
                rotationDegrees: 90,
                mirrorX: true
            ),
        ])

        let result = try DesignFlowLayoutEditService().apply(script: script, to: layout)

        #expect(result.layout.cells.map(\.name) == ["TOP", "INV"])
        let top = try #require(result.layout.cells.first { $0.name == "TOP" })
        let inv = try #require(result.layout.cells.first { $0.name == "INV" })
        let instance = try #require(top.instances.first)
        #expect(instance.id == instanceID)
        #expect(instance.cellID == inv.id)
        #expect(instance.name == "inv0")
        #expect(instance.transform.translation == LayoutPoint(x: 4.0, y: 2.0))
        #expect(instance.transform.rotationDegrees == 90)
        #expect(instance.transform.magnification == 1.0)
        #expect(instance.transform.mirrorX)
        #expect(!instance.transform.mirrorY)
        #expect(result.diff.addedCells == ["INV"])
        #expect(result.diff.addedInstances == ["TOP:inv0"])

        let removed = try DesignFlowLayoutEditService().apply(
            script: DesignFlowLayoutEditScript(edits: [
                DesignFlowLayoutEdit(kind: .removeInstance, cellName: "TOP", elementID: instanceID),
            ]),
            to: result.layout
        )
        #expect(removed.layout.cells.first { $0.name == "TOP" }?.instances.isEmpty == true)
        #expect(removed.diff.removedInstances == ["TOP:inv0"])
    }

    @Test func addCellRejectsDuplicateName() throws {
        let layout = singleCellLayout()
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(kind: .addCell, cellName: "TOP"),
        ])

        #expect(throws: DesignFlowLayoutEditError.duplicateCell("TOP")) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    @Test func addInstanceRejectsSelfInstantiation() throws {
        let layout = singleCellLayout()
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(
                kind: .addInstance,
                cellName: "TOP",
                x: 0,
                y: 0,
                instanceName: "self0",
                referenceCellName: "TOP"
            ),
        ])

        #expect(throws: DesignFlowLayoutEditError.self) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    @Test func addInstanceRejectsIndirectCycle() throws {
        // TOP already instantiates INV; nesting TOP inside INV would make
        // each cell contain the other, which GDS hierarchies forbid.
        let invCell = LayoutCell(name: "INV")
        var topCell = LayoutCell(name: "TOP")
        topCell.instances = [LayoutInstance(cellID: invCell.id, name: "inv0")]
        let layout = LayoutDocument(
            name: "EditTest",
            cells: [topCell, invCell],
            topCellID: topCell.id
        )

        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(
                kind: .addInstance,
                cellName: "INV",
                x: 0,
                y: 0,
                instanceName: "top0",
                referenceCellName: "TOP"
            ),
        ])

        #expect(throws: DesignFlowLayoutEditError.instanceCycle(
            "instantiating TOP inside INV would make INV contain itself"
        )) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    @Test func addInstanceRejectsUnknownReferenceCell() throws {
        let layout = singleCellLayout()
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(
                kind: .addInstance,
                cellName: "TOP",
                x: 0,
                y: 0,
                instanceName: "ghost0",
                referenceCellName: "GHOST"
            ),
        ])

        #expect(throws: DesignFlowLayoutEditError.unknownCell("GHOST")) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    @Test func addInstanceRejectsDuplicateInstanceName() throws {
        let invCell = LayoutCell(name: "INV")
        var topCell = LayoutCell(name: "TOP")
        topCell.instances = [LayoutInstance(cellID: invCell.id, name: "inv0")]
        let layout = LayoutDocument(
            name: "EditTest",
            cells: [topCell, invCell],
            topCellID: topCell.id
        )

        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(
                kind: .addInstance,
                cellName: "TOP",
                x: 1,
                y: 1,
                instanceName: "inv0",
                referenceCellName: "INV"
            ),
        ])

        #expect(throws: DesignFlowLayoutEditError.duplicateInstanceName("inv0")) {
            try DesignFlowLayoutEditService().apply(script: script, to: layout)
        }
    }

    // MARK: - JSON round-trip

    @Test func scriptWithNewKindsRoundTripsThroughJSON() throws {
        let script = DesignFlowLayoutEditScript(edits: [
            DesignFlowLayoutEdit(kind: .addCell, cellName: "INV"),
            DesignFlowLayoutEdit(
                kind: .addPolygonShape,
                cellName: "INV",
                layerName: "M1",
                points: [
                    LayoutPoint(x: 0, y: 0),
                    LayoutPoint(x: 1, y: 0),
                    LayoutPoint(x: 1, y: 1),
                ]
            ),
            DesignFlowLayoutEdit(kind: .addVia, cellName: "INV", x: 0.5, y: 0.5, viaDefinitionID: "VIA1"),
            DesignFlowLayoutEdit(kind: .moveShape, cellName: "INV", elementID: UUID(), dx: 1, dy: 0),
            DesignFlowLayoutEdit(
                kind: .addInstance,
                cellName: "TOP",
                x: 0,
                y: 0,
                instanceName: "inv0",
                referenceCellName: "INV",
                mirrorY: true
            ),
        ])

        let data = try JSONEncoder().encode(script)
        let decoded = try JSONDecoder().decode(DesignFlowLayoutEditScript.self, from: data)
        #expect(decoded == script)
    }

    // MARK: - Fixtures

    private func singleCellLayout() -> LayoutDocument {
        let cell = LayoutCell(name: "TOP")
        return LayoutDocument(name: "EditTest", cells: [cell], topCellID: cell.id)
    }
}
