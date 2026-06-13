import Foundation
import CircuitPhysicalDesign
import CoreGraphics
import Testing
import CoreSpiceWaveform
@testable import CircuitStudioApp
@testable import CircuitStudioCore
@testable import SchematicEditor

// MARK: - Schematic builders

/// Builds a chain of wires forming one net. Each net occupies its own
/// horizontal row (`netIndex * 100`) so separate nets never touch.
private func net(
    _ netIndex: Int,
    _ pins: [(UUID, String)],
    name: String? = nil
) -> [Wire] {
    let y = CGFloat(netIndex * 100)
    var wires: [Wire] = []
    for (j, pin) in pins.enumerated() {
        wires.append(Wire(
            startPoint: CGPoint(x: CGFloat(j) * 100, y: y),
            endPoint: CGPoint(x: CGFloat(j + 1) * 100, y: y),
            startPin: PinReference(componentID: pin.0, portID: pin.1),
            netName: j == 0 ? name : nil
        ))
    }
    return wires
}

/// The stable connectivity id of a cell port — the UUID of its port-marker
/// component, which `CellInterface.derive` exposes as `CellPort.id`. Parent
/// wires must reference this, not the editable port name, so a child-port
/// rename never misroutes the net. The cell passed here must be the very
/// same instance later registered in the library, since each builder call
/// mints fresh port-marker UUIDs.
private func cellPortID(_ cell: DesignCell, _ portName: String) throws -> String {
    let interface = try CellInterface.derive(from: cell.schematic)
    let port = try #require(
        interface.ports.first { $0.name == portName },
        "cell \(cell.name) has no port named \(portName)"
    )
    return port.id
}

/// A CMOS inverter cell with ports A (in), Y (out), VDD (power), VSS (ground).
private func makeInverterCell() -> DesignCell {
    let portA = PlacedComponent(deviceKindID: "port_input", name: "A", position: .zero)
    let portY = PlacedComponent(deviceKindID: "port_output", name: "Y", position: .zero)
    let portVdd = PlacedComponent(deviceKindID: "port_power", name: "VDD", position: .zero)
    let portVss = PlacedComponent(deviceKindID: "port_ground", name: "VSS", position: .zero)
    let mp = PlacedComponent(
        deviceKindID: "pmos_l1", name: "MP1", position: .zero,
        parameters: ["w": 20e-6, "l": 1e-6, "vto": -0.7, "kp": 50e-6]
    )
    let mn = PlacedComponent(
        deviceKindID: "nmos_l1", name: "MN1", position: .zero,
        parameters: ["w": 10e-6, "l": 1e-6, "vto": 0.7, "kp": 110e-6]
    )

    var wires: [Wire] = []
    wires += net(0, [(portA.id, "pin"), (mp.id, "gate"), (mn.id, "gate")])
    wires += net(1, [(portY.id, "pin"), (mp.id, "drain"), (mn.id, "drain")])
    wires += net(2, [(portVdd.id, "pin"), (mp.id, "source"), (mp.id, "bulk")])
    wires += net(3, [(portVss.id, "pin"), (mn.id, "source"), (mn.id, "bulk")])

    return DesignCell(name: "INV", schematic: SchematicDocument(
        components: [portA, portY, portVdd, portVss, mp, mn],
        wires: wires
    ))
}

private let inverterTestbench = Testbench(
    name: "Transient",
    analysisCommands: [.tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9))]
)

private let pulseParameters: [String: Double] = [
    "pulse_v1": 0, "pulse_v2": 3.3, "pulse_td": 1e-9,
    "pulse_tr": 0.5e-9, "pulse_tf": 0.5e-9, "pulse_pw": 10e-9, "pulse_per": 22e-9,
]

