import SwiftUI
import CircuitStudioCore

/// Factory for creating SchematicViewModel instances populated with sample data for SwiftUI Previews.
@MainActor
public enum SchematicPreview {

    /// Empty canvas with default tools.
    public static func emptyViewModel() -> SchematicViewModel {
        SchematicViewModel()
    }

    /// Canvas with a properly wired voltage divider circuit ready for simulation.
    ///
    /// Circuit topology:
    /// ```
    ///        in          out
    ///   V1+ ──── R1 ──┬── R2 ──┐
    ///                  │        │
    ///   V1- ───────────┴── GND ─┘
    ///        (net "0")
    /// ```
    ///
    /// Nets:
    /// - "in" (auto): V1.pos, R1.pos
    /// - "out" (label): R1.neg, R2.pos
    /// - "0" (ground): V1.neg, R2.neg, GND.gnd
    public static func voltageDividerViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        // --- Components ---
        // Pin world positions are component.position + portDefinition.position
        //   vsource:  pos=(0,-30), neg=(0,+30)
        //   resistor: pos=(0,-30), neg=(0,+30)
        //   ground:   gnd=(0,-10)

        let v1 = PlacedComponent(
            deviceKindID: "vsource",
            name: "V1",
            position: CGPoint(x: 100, y: 150),       // pos@(100,120) neg@(100,180)
            parameters: ["dc": 5]
        )
        let r1 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R1",
            position: CGPoint(x: 200, y: 100),       // pos@(200,70) neg@(200,130)
            parameters: ["r": 1000]
        )
        let r2 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R2",
            position: CGPoint(x: 200, y: 200),       // pos@(200,170) neg@(200,230)
            parameters: ["r": 1000]
        )
        let gnd = PlacedComponent(
            deviceKindID: "ground",
            name: "GND1",
            position: CGPoint(x: 100, y: 250)        // gnd@(100,240)
        )

        vm.document.components = [v1, r1, r2, gnd]

        // --- Wires with PinReferences ---
        // Net "in": V1.pos → R1.pos
        let w1 = Wire(
            startPoint: CGPoint(x: 100, y: 120),
            endPoint: CGPoint(x: 200, y: 70),
            startPin: PinReference(componentID: v1.id, portID: "pos"),
            endPin: PinReference(componentID: r1.id, portID: "pos")
        )

        // Net "out": R1.neg → junction(200,150)
        let w2a = Wire(
            startPoint: CGPoint(x: 200, y: 130),
            endPoint: CGPoint(x: 200, y: 150),
            startPin: PinReference(componentID: r1.id, portID: "neg")
        )
        // Net "out": R2.pos → junction(200,150)
        let w2b = Wire(
            startPoint: CGPoint(x: 200, y: 170),
            endPoint: CGPoint(x: 200, y: 150),
            startPin: PinReference(componentID: r2.id, portID: "pos")
        )

        // Net "0": R2.neg → junction(100,230)
        let w3 = Wire(
            startPoint: CGPoint(x: 200, y: 230),
            endPoint: CGPoint(x: 100, y: 230),
            startPin: PinReference(componentID: r2.id, portID: "neg")
        )
        // Net "0": V1.neg → junction(100,230)
        let w4 = Wire(
            startPoint: CGPoint(x: 100, y: 180),
            endPoint: CGPoint(x: 100, y: 230),
            startPin: PinReference(componentID: v1.id, portID: "neg")
        )
        // Net "0": junction(100,230) → GND.gnd
        let w5 = Wire(
            startPoint: CGPoint(x: 100, y: 230),
            endPoint: CGPoint(x: 100, y: 240),
            endPin: PinReference(componentID: gnd.id, portID: "gnd")
        )

        vm.document.wires = [w1, w2a, w2b, w3, w4, w5]

        // Net label "out" at the junction point between R1 and R2
        vm.document.labels = [
            NetLabel(name: "out", position: CGPoint(x: 200, y: 150))
        ]

        return vm
    }

    /// ViewModel with a selected component (for PropertyInspector preview).
    public static func selectedComponentViewModel() -> SchematicViewModel {
        let vm = voltageDividerViewModel()
        if let firstID = vm.document.components.first?.id {
            vm.document.selection = [firstID]
        }
        return vm
    }

    /// ViewModel with a selected wire (for PropertyInspector preview).
    public static func selectedWireViewModel() -> SchematicViewModel {
        let vm = voltageDividerViewModel()
        if let firstWire = vm.document.wires.first {
            vm.document.selection = [firstWire.id]
        }
        return vm
    }
}
