import Testing
import CoreGraphics
@testable import CircuitStudioCore
@testable import SchematicEditor

@Suite("Design Model Tests")
struct DesignModelTests {

    @Test func createDesign() {
        let design = Design(name: "Test Circuit")
        #expect(design.name == "Test Circuit")
        #expect(design.components.isEmpty)
        #expect(design.nets.isEmpty)
    }

    @Test func createComponent() {
        let component = Component(
            name: "R1",
            typeName: "resistor",
            pins: [
                Pin(name: "1"),
                Pin(name: "2"),
            ],
            parameters: ["r": 1000]
        )
        #expect(component.name == "R1")
        #expect(component.typeName == "resistor")
        #expect(component.pins.count == 2)
        #expect(component.parameters["r"] == 1000)
    }

    @Test func createTestbench() {
        let tb = Testbench(
            name: "AC Test",
            analysisCommands: [
                .ac(ACSpec(scaleType: .decade, numberOfPoints: 10, startFrequency: 1, stopFrequency: 1e6)),
            ]
        )
        #expect(tb.name == "AC Test")
        #expect(tb.analysisCommands.count == 1)
    }

    @Test func sweepValuesLinear() {
        let sweep = SweepValues.linear(start: 0, stop: 1, step: 0.25)
        let values = sweep.allValues
        #expect(values.count == 5)
        #expect(values.first == 0)
        #expect(values.last == 1.0)
    }
}

@Suite("Device Catalog Tests")
struct DeviceCatalogTests {

    @Test func standardCatalogHasDevices() {
        let catalog = DeviceCatalog.standard()
        #expect(!catalog.allDevices().isEmpty)
        #expect(catalog.device(for: "resistor") != nil)
        #expect(catalog.device(for: "capacitor") != nil)
        #expect(catalog.device(for: "vsource") != nil)
        #expect(catalog.device(for: "ground") != nil)
    }

    @Test func deviceCategories() {
        let catalog = DeviceCatalog.standard()
        let passives = catalog.devices(in: .passive)
        #expect(passives.contains(where: { $0.id == "resistor" }))
        #expect(passives.contains(where: { $0.id == "capacitor" }))
        #expect(passives.contains(where: { $0.id == "inductor" }))
    }

    @Test func deviceKindHasPortDefinitions() {
        let catalog = DeviceCatalog.standard()
        let resistor = catalog.device(for: "resistor")!
        #expect(resistor.portDefinitions.count == 2)
        #expect(resistor.spicePrefix == "R")
    }

    @Test func deviceKindHasParameterSchema() {
        let catalog = DeviceCatalog.standard()
        let resistor = catalog.device(for: "resistor")!
        #expect(!resistor.parameterSchema.isEmpty)
        let rParam = resistor.parameterSchema.first(where: { $0.id == "r" })
        #expect(rParam != nil)
        #expect(rParam?.isRequired == true)
    }

    @Test func mosfetHasBulkPort() {
        let catalog = DeviceCatalog.standard()
        let nmos = catalog.device(for: "nmos_l1")!
        #expect(nmos.portDefinitions.count == 4)
        #expect(nmos.portDefinitions.map(\.id).contains("bulk"))
        #expect(nmos.modelType == "NMOS")

        let pmos = catalog.device(for: "pmos_l1")!
        #expect(pmos.portDefinitions.count == 4)
        #expect(pmos.portDefinitions.map(\.id).contains("bulk"))
        #expect(pmos.modelType == "PMOS")
    }

    @Test func semiconductorModelTypes() {
        let catalog = DeviceCatalog.standard()
        #expect(catalog.device(for: "diode")?.modelType == "D")
        #expect(catalog.device(for: "npn")?.modelType == "NPN")
        #expect(catalog.device(for: "pnp")?.modelType == "PNP")
        #expect(catalog.device(for: "nmos_l1")?.modelType == "NMOS")
        #expect(catalog.device(for: "pmos_l1")?.modelType == "PMOS")
    }

    @Test func nonSemiconductorHasNoModelType() {
        let catalog = DeviceCatalog.standard()
        #expect(catalog.device(for: "resistor")?.modelType == nil)
        #expect(catalog.device(for: "capacitor")?.modelType == nil)
        #expect(catalog.device(for: "vsource")?.modelType == nil)
        #expect(catalog.device(for: "vcvs")?.modelType == nil)
    }