/// Top-level testbench instantiating the INV cell: pulse input, DC supply,
/// capacitive load, global ground. The inverter is passed in so X1's pins
/// reference the same port-marker UUIDs the library cell exposes.
private func makeHierarchicalTop(inv: DesignCell) throws -> SchematicDocument {
    let x1 = PlacedComponent(
        deviceKindID: DeviceCatalog.cellKindID(for: inv.name),
        name: "X1", position: .zero, cellName: inv.name
    )
    let vdd = PlacedComponent(deviceKindID: "vsource", name: "V1", position: .zero, parameters: ["dc": 3.3])
    let vin = PlacedComponent(deviceKindID: "vsource", name: "V2", position: .zero, parameters: pulseParameters)
    let cload = PlacedComponent(deviceKindID: "capacitor", name: "C1", position: .zero, parameters: ["c": 100e-15])
    let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: .zero)

    var wires: [Wire] = []
    wires += net(0, [(vin.id, "pos"), (x1.id, try cellPortID(inv, "A"))], name: "in")
    wires += net(1, [(x1.id, try cellPortID(inv, "Y")), (cload.id, "pos")], name: "out")
    wires += net(2, [(vdd.id, "pos"), (x1.id, try cellPortID(inv, "VDD"))], name: "vdd")
    wires += net(3, [(vdd.id, "neg"), (vin.id, "neg"), (x1.id, try cellPortID(inv, "VSS")), (cload.id, "neg"), (gnd.id, "gnd")])

    return SchematicDocument(
        components: [x1, vdd, vin, cload, gnd],
        wires: wires
    )
}

/// The same circuit with the inverter devices placed directly at top level.
private func makeFlatTop() -> SchematicDocument {
    let mp = PlacedComponent(
        deviceKindID: "pmos_l1", name: "MP1", position: .zero,
        parameters: ["w": 20e-6, "l": 1e-6, "vto": -0.7, "kp": 50e-6]
    )
    let mn = PlacedComponent(
        deviceKindID: "nmos_l1", name: "MN1", position: .zero,
        parameters: ["w": 10e-6, "l": 1e-6, "vto": 0.7, "kp": 110e-6]
    )
    let vdd = PlacedComponent(deviceKindID: "vsource", name: "V1", position: .zero, parameters: ["dc": 3.3])
    let vin = PlacedComponent(deviceKindID: "vsource", name: "V2", position: .zero, parameters: pulseParameters)
    let cload = PlacedComponent(deviceKindID: "capacitor", name: "C1", position: .zero, parameters: ["c": 100e-15])
    let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: .zero)

    var wires: [Wire] = []
    wires += net(0, [(vin.id, "pos"), (mp.id, "gate"), (mn.id, "gate")], name: "in")
    wires += net(1, [(mp.id, "drain"), (mn.id, "drain"), (cload.id, "pos")], name: "out")
    wires += net(2, [(vdd.id, "pos"), (mp.id, "source"), (mp.id, "bulk")], name: "vdd")
    wires += net(3, [(vdd.id, "neg"), (vin.id, "neg"), (mn.id, "source"), (mn.id, "bulk"), (cload.id, "neg"), (gnd.id, "gnd")])

    return SchematicDocument(
        components: [mp, mn, vdd, vin, cload, gnd],
        wires: wires
    )
}

/// A two-port "RC" cell (input → resistor → output) built with explicit
/// port-marker UUIDs. Two builds with different `inputName` but identical
/// `inputID`/`outputID` model exactly what a child-port rename produces:
/// the SPICE name changes while the stable port id stays put.
private func makeRenamableCell(
    inputName: String,
    inputID: UUID,
    outputID: UUID
) -> DesignCell {
    let portIn = PlacedComponent(id: inputID, deviceKindID: "port_input", name: inputName, position: .zero)
    let portOut = PlacedComponent(id: outputID, deviceKindID: "port_output", name: "Q", position: .zero)
    let r = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero, parameters: ["r": 1000])
    var wires: [Wire] = []
    wires += net(0, [(portIn.id, "pin"), (r.id, "pos")])
    wires += net(1, [(portOut.id, "pin"), (r.id, "neg")])
    return DesignCell(name: "RC", schematic: SchematicDocument(
        components: [portIn, portOut, r], wires: wires
    ))
}

// MARK: - CellInterface

@Suite("Cell Interface Derivation")
struct CellInterfaceTests {

