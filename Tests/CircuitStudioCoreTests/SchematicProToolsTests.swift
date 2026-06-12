import Testing
import Foundation
import CoreGraphics
@testable import SchematicEditor
@testable import CircuitStudioCore

@Suite("Schematic Professional Tools")
@MainActor
struct SchematicProToolsTests {

    // MARK: - Manhattan Wire Routing

    @Test("Diagonal wire request creates an L-shaped pair of axis-aligned segments")
    func diagonalWireBecomesLShape() {
        let vm = SchematicViewModel()
        vm.addWire(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 30))

        #expect(vm.document.wires.count == 2)
        for wire in vm.document.wires {
            let axisAligned = wire.startPoint.x == wire.endPoint.x
                || wire.startPoint.y == wire.endPoint.y
            #expect(axisAligned)
        }
        // dx (50) dominates dy (30): first leg is horizontal, corner at (50, 0).
        let corner = CGPoint(x: 50, y: 0)
        #expect(vm.document.wires[0].endPoint == corner)
        #expect(vm.document.wires[1].startPoint == corner)
    }

    @Test("Vertical-dominant diagonal routes vertically first")
    func verticalDominantRoute() {
        let vm = SchematicViewModel()
        vm.addWire(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 20, y: 80))

        #expect(vm.document.wires.count == 2)
        let corner = CGPoint(x: 0, y: 80)
        #expect(vm.document.wires[0].endPoint == corner)
        #expect(vm.document.wires[1].startPoint == corner)
    }

    @Test("Axis-aligned wire stays a single segment")
    func straightWireStaysSingle() {
        let vm = SchematicViewModel()
        vm.addWire(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))

        #expect(vm.document.wires.count == 1)
    }

    @Test("Manhattan corner equals an endpoint for axis-aligned displacement")
    func manhattanCornerDegenerate() {
        let end = CGPoint(x: 100, y: 0)
        #expect(SchematicViewModel.manhattanCorner(from: .zero, to: end) == end)
        let verticalEnd = CGPoint(x: 0, y: 100)
        #expect(SchematicViewModel.manhattanCorner(from: .zero, to: verticalEnd) == verticalEnd)
    }

    // MARK: - Arrow-Key Nudge

    @Test("Nudge moves the selected component and is one undo step")
    func nudgeMovesAndUndoes() {
        let vm = SchematicViewModel()
        vm.placeComponent(deviceKindID: "resistor", at: CGPoint(x: 100, y: 100))
        let id = vm.document.components[0].id
        vm.select(id)

        vm.nudgeSelection(by: CGSize(width: 10, height: 0))
        #expect(vm.document.components[0].position == CGPoint(x: 110, y: 100))

        vm.nudgeSelection(by: CGSize(width: 0, height: -10))
        #expect(vm.document.components[0].position == CGPoint(x: 110, y: 90))

        vm.undo()
        #expect(vm.document.components[0].position == CGPoint(x: 110, y: 100))
        vm.undo()
        #expect(vm.document.components[0].position == CGPoint(x: 100, y: 100))
    }

    @Test("Nudge with empty selection does nothing")
    func nudgeEmptySelection() {
        let vm = SchematicViewModel()
        vm.placeComponent(deviceKindID: "resistor", at: CGPoint(x: 100, y: 100))
        vm.nudgeSelection(by: CGSize(width: 10, height: 0))

        #expect(vm.document.components[0].position == CGPoint(x: 100, y: 100))
        #expect(!vm.canUndo)
    }

    @Test("Nudge keeps attached wires rubber-banded")
    func nudgeRubberBandsWires() {
        let vm = SchematicViewModel()
        vm.placeComponent(deviceKindID: "resistor", at: CGPoint(x: 100, y: 100))
        let component = vm.document.components[0]

        guard let kind = vm.catalog.device(for: component.deviceKindID),
              let port = kind.portDefinitions.first else {
            Issue.record("Resistor must define ports")
            return
        }
        let pinPosition = vm.pinWorldPosition(port: port, component: component)
        vm.addWire(from: pinPosition, to: CGPoint(x: pinPosition.x, y: pinPosition.y - 50))
        let attachedWire = vm.document.wires.first { $0.startPin?.componentID == component.id }
        #expect(attachedWire != nil)

        vm.select(component.id)
        vm.nudgeSelection(by: CGSize(width: 20, height: 0))

        let moved = vm.document.components[0]
        let expectedPin = vm.pinWorldPosition(port: port, component: moved)
        let movedWire = vm.document.wires.first { $0.startPin?.componentID == component.id }
        #expect(movedWire?.startPoint == expectedPin)
    }

    // MARK: - Zoom to Selection

    @Test("Zoom to selection centers the selected component")
    func zoomToSelectionCenters() {
        let vm = SchematicViewModel()
        vm.placeComponent(deviceKindID: "resistor", at: CGPoint(x: 500, y: 300))
        vm.select(vm.document.components[0].id)

        let canvasSize = CGSize(width: 800, height: 600)
        vm.zoomToSelection(canvasSize: canvasSize)

        let screenX = 500 * vm.zoom + vm.offset.x
        let screenY = 300 * vm.zoom + vm.offset.y
        #expect(abs(screenX - 400) < 1)
        #expect(abs(screenY - 300) < 1)
        #expect(vm.zoom <= 4.0)
    }

    @Test("Zoom to selection without selection leaves the viewport unchanged")
    func zoomToSelectionNoSelection() {
        let vm = SchematicViewModel()
        vm.placeComponent(deviceKindID: "resistor", at: CGPoint(x: 500, y: 300))
        let zoomBefore = vm.zoom
        let offsetBefore = vm.offset

        vm.zoomToSelection(canvasSize: CGSize(width: 800, height: 600))

        #expect(vm.zoom == zoomBefore)
        #expect(vm.offset == offsetBefore)
    }

    // MARK: - Grid Configuration

    @Test("Snap returns the input unchanged when snapping is disabled")
    func snapDisabled() {
        let vm = SchematicViewModel()
        vm.snapsToGrid = false
        let point = CGPoint(x: 3.7, y: 11.2)
        #expect(vm.snapToGrid(point) == point)

        vm.snapsToGrid = true
        #expect(vm.snapToGrid(point) == CGPoint(x: 0, y: 10))
    }

    @Test("Snap honors a configured grid size")
    func snapHonorsGridSize() {
        let vm = SchematicViewModel()
        vm.gridSize = 25
        #expect(vm.snapToGrid(CGPoint(x: 30, y: 40)) == CGPoint(x: 25, y: 50))
    }

    // MARK: - Engineering Notation

    @Test("Engineering notation formats with SI prefixes")
    func engineeringNotationFormats() {
        #expect(EngineeringNotation.format(1000, unit: "\u{2126}") == "1k\u{2126}")
        #expect(EngineeringNotation.format(4700, unit: "\u{2126}") == "4.7k\u{2126}")
        #expect(EngineeringNotation.format(1e-9, unit: "F") == "1nF")
        #expect(EngineeringNotation.format(2.2e-6, unit: "F") == "2.2\u{00B5}F")
        #expect(EngineeringNotation.format(0, unit: "V") == "0V")
        #expect(EngineeringNotation.format(5, unit: "V") == "5V")
        #expect(EngineeringNotation.format(-3.3, unit: "V") == "-3.3V")
        #expect(EngineeringNotation.format(1e6, unit: "\u{2126}") == "1M\u{2126}")
        #expect(EngineeringNotation.format(10e-6, unit: "m") == "10\u{00B5}m")
    }

    // MARK: - Component Value Annotation

    @Test("Resistor annotation shows the formatted resistance")
    func resistorAnnotation() {
        let vm = SchematicViewModel()
        vm.placeComponent(deviceKindID: "resistor", at: .zero)
        let component = vm.document.components[0]
        guard let kind = vm.catalog.device(for: "resistor") else {
            Issue.record("Resistor must exist in the standard catalog")
            return
        }
        #expect(ComponentValueText.annotation(for: component, kind: kind) == "1k\u{2126}")
    }

    @Test("MOSFET annotation shows W and L")
    func mosfetAnnotation() {
        let vm = SchematicViewModel()
        vm.placeComponent(deviceKindID: "nmos_l1", at: .zero)
        let component = vm.document.components[0]
        guard let kind = vm.catalog.device(for: "nmos_l1") else {
            Issue.record("NMOS must exist in the standard catalog")
            return
        }
        let annotation = ComponentValueText.annotation(for: component, kind: kind)
        #expect(annotation == "W=10\u{00B5}m L=1\u{00B5}m")
    }

    @Test("External model name wins over parameters")
    func externalModelAnnotation() {
        let vm = SchematicViewModel()
        vm.placeComponent(deviceKindID: "nmos_l1", at: .zero)
        vm.document.components[0].modelName = "sky130_fd_pr__nfet_01v8"
        let component = vm.document.components[0]
        guard let kind = vm.catalog.device(for: "nmos_l1") else {
            Issue.record("NMOS must exist in the standard catalog")
            return
        }
        #expect(ComponentValueText.annotation(for: component, kind: kind) == "sky130_fd_pr__nfet_01v8")
    }

    @Test("Voltage source annotation shows the DC value")
    func voltageSourceAnnotation() {
        let vm = SchematicViewModel()
        vm.placeComponent(deviceKindID: "vsource", at: .zero)
        let component = vm.document.components[0]
        guard let kind = vm.catalog.device(for: "vsource") else {
            Issue.record("Voltage source must exist in the standard catalog")
            return
        }
        #expect(ComponentValueText.annotation(for: component, kind: kind) == "5V")
    }
}