    @Test func mosfetParameterClassification() {
        let catalog = DeviceCatalog.standard()
        let nmos = catalog.device(for: "nmos_l1")!

        // Instance parameters
        let wParam = nmos.parameterSchema.first(where: { $0.id == "w" })!
        #expect(wParam.isRequired == true)
        #expect(wParam.isModelParameter == false)

        let lParam = nmos.parameterSchema.first(where: { $0.id == "l" })!
        #expect(lParam.isRequired == true)
        #expect(lParam.isModelParameter == false)

        // Model parameters
        let vtoParam = nmos.parameterSchema.first(where: { $0.id == "vto" })!
        #expect(vtoParam.isModelParameter == true)

        let kpParam = nmos.parameterSchema.first(where: { $0.id == "kp" })!
        #expect(kpParam.isModelParameter == true)
    }
}

@Suite("Design Service Tests")
struct DesignServiceTests {

    @Test func validateEmptyDocument() {
        let service = DesignService()
        let document = SchematicDocument()
        let diagnostics = service.validate(document)
        #expect(diagnostics.contains(where: { $0.message.contains("no components") }))
    }

    @Test func validateMissingGround() {
        let service = DesignService()
        let document = SchematicDocument(
            components: [
                PlacedComponent(
                    deviceKindID: "resistor",
                    name: "R1",
                    position: .zero,
                    parameters: ["r": 1000]
                ),
            ]
        )
        let diagnostics = service.validate(document)
        #expect(diagnostics.contains(where: { $0.message.contains("ground") }))
    }

    @Test func validateDuplicateNames() {
        let service = DesignService()
        let document = SchematicDocument(
            components: [
                PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero, parameters: ["r": 1000]),
                PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 100, y: 0), parameters: ["r": 2000]),
            ]
        )
        let diagnostics = service.validate(document)
        #expect(diagnostics.contains(where: { $0.message.contains("Duplicate") }))
    }

    @Test func validateUnknownDeviceType() {
        let service = DesignService()
        let document = SchematicDocument(
            components: [
                PlacedComponent(deviceKindID: "unknown_device", name: "X1", position: .zero),
            ]
        )
        let diagnostics = service.validate(document)
        #expect(diagnostics.contains(where: { $0.severity == .info && $0.message.contains("Unknown") }))
    }
}

@Suite("Net Extractor Tests")
struct NetExtractorTests {

    @Test func extractSimpleNet() {
        let compA = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        let compB = PlacedComponent(deviceKindID: "resistor", name: "R2", position: CGPoint(x: 100, y: 0))

        let wire = Wire(
            startPoint: CGPoint(x: 20, y: 0),
            endPoint: CGPoint(x: 80, y: 0),
            startPin: PinReference(componentID: compA.id, portID: "neg"),
            endPin: PinReference(componentID: compB.id, portID: "pos")
        )

        let document = SchematicDocument(components: [compA, compB], wires: [wire])
        let extractor = NetExtractor()
        let nets = extractor.extract(from: document)

        // Should have at least one net connecting the two components
        #expect(!nets.isEmpty)
        let net = nets.first(where: { $0.connections.count == 2 })
        #expect(net != nil)
    }

    @Test func extractGroundNet() {
        let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: CGPoint(x: 0, y: 50))
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)

        let wire = Wire(
            startPoint: CGPoint(x: 0, y: 20),
            endPoint: CGPoint(x: 0, y: 50),
            startPin: PinReference(componentID: r1.id, portID: "neg"),
            endPin: PinReference(componentID: gnd.id, portID: "gnd")
        )

        let document = SchematicDocument(components: [r1, gnd], wires: [wire])
        let extractor = NetExtractor()
        let nets = extractor.extract(from: document)

        let groundNet = nets.first(where: { $0.name == "0" })
        #expect(groundNet != nil)
    }
}

@Suite("Netlist Generator Tests")
struct NetlistGeneratorTests {