    @Test func canonicalPortOrder() throws {
        let interface = try CellInterface.derive(from: makeInverterCell().schematic)
        #expect(interface.ports.map(\.name) == ["A", "Y", "VDD", "VSS"])
        #expect(interface.ports.map(\.direction) == [.input, .output, .power, .ground])
    }

    @Test func alphabeticalWithinGroup() throws {
        let b = PlacedComponent(deviceKindID: "port_input", name: "B", position: .zero)
        let a = PlacedComponent(deviceKindID: "port_input", name: "A", position: .zero)
        let r = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero, parameters: ["r": 1000])
        var wires: [Wire] = []
        wires += net(0, [(b.id, "pin"), (r.id, "pos")])
        wires += net(1, [(a.id, "pin"), (r.id, "neg")])
        let document = SchematicDocument(components: [b, a, r], wires: wires)

        let interface = try CellInterface.derive(from: document)
        #expect(interface.ports.map(\.name) == ["A", "B"])
    }

    @Test func duplicatePortNameThrows() {
        let p1 = PlacedComponent(deviceKindID: "port_input", name: "A", position: .zero)
        let p2 = PlacedComponent(deviceKindID: "port_output", name: "A", position: .zero)
        let r = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        var wires: [Wire] = []
        wires += net(0, [(p1.id, "pin"), (r.id, "pos")])
        wires += net(1, [(p2.id, "pin"), (r.id, "neg")])
        let document = SchematicDocument(components: [p1, p2, r], wires: wires)

        #expect(throws: CellInterfaceError.duplicatePortName("A")) {
            try CellInterface.derive(from: document)
        }
    }

    @Test func invalidPortNameThrows() {
        let p1 = PlacedComponent(deviceKindID: "port_input", name: "1bad", position: .zero)
        let document = SchematicDocument(components: [p1], wires: net(0, [(p1.id, "pin")]))

        #expect(throws: CellInterfaceError.invalidPortName("1bad")) {
            try CellInterface.derive(from: document)
        }
    }

    @Test func shortedPortsThrow() {
        let p1 = PlacedComponent(deviceKindID: "port_input", name: "A", position: .zero)
        let p2 = PlacedComponent(deviceKindID: "port_output", name: "Y", position: .zero)
        let document = SchematicDocument(
            components: [p1, p2],
            wires: net(0, [(p1.id, "pin"), (p2.id, "pin")])
        )

        #expect(throws: CellInterfaceError.shortedPorts(["A", "Y"])) {
            try CellInterface.derive(from: document)
        }
    }

    @Test func unconnectedPortThrows() {
        let p1 = PlacedComponent(deviceKindID: "port_input", name: "A", position: .zero)
        let document = SchematicDocument(components: [p1], wires: [])

        #expect(throws: CellInterfaceError.unconnectedPort("A")) {
            try CellInterface.derive(from: document)
        }
    }

    @Test func portShortedToGroundThrows() {
        let p1 = PlacedComponent(deviceKindID: "port_ground", name: "VSS", position: .zero)
        let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: .zero)
        let document = SchematicDocument(
            components: [p1, gnd],
            wires: net(0, [(p1.id, "pin"), (gnd.id, "gnd")])
        )

        #expect(throws: CellInterfaceError.portShortedToGround("VSS")) {
            try CellInterface.derive(from: document)
        }
    }

    @Test func portNamesBecomeNetNames() {
        let document = makeInverterCell().schematic
        let netNames = Set(NetExtractor().extract(from: document).map(\.name))
        #expect(netNames == ["A", "Y", "VDD", "VSS"])
    }
}

// MARK: - CellLibrary

@Suite("Cell Library")
struct CellLibraryTests {

    /// A minimal valid cell that instantiates the given children.
    private func cell(_ name: String, instantiating children: [String]) -> DesignCell {
        let port = PlacedComponent(deviceKindID: "port_input", name: "P", position: .zero)
        var components = [port]
        var wires = net(0, [(port.id, "pin")])
        for (index, child) in children.enumerated() {
            let instance = PlacedComponent(
                deviceKindID: DeviceCatalog.cellKindID(for: child),
                name: "X\(index + 1)", position: .zero, cellName: child
            )
            components.append(instance)
            wires += net(index + 1, [(instance.id, "P")])
        }
        return DesignCell(name: name, schematic: SchematicDocument(components: components, wires: wires))
    }

    @Test func orderedDependenciesAreDeepestFirst() throws {
        let library = CellLibrary(cells: [
            cell("Top", instantiating: ["A"]),
            cell("A", instantiating: ["B"]),
            cell("B", instantiating: []),
        ])
        #expect(try library.orderedDependencies(of: "Top") == ["B", "A"])
    }

    @Test func cycleDetection() {
        let library = CellLibrary(cells: [
            cell("A", instantiating: ["B"]),
            cell("B", instantiating: ["A"]),
        ])
        #expect(throws: CellLibraryError.dependencyCycle(["A", "B", "A"])) {
            try library.orderedDependencies(of: "A")
        }
    }

    @Test func reachesIncludesSelfAndTransitive() {
        let library = CellLibrary(cells: [
            cell("A", instantiating: ["B"]),
            cell("B", instantiating: []),
        ])
        #expect(library.reaches(from: "A", to: "A"))
        #expect(library.reaches(from: "A", to: "B"))
        #expect(!library.reaches(from: "B", to: "A"))
    }

    @Test func duplicateCellNameFailsValidation() {
        let library = CellLibrary(cells: [
            cell("A", instantiating: []),
            cell("A", instantiating: []),
        ])
        #expect(throws: CellLibraryError.duplicateCellName("A")) {
            try library.validate()
        }
    }

    @Test func unknownReferenceFailsValidation() {
        let library = CellLibrary(cells: [
            cell("A", instantiating: ["Ghost"]),
        ])
        #expect(throws: CellLibraryError.unknownCellReference(parent: "A", child: "Ghost")) {
            try library.validate()
        }
    }

    @Test func cellLookupIsCaseInsensitive() {
        // SPICE subckt names and the on-disk cells/<name>/ directory are both
        // case-insensitive, so a lookup must fold case yet return the cell's
        // canonical spelling.
        let library = CellLibrary(cells: [cell("INV", instantiating: [])])
        #expect(library.cell(named: "inv")?.name == "INV")
        #expect(library.cell(named: "Inv")?.name == "INV")
    }

    @Test func duplicateCellNameIsCaseInsensitive() {
        let library = CellLibrary(cells: [
            cell("INV", instantiating: []),
            cell("inv", instantiating: []),
        ])
        #expect(throws: CellLibraryError.duplicateCellName("inv")) {
            try library.validate()
        }
    }

    @Test func referenceResolvesCaseInsensitively() throws {
        // Top instantiates "INV"; the cell is defined as "inv". Emission must
        // resolve the reference and order the dependency by canonical name.
        let library = CellLibrary(cells: [
            cell("Top", instantiating: ["INV"]),
            cell("inv", instantiating: []),
        ])
        #expect(try library.orderedDependencies(of: "Top") == ["inv"])
    }
}

// MARK: - Catalog integration

@Suite("Cell Catalog Integration")
struct CellCatalogTests {

    @Test func includingCellsRegistersPlaceableKinds() {
        let library = CellLibrary(cells: [makeInverterCell()])
        let result = DeviceCatalog.standard().includingCells(from: library, activeCellName: nil)

        #expect(result.issues.isEmpty)
        let kind = result.catalog.device(for: DeviceCatalog.cellKindID(for: "INV"))
        #expect(kind != nil)
        #expect(kind?.category == .cell)
        #expect(kind?.spicePrefix == "X")
        #expect(kind?.cellName == "INV")
        // Names appear in display order; the ids are now the stable
        // port-marker UUIDs (decoupled from the names), so they must be
        // unique, non-empty, and real UUIDs rather than the SPICE names.
        #expect(kind?.portDefinitions.map(\.displayName) == ["A", "Y", "VDD", "VSS"])
        let portIDs = kind?.portDefinitions.map(\.id) ?? []
        #expect(portIDs.count == 4)
        #expect(Set(portIDs).count == 4)
        #expect(portIDs.allSatisfy { UUID(uuidString: $0) != nil })
    }