    @Test func generateSimpleNetlist() {
        let v1 = PlacedComponent(deviceKindID: "vsource", name: "V1", position: .zero, parameters: ["dc": 5])
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 100, y: 0), parameters: ["r": 1000])
        let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: CGPoint(x: 50, y: 100))

        let wireVR = Wire(
            startPoint: CGPoint(x: 0, y: -20),
            endPoint: CGPoint(x: 100, y: -20),
            startPin: PinReference(componentID: v1.id, portID: "pos"),
            endPin: PinReference(componentID: r1.id, portID: "pos")
        )
        let wireRGnd = Wire(
            startPoint: CGPoint(x: 100, y: 20),
            endPoint: CGPoint(x: 50, y: 100),
            startPin: PinReference(componentID: r1.id, portID: "neg"),
            endPin: PinReference(componentID: gnd.id, portID: "gnd")
        )
        let wireVGnd = Wire(
            startPoint: CGPoint(x: 0, y: 20),
            endPoint: CGPoint(x: 50, y: 100),
            startPin: PinReference(componentID: v1.id, portID: "neg"),
            endPin: PinReference(componentID: gnd.id, portID: "gnd")
        )

        let document = SchematicDocument(
            components: [v1, r1, gnd],
            wires: [wireVR, wireRGnd, wireVGnd]
        )
        let generator = NetlistGenerator()
        let netlist = generator.generate(from: document, title: "Test Circuit")
        #expect(netlist.contains("V1"))
        #expect(netlist.contains("R1"))
        #expect(netlist.contains(".end"))
    }

    @Test func generateWithAnalysis() {
        let document = SchematicDocument()
        let testbench = Testbench(
            name: "AC",
            analysisCommands: [
                .ac(ACSpec(scaleType: .decade, numberOfPoints: 10, startFrequency: 1, stopFrequency: 1e6)),
            ]
        )
        let generator = NetlistGenerator()
        let netlist = generator.generate(from: document, title: "AC Test", testbench: testbench)
        #expect(netlist.contains(".ac dec"))
        #expect(netlist.contains(".end"))
    }

    @Test func generateTranAnalysis() {
        let document = SchematicDocument()
        let testbench = Testbench(
            name: "Tran",
            analysisCommands: [
                .tran(TranSpec(stopTime: 1e-3, stepTime: 1e-6)),
            ]
        )
        let generator = NetlistGenerator()
        let netlist = generator.generate(from: document, title: "Tran Test", testbench: testbench)
        #expect(netlist.contains(".tran"))
        #expect(netlist.contains(".end"))
    }

    @Test func generateControlledSourceNetlist() {
        let e1 = PlacedComponent(
            deviceKindID: "vcvs",
            name: "E1",
            position: .zero,
            parameters: ["e": 10.0]
        )
        let document = SchematicDocument(components: [e1])
        let generator = NetlistGenerator()
        let netlist = generator.generate(from: document, title: "VCVS Test")

        // VCVS should output bare gain value, not "e=10"
        #expect(netlist.contains("E1"))
        #expect(netlist.contains("10"))
        #expect(!netlist.contains("e=10"))
    }

    @Test func generateMOSFETNetlist() {
        let m1 = PlacedComponent(
            deviceKindID: "nmos_l1",
            name: "M1",
            position: .zero,
            parameters: ["w": 10e-6, "l": 1e-6, "vto": 0.7, "kp": 110e-6]
        )
        let document = SchematicDocument(components: [m1])
        let generator = NetlistGenerator()
        let netlist = generator.generate(from: document, title: "MOSFET Test")

        // Instance line should have model name and W=, L= instance params
        #expect(netlist.contains("M1"))
        #expect(netlist.contains("NMOS_M1"))
        #expect(netlist.contains("W="))
        #expect(netlist.contains("L="))

        // .model card should be generated
        #expect(netlist.contains(".model NMOS_M1 NMOS level=1"))
        #expect(netlist.contains("vto="))
        #expect(netlist.contains("kp="))
    }

    @Test func generateDiodeNetlist() {
        let d1 = PlacedComponent(
            deviceKindID: "diode",
            name: "D1",
            position: .zero,
            parameters: ["is": 1e-14, "n": 1.0]
        )
        let document = SchematicDocument(components: [d1])
        let generator = NetlistGenerator()
        let netlist = generator.generate(from: document, title: "Diode Test")

        #expect(netlist.contains("D1"))
        #expect(netlist.contains("D_D1"))
        #expect(netlist.contains(".model D_D1 D"))
    }

    @Test func generateBJTNetlist() {
        let q1 = PlacedComponent(
            deviceKindID: "npn",
            name: "Q1",
            position: .zero,
            parameters: ["bf": 100, "is": 1e-14]
        )
        let document = SchematicDocument(components: [q1])
        let generator = NetlistGenerator()
        let netlist = generator.generate(from: document, title: "BJT Test")

        #expect(netlist.contains("Q1"))
        #expect(netlist.contains("NPN_Q1"))
        #expect(netlist.contains(".model NPN_Q1 NPN"))
    }
}

@Suite("Simulation Service Tests")
struct SimulationServiceTests {