    @Test func activeCellAndAncestorsAreExcluded() {
        let portP = PlacedComponent(deviceKindID: "port_input", name: "P", position: .zero)
        let inv = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "INV"),
            name: "X1", position: .zero, cellName: "INV"
        )
        var wires = net(0, [(portP.id, "pin"), (inv.id, "A")])
        wires += net(1, [(inv.id, "Y")])
        let parent = DesignCell(name: "BUF_STAGE", schematic: SchematicDocument(
            components: [portP, inv], wires: wires
        ))
        let library = CellLibrary(cells: [makeInverterCell(), parent])

        // Editing INV: neither INV itself nor BUF_STAGE (which instantiates
        // INV) may be placed, or the hierarchy would cycle.
        let result = DeviceCatalog.standard().includingCells(from: library, activeCellName: "INV")
        #expect(result.catalog.device(for: DeviceCatalog.cellKindID(for: "INV")) == nil)
        #expect(result.catalog.device(for: DeviceCatalog.cellKindID(for: "BUF_STAGE")) == nil)

        // Editing BUF_STAGE: INV is placeable.
        let result2 = DeviceCatalog.standard().includingCells(from: library, activeCellName: "BUF_STAGE")
        #expect(result2.catalog.device(for: DeviceCatalog.cellKindID(for: "INV")) != nil)
        #expect(result2.catalog.device(for: DeviceCatalog.cellKindID(for: "BUF_STAGE")) == nil)
    }

    @Test func brokenCellBecomesIssueNotCrash() {
        let orphan = PlacedComponent(deviceKindID: "port_input", name: "A", position: .zero)
        let broken = DesignCell(name: "BROKEN", schematic: SchematicDocument(
            components: [orphan], wires: []
        ))
        let library = CellLibrary(cells: [broken, makeInverterCell()])

        let result = DeviceCatalog.standard().includingCells(from: library, activeCellName: nil)
        #expect(result.issues.count == 1)
        #expect(result.issues.first?.cellName == "BROKEN")
        #expect(result.catalog.device(for: DeviceCatalog.cellKindID(for: "BROKEN")) == nil)
        #expect(result.catalog.device(for: DeviceCatalog.cellKindID(for: "INV")) != nil)
    }
}

// MARK: - Hierarchical netlist generation

@Suite("Hierarchical Netlist Generation")
struct HierarchicalNetlistTests {

    @Test func emitsSubcktWithCanonicalPorts() throws {
        let inv = makeInverterCell()
        let library = CellLibrary(cells: [inv])
        let netlist = try NetlistGenerator().generate(
            from: try makeHierarchicalTop(inv: inv),
            library: library,
            title: "Hierarchical Inverter",
            testbench: inverterTestbench
        )

        #expect(netlist.contains(".subckt INV A Y VDD VSS"))
        #expect(netlist.contains(".ends INV"))
        #expect(netlist.contains("X1 in out vdd 0 INV"))
        // Custom model cards inside a cell carry the cell prefix.
        #expect(netlist.contains(".model PMOS_INV_MP1 PMOS level=1"))
        #expect(netlist.contains(".model NMOS_INV_MN1 NMOS level=1"))
        #expect(netlist.contains(".tran"))
        #expect(netlist.hasSuffix(".end"))
    }

    @Test func nestedCellsEmitDeepestFirst() throws {
        // BUF instantiates INV twice; the netlist must define INV before BUF.
        let inv = makeInverterCell()
        let portA = PlacedComponent(deviceKindID: "port_input", name: "A", position: .zero)
        let portY = PlacedComponent(deviceKindID: "port_output", name: "Y", position: .zero)
        let portVdd = PlacedComponent(deviceKindID: "port_power", name: "VDD", position: .zero)
        let portVss = PlacedComponent(deviceKindID: "port_ground", name: "VSS", position: .zero)
        let x1 = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "INV"),
            name: "X1", position: .zero, cellName: "INV"
        )
        let x2 = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "INV"),
            name: "X2", position: .zero, cellName: "INV"
        )
        var wires: [Wire] = []
        wires += net(0, [(portA.id, "pin"), (x1.id, try cellPortID(inv, "A"))])
        wires += net(1, [(x1.id, try cellPortID(inv, "Y")), (x2.id, try cellPortID(inv, "A"))])
        wires += net(2, [(x2.id, try cellPortID(inv, "Y")), (portY.id, "pin")])
        wires += net(3, [(portVdd.id, "pin"), (x1.id, try cellPortID(inv, "VDD")), (x2.id, try cellPortID(inv, "VDD"))])
        wires += net(4, [(portVss.id, "pin"), (x1.id, try cellPortID(inv, "VSS")), (x2.id, try cellPortID(inv, "VSS"))])
        let buf = DesignCell(name: "BUF", schematic: SchematicDocument(
            components: [portA, portY, portVdd, portVss, x1, x2],
            wires: wires
        ))

        let xb = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "BUF"),
            name: "XB1", position: .zero, cellName: "BUF"
        )
        let vdd = PlacedComponent(deviceKindID: "vsource", name: "V1", position: .zero, parameters: ["dc": 3.3])
        let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: .zero)
        var topWires: [Wire] = []
        topWires += net(0, [(xb.id, try cellPortID(buf, "A"))], name: "in")
        topWires += net(1, [(xb.id, try cellPortID(buf, "Y"))], name: "out")
        topWires += net(2, [(vdd.id, "pos"), (xb.id, try cellPortID(buf, "VDD"))], name: "vdd")
        topWires += net(3, [(vdd.id, "neg"), (xb.id, try cellPortID(buf, "VSS")), (gnd.id, "gnd")])
        let top = SchematicDocument(components: [xb, vdd, gnd], wires: topWires)

        let library = CellLibrary(cells: [buf, inv])
        let netlist = try NetlistGenerator().generate(from: top, library: library, title: "Nested")

        let invRange = try #require(netlist.range(of: ".subckt INV"))
        let bufRange = try #require(netlist.range(of: ".subckt BUF"))
        #expect(invRange.lowerBound < bufRange.lowerBound)
        #expect(netlist.contains("X1 ") && netlist.contains("X2 "))
        #expect(netlist.contains("XB1 in out vdd 0 BUF"))
    }

    @Test func caseVariantCellReferencesEmitOneCanonicalSubckt() throws {
        var inv = makeInverterCell()
        inv.name = "inv"
        let x1 = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "INV"),
            name: "X1", position: .zero, cellName: "INV"
        )
        let x2 = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "inv"),
            name: "X2", position: .zero, cellName: "inv"
        )
        let top = SchematicDocument(components: [x1, x2], wires: [])

        let netlist = try NetlistGenerator().generate(
            from: top,
            library: CellLibrary(cells: [inv]),
            title: "Case Folded"
        )

        #expect(netlist.components(separatedBy: ".subckt inv").count == 2)
        #expect(netlist.contains("X1 nc_X1_A nc_X1_Y nc_X1_VDD nc_X1_VSS inv"))
        #expect(netlist.contains("X2 nc_X2_A nc_X2_Y nc_X2_VDD nc_X2_VSS inv"))
    }

    @Test func unknownCellReferenceThrows() {
        let ghost = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "GHOST"),
            name: "X1", position: .zero, cellName: "GHOST"
        )
        let document = SchematicDocument(components: [ghost], wires: net(0, [(ghost.id, "P")]))

        #expect(throws: NetlistGenerationError.unknownCellReference(parentCell: nil, cellName: "GHOST")) {
            try NetlistGenerator().generate(from: document)
        }
    }

    @Test func nonXInstanceNameThrows() {
        let instance = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "INV"),
            name: "U1", position: .zero, cellName: "INV"
        )
        let document = SchematicDocument(components: [instance], wires: net(0, [(instance.id, "A")]))
        let library = CellLibrary(cells: [makeInverterCell()])

        #expect(throws: NetlistGenerationError.invalidSubcircuitInstanceName("U1")) {
            try NetlistGenerator().generate(from: document, library: library)
        }
    }

    @Test func dependencyCycleThrows() {
        // A instantiates B, B instantiates A.
        func cellInstantiating(_ child: String, named name: String) -> DesignCell {
            let port = PlacedComponent(deviceKindID: "port_input", name: "P", position: .zero)
            let instance = PlacedComponent(
                deviceKindID: DeviceCatalog.cellKindID(for: child),
                name: "X1", position: .zero, cellName: child
            )
            var wires = net(0, [(port.id, "pin"), (instance.id, "P")])
            wires += net(1, [(instance.id, "Q")])
            return DesignCell(name: name, schematic: SchematicDocument(
                components: [port, instance], wires: wires
            ))
        }
        let library = CellLibrary(cells: [
            cellInstantiating("B", named: "A"),
            cellInstantiating("A", named: "B"),
        ])
        let top = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "A"),
            name: "X1", position: .zero, cellName: "A"
        )
        let document = SchematicDocument(components: [top], wires: net(0, [(top.id, "P")]))

        #expect(throws: NetlistGenerationError.dependencyCycle(["A", "B", "A"])) {
            try NetlistGenerator().generate(from: document, library: library)
        }
    }

    @Test func invalidInterfaceSurfacesUnderlyingError() {
        let orphan = PlacedComponent(deviceKindID: "port_input", name: "A", position: .zero)
        let broken = DesignCell(name: "BROKEN", schematic: SchematicDocument(
            components: [orphan], wires: []
        ))
        let instance = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "BROKEN"),
            name: "X1", position: .zero, cellName: "BROKEN"
        )
        let document = SchematicDocument(components: [instance], wires: net(0, [(instance.id, "A")]))
        let library = CellLibrary(cells: [broken])

        #expect(throws: NetlistGenerationError.invalidCellInterface(
            cellName: "BROKEN",
            underlying: .unconnectedPort("A")
        )) {
            try NetlistGenerator().generate(from: document, library: library)
        }
    }

    @Test func unknownDeviceKindThrows() {
        let mystery = PlacedComponent(deviceKindID: "warp_core", name: "W1", position: .zero)
        let document = SchematicDocument(components: [mystery], wires: net(0, [(mystery.id, "pin")]))

        #expect(throws: NetlistGenerationError.unknownDeviceKind(
            instanceName: "W1", deviceKindID: "warp_core"
        )) {
            try NetlistGenerator().generate(from: document)
        }
    }

    @Test func childPortRenameKeepsParentWiringConnected() throws {
        // The trust proof for stable pin ids: a parent wires X1 to a child
        // port by the port's stable id. Renaming that child port changes the
        // `.subckt` node name but must leave X1's connection intact — no
        // unconnected-pin placeholder, same net on the X line.
        let inID = UUID()
        let outID = UUID()
        let original = makeRenamableCell(inputName: "P", inputID: inID, outputID: outID)
        let renamed = makeRenamableCell(inputName: "IN", inputID: inID, outputID: outID)

        let x1 = PlacedComponent(
            deviceKindID: DeviceCatalog.cellKindID(for: "RC"),
            name: "X1", position: .zero, cellName: "RC"
        )
        var wires: [Wire] = []
        wires += net(0, [(x1.id, inID.uuidString)], name: "drive")
        wires += net(1, [(x1.id, outID.uuidString)], name: "sense")
        let top = SchematicDocument(components: [x1], wires: wires)

        let beforeRename = try NetlistGenerator().generate(
            from: top, library: CellLibrary(cells: [original]), title: "Before"
        )
        #expect(beforeRename.contains(".subckt RC P Q"))
        #expect(beforeRename.contains("X1 drive sense RC"))

        let afterRename = try NetlistGenerator().generate(
            from: top, library: CellLibrary(cells: [renamed]), title: "After"
        )
        // The port's SPICE name changed on the .subckt line ...
        #expect(afterRename.contains(".subckt RC IN Q"))
        // ... but the parent wiring is untouched: same X line, no placeholder.
        #expect(afterRename.contains("X1 drive sense RC"))
        #expect(!afterRename.contains("nc_X1"))
    }

    @Test func duplicateInstanceNameThrows() {
        // Two emitted devices sharing an instance name would write an
        // ambiguous netlist; generation must reject it instead.
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero, parameters: ["r": 1000])
        let r2 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero, parameters: ["r": 2000])
        let document = SchematicDocument(components: [r1, r2], wires: [])

        #expect(throws: NetlistGenerationError.duplicateInstanceName(cellName: nil, instanceName: "R1")) {
            try NetlistGenerator().generate(from: document)
        }
    }
}