    @Test(.timeLimit(.minutes(1)))
    func runOPAnalysis() async throws {
        let service = SimulationService()
        let source = """
        Simple voltage divider
        V1 in 0 5
        R1 in out 1k
        R2 out 0 1k
        .op
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)
        #expect(result.waveform != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func runTranAnalysis() async throws {
        let service = SimulationService()
        let source = """
        RC circuit
        V1 in 0 PULSE(0 5 0 1n 1n 5u 10u)
        R1 in out 1k
        C1 out 0 1n
        .tran 100n 20u
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)
        #expect(result.waveform != nil)
        if let waveform = result.waveform {
            #expect(waveform.pointCount > 0)
            #expect(waveform.sweepVariable.name == "time")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func runTranAnalysisPreviewCircuit() async throws {
        let service = SimulationService()
        let source = """
        * RC Lowpass Filter
        V1 in 0 PULSE(0 5 1u 0.1u 0.1u 10u 20u)
        R1 in out 1k
        C1 out 0 1n
        .tran 0.1u 20u
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)
        #expect(result.waveform != nil)
        if let waveform = result.waveform {
            #expect(waveform.pointCount > 0)
            #expect(waveform.sweepVariable.name == "time")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func runACAnalysis() async throws {
        let service = SimulationService()
        let source = """
        RC lowpass filter
        V1 in 0 AC 1
        R1 in out 1k
        C1 out 0 1n
        .ac dec 10 1 1e9
        .end
        """

        let result = try await service.runSPICE(source: source, fileName: nil)
        #expect(result.status == .completed)
        #expect(result.waveform != nil)
        if let waveform = result.waveform {
            #expect(waveform.isComplex)
            #expect(waveform.pointCount > 0)

            // V(in) should be ~0 dB (source node, magnitude ~1V)
            if let inIdx = waveform.variableIndex(named: "V(1)") {
                let mag = waveform.magnitudeDB(variable: inIdx, point: 0)
                #expect(mag != nil)
                if let db = mag {
                    #expect(abs(db) < 1.0, Comment(rawValue: "V(in) at low freq should be ~0 dB, got \(db)"))
                }
            }

            // V(out) at low freq should also be ~0 dB (below cutoff)
            if let outIdx = waveform.variableIndex(named: "V(2)") {
                let magLow = waveform.magnitudeDB(variable: outIdx, point: 0)
                #expect(magLow != nil)
                if let db = magLow {
                    #expect(abs(db) < 1.0, Comment(rawValue: "V(out) at 1 Hz should be ~0 dB, got \(db)"))
                }

                // V(out) at high freq should be well below 0 dB (above cutoff ~159 kHz)
                let lastPoint = waveform.pointCount - 1
                let magHigh = waveform.magnitudeDB(variable: outIdx, point: lastPoint)
                if let db = magHigh {
                    #expect(db < -20.0, Comment(rawValue: "V(out) at 1 GHz should be < -20 dB, got \(db)"))
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func runExplicitAnalysisCommand() async throws {
        let service = SimulationService()
        let source = """
        Voltage divider
        V1 in 0 5
        R1 in out 1k
        R2 out 0 1k
        .end
        """

        let result = try await service.runAnalysis(
            source: source,
            fileName: nil,
            command: .op
        )
        #expect(result.status == .completed)
    }
}

@Suite("SchematicViewModel Tests")
struct SchematicViewModelTests {

    @Test @MainActor func nameCounterNoPrefixCollision() {
        let vm = SchematicViewModel()

        // NPN and PNP share spicePrefix "Q" — counters should not collide
        #expect(vm.nextComponentName(for: "npn") == "Q1")
        #expect(vm.nextComponentName(for: "pnp") == "Q2")

        // NMOS and PMOS share spicePrefix "M"
        #expect(vm.nextComponentName(for: "nmos_l1") == "M1")
        #expect(vm.nextComponentName(for: "pmos_l1") == "M2")

        // Independent prefixes still start at 1
        #expect(vm.nextComponentName(for: "resistor") == "R1")
        #expect(vm.nextComponentName(for: "capacitor") == "C1")
    }
}

// MARK: - UndoStack Tests

@Suite("UndoStack Tests")
struct UndoStackTests {

    @Test func undoRestoresPreviousState() {
        var stack = UndoStack()
        let doc0 = SchematicDocument()
        var doc1 = SchematicDocument()
        doc1.components.append(PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero))

        stack.record(doc0)
        // Undo from doc1 should yield doc0
        let restored = stack.undo(current: doc1)
        #expect(restored != nil)
        #expect(restored!.components.isEmpty)
    }

    @Test func redoRestoresUndoneState() {
        var stack = UndoStack()
        let doc0 = SchematicDocument()
        var doc1 = SchematicDocument()
        doc1.components.append(PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero))

        stack.record(doc0)
        let undone = stack.undo(current: doc1)!
        // Redo from undone should yield doc1
        let redone = stack.redo(current: undone)
        #expect(redone != nil)
        #expect(redone!.components.count == 1)
    }

    @Test func newActionClearsRedoStack() {
        var stack = UndoStack()
        let doc0 = SchematicDocument()
        var doc1 = SchematicDocument()
        doc1.components.append(PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero))

        stack.record(doc0)
        let undone = stack.undo(current: doc1)!
        // Recording a new action should clear redo
        stack.record(undone)
        #expect(!stack.canRedo)
    }

    @Test func maxDepthEnforced() {
        var stack = UndoStack(maxDepth: 3)
        let base = SchematicDocument()

        // Record 4 states (exceeds maxDepth of 3)
        for i in 0..<4 {
            var doc = SchematicDocument()
            doc.components.append(PlacedComponent(deviceKindID: "resistor", name: "R\(i)", position: .zero))
            stack.record(doc)
        }

        // Should be able to undo exactly 3 times
        #expect(stack.undo(current: base) != nil)
        #expect(stack.undo(current: base) != nil)
        #expect(stack.undo(current: base) != nil)
        #expect(stack.undo(current: base) == nil)
    }

    @Test func emptyUndoReturnsNil() {
        var stack = UndoStack()
        let doc = SchematicDocument()
        #expect(stack.undo(current: doc) == nil)
        #expect(!stack.canUndo)
        #expect(!stack.canRedo)
    }
}

// MARK: - Mirror Tests

@Suite("Mirror Tests")
struct MirrorTests {

    @Test @MainActor func mirrorXToggle() {
        let vm = SchematicViewModel()
        vm.document.components.append(PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero))
        vm.document.selection = [vm.document.components[0].id]

        #expect(vm.document.components[0].mirrorX == false)
        vm.mirrorSelectionX()
        #expect(vm.document.components[0].mirrorX == true)
        vm.mirrorSelectionX()
        #expect(vm.document.components[0].mirrorX == false)
    }

    @Test @MainActor func mirrorYToggle() {
        let vm = SchematicViewModel()
        vm.document.components.append(PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero))
        vm.document.selection = [vm.document.components[0].id]

        #expect(vm.document.components[0].mirrorY == false)
        vm.mirrorSelectionY()
        #expect(vm.document.components[0].mirrorY == true)
        vm.mirrorSelectionY()
        #expect(vm.document.components[0].mirrorY == false)
    }

    @Test @MainActor func pinWorldPositionWithMirror() {
        let vm = SchematicViewModel()
        let port = PortDefinition(id: "pos", displayName: "Positive", position: CGPoint(x: 0, y: -20))

        // No mirror
        let comp = PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 100, y: 100))
        let noMirror = vm.pinWorldPosition(port: port, component: comp)
        #expect(noMirror.x == 100)
        #expect(noMirror.y == 80)

        // mirrorX flips Y axis of port
        let compMX = PlacedComponent(deviceKindID: "resistor", name: "R2", position: CGPoint(x: 100, y: 100), mirrorX: true)
        let mirrored = vm.pinWorldPosition(port: port, component: compMX)
        #expect(mirrored.x == 100)
        #expect(mirrored.y == 120)

        // mirrorY flips X axis of port
        let portX = PortDefinition(id: "neg", displayName: "Negative", position: CGPoint(x: 10, y: 0))
        let compMY = PlacedComponent(deviceKindID: "resistor", name: "R3", position: CGPoint(x: 100, y: 100), mirrorY: true)
        let mirroredY = vm.pinWorldPosition(port: portX, component: compMY)
        #expect(mirroredY.x == 90)
        #expect(mirroredY.y == 100)
    }
}

// MARK: - Selection Tests

@Suite("Selection Tests")
struct SelectionTests {

    @Test @MainActor func toggleSelection() {
        let vm = SchematicViewModel()
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        let r2 = PlacedComponent(deviceKindID: "resistor", name: "R2", position: CGPoint(x: 100, y: 0))
        vm.document.components = [r1, r2]

        // Toggle adds
        vm.toggleSelection(r1.id)
        #expect(vm.document.selection.contains(r1.id))

        // Toggle again removes
        vm.toggleSelection(r1.id)
        #expect(!vm.document.selection.contains(r1.id))

        // Multi-toggle
        vm.toggleSelection(r1.id)
        vm.toggleSelection(r2.id)
        #expect(vm.document.selection.count == 2)
    }

    @Test @MainActor func selectAll() {
        let vm = SchematicViewModel()
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        let wire = Wire(startPoint: .zero, endPoint: CGPoint(x: 50, y: 0))
        let label = NetLabel(name: "net1", position: CGPoint(x: 25, y: 0))
        vm.document.components = [r1]
        vm.document.wires = [wire]
        vm.document.labels = [label]

        vm.selectAll()
        #expect(vm.document.selection.count == 3)
        #expect(vm.document.selection.contains(r1.id))
        #expect(vm.document.selection.contains(wire.id))
        #expect(vm.document.selection.contains(label.id))
    }

    @Test @MainActor func selectInRectEnclosed() {
        let vm = SchematicViewModel()
        // Component at (50,50) with symbol size ~40x80 (default resistor bounding box)
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 50, y: 50))
        // Component at (200,200) — outside selection rect
        let r2 = PlacedComponent(deviceKindID: "resistor", name: "R2", position: CGPoint(x: 200, y: 200))
        vm.document.components = [r1, r2]

        // Large rect should contain r1 only
        vm.selectInRect(CGRect(x: 0, y: 0, width: 150, height: 150), enclosedOnly: true)
        #expect(vm.document.selection.contains(r1.id))
        #expect(!vm.document.selection.contains(r2.id))
    }

    @Test @MainActor func selectInRectTouching() {
        let vm = SchematicViewModel()
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 50, y: 50))
        vm.document.components = [r1]

        // Small rect that intersects but doesn't fully enclose
        vm.selectInRect(CGRect(x: 40, y: 40, width: 15, height: 15), enclosedOnly: false)
        #expect(vm.document.selection.contains(r1.id))
    }
}

// MARK: - Copy/Paste Tests

@Suite("CopyPaste Tests")
struct CopyPasteTests {

    @Test @MainActor func copyAndPaste() {
        let vm = SchematicViewModel()
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 50, y: 50))
        vm.document.components = [r1]
        vm.document.selection = [r1.id]

        vm.copySelection()
        vm.paste(at: CGPoint(x: 100, y: 100))

        #expect(vm.document.components.count == 2)
        // Pasted component has new ID
        let pastedIDs = vm.document.components.map(\.id)
        #expect(pastedIDs[0] != pastedIDs[1])
    }

    @Test @MainActor func pasteRemapsWirePinReferences() {
        let vm = SchematicViewModel()
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 50, y: 50))
        let wire = Wire(
            startPoint: CGPoint(x: 50, y: 30),
            endPoint: CGPoint(x: 100, y: 30),
            startPin: PinReference(componentID: r1.id, portID: "pos")
        )
        vm.document.components = [r1]
        vm.document.wires = [wire]
        vm.document.selection = [r1.id, wire.id]

        vm.copySelection()
        vm.paste(at: CGPoint(x: 200, y: 200))

        // The pasted wire's startPin should reference the pasted component, not r1
        let pastedWire = vm.document.wires.last!
        #expect(pastedWire.startPin != nil)
        #expect(pastedWire.startPin!.componentID != r1.id)
        // The remapped ID should exist in the pasted components
        let pastedComp = vm.document.components.last!
        #expect(pastedWire.startPin!.componentID == pastedComp.id)
    }

    @Test @MainActor func pasteGeneratesNewNames() {
        let vm = SchematicViewModel()
        // Place via VM so the name counter is properly incremented
        vm.placeComponent(deviceKindID: "resistor", at: .zero)
        let r1id = vm.document.components[0].id
        vm.document.selection = [r1id]

        vm.copySelection()
        vm.paste(at: CGPoint(x: 50, y: 50))

        let names = vm.document.components.map(\.name)
        #expect(names[0] != names[1])
    }

    @Test @MainActor func cutRemovesOriginal() {
        let vm = SchematicViewModel()
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: .zero)
        vm.document.components = [r1]
        vm.document.selection = [r1.id]

        vm.cutSelection()

        #expect(vm.document.components.isEmpty)
        // Paste brings it back
        vm.paste(at: CGPoint(x: 100, y: 100))
        #expect(vm.document.components.count == 1)
    }
}