// MARK: - Simulation equivalence

@Suite("Hierarchical Simulation Equivalence")
struct HierarchicalSimulationTests {

    /// The trust anchor for the whole hierarchy feature: the same inverter
    /// simulated through a `.subckt` and flat must produce the same physics.
    @Test(.timeLimit(.minutes(2)))
    func hierarchicalInverterMatchesFlat() async throws {
        let inv = makeInverterCell()
        let library = CellLibrary(cells: [inv])
        let hierarchicalNetlist = try NetlistGenerator().generate(
            from: try makeHierarchicalTop(inv: inv),
            library: library,
            title: "Hierarchical",
            testbench: inverterTestbench
        )
        let flatNetlist = try NetlistGenerator().generate(
            from: makeFlatTop(),
            title: "Flat",
            testbench: inverterTestbench
        )

        let hierarchical = try await SimulationService().runSPICE(
            source: hierarchicalNetlist, fileName: "hier-inv.cir"
        )
        let flat = try await SimulationService().runSPICE(
            source: flatNetlist, fileName: "flat-inv.cir"
        )
        #expect(hierarchical.status == .completed)
        #expect(flat.status == .completed)

        let hierWave = try #require(hierarchical.waveform)
        let flatWave = try #require(flat.waveform)
        let hierOut = try #require(hierWave.realWaveform(named: outVariableName(in: hierWave)))
        let flatOut = try #require(flatWave.realWaveform(named: outVariableName(in: flatWave)))

        #expect(hierOut.count == flatOut.count)
        let count = min(hierOut.count, flatOut.count)
        #expect(count > 100)

        var maxDelta = 0.0
        let hierPoints = hierOut.points
        let flatPoints = flatOut.points
        for i in 0..<count {
            maxDelta = max(maxDelta, abs(hierPoints[i].value - flatPoints[i].value))
        }
        #expect(maxDelta < 5e-3, "max |Δv(out)| = \(maxDelta)")
    }

    private func outVariableName(in waveform: WaveformData) throws -> String {
        let name = waveform.variables.first { $0.name.lowercased() == "v(out)" }?.name
        return try #require(name, "v(out) missing; variables: \(waveform.variables.map(\.name))")
    }
}

// MARK: - Circuit layout guard

@Suite("Circuit Layout Hierarchy Guard")
struct CircuitLayoutHierarchyTests {

    @Test @MainActor func cellInstancesAreRejectedExplicitly() throws {
        let document = try makeHierarchicalTop(inv: makeInverterCell())
        #expect(throws: CircuitLayoutSynthesisError.hierarchicalCellsUnsupported(instanceNames: ["X1"])) {
            try CircuitLayoutSynthesizer().generate(from: document, catalog: .standard())
        }
    }

    @Test @MainActor func portsAreSkippedNotPlaced() throws {
        // A leaf cell body (ports + devices) must lay out the devices and
        // ignore the boundary ports rather than failing or placing them.
        let document = makeInverterCell().schematic
        let output = try CircuitLayoutSynthesizer().generate(from: document, catalog: .standard())
        #expect(output.designUnit.componentToInstance.count == 2)
        #expect(!output.skippedComponents.contains("A"))
    }
}
