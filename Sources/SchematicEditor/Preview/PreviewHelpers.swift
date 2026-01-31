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
        // Net "in": V1.pos → corner(100,70) → R1.pos (L-shaped, orthogonal)
        let w1a = Wire(
            startPoint: CGPoint(x: 100, y: 120),
            endPoint: CGPoint(x: 100, y: 70),
            startPin: PinReference(componentID: v1.id, portID: "pos")
        )
        let w1b = Wire(
            startPoint: CGPoint(x: 100, y: 70),
            endPoint: CGPoint(x: 200, y: 70),
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

        vm.document.wires = [w1a, w1b, w2a, w2b, w3, w4, w5]

        // Net label "out" at the junction point between R1 and R2
        vm.document.labels = [
            NetLabel(name: "out", position: CGPoint(x: 200, y: 150))
        ]

        vm.recomputeJunctions()
        return vm
    }

    /// Canvas with a properly wired RC lowpass filter circuit.
    ///
    /// Circuit topology:
    /// ```
    ///        in          out
    ///   V1+ ──── R1 ──┬── C1+
    ///                  │
    ///   V1- ───────────┴── C1- ── GND
    ///        (net "0")
    /// ```
    ///
    /// Nets:
    /// - "in" (auto): V1.pos, R1.pos
    /// - "out" (label): R1.neg, C1.pos
    /// - "0" (ground): V1.neg, C1.neg, GND.gnd
    public static func rcLowpassViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let v1 = PlacedComponent(
            deviceKindID: "vsource",
            name: "V1",
            position: CGPoint(x: 100, y: 150),       // pos@(100,120) neg@(100,180)
            parameters: ["dc": 0, "ac": 1]
        )
        let r1 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R1",
            position: CGPoint(x: 200, y: 100),       // pos@(200,70) neg@(200,130)
            parameters: ["r": 1000]
        )
        let c1 = PlacedComponent(
            deviceKindID: "capacitor",
            name: "C1",
            position: CGPoint(x: 200, y: 200),       // pos@(200,170) neg@(200,230)
            parameters: ["c": 1e-6]
        )
        let gnd = PlacedComponent(
            deviceKindID: "ground",
            name: "GND1",
            position: CGPoint(x: 100, y: 250)        // gnd@(100,240)
        )

        vm.document.components = [v1, r1, c1, gnd]

        // Net "in": V1.pos → corner(100,70) → R1.pos (L-shaped, orthogonal)
        let w1a = Wire(
            startPoint: CGPoint(x: 100, y: 120),
            endPoint: CGPoint(x: 100, y: 70),
            startPin: PinReference(componentID: v1.id, portID: "pos")
        )
        let w1b = Wire(
            startPoint: CGPoint(x: 100, y: 70),
            endPoint: CGPoint(x: 200, y: 70),
            endPin: PinReference(componentID: r1.id, portID: "pos")
        )
        // Net "out": R1.neg → junction(200,150)
        let w2a = Wire(
            startPoint: CGPoint(x: 200, y: 130),
            endPoint: CGPoint(x: 200, y: 150),
            startPin: PinReference(componentID: r1.id, portID: "neg")
        )
        // Net "out": C1.pos → junction(200,150)
        let w2b = Wire(
            startPoint: CGPoint(x: 200, y: 170),
            endPoint: CGPoint(x: 200, y: 150),
            startPin: PinReference(componentID: c1.id, portID: "pos")
        )
        // Net "0": C1.neg → junction(100,230)
        let w3 = Wire(
            startPoint: CGPoint(x: 200, y: 230),
            endPoint: CGPoint(x: 100, y: 230),
            startPin: PinReference(componentID: c1.id, portID: "neg")
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

        vm.document.wires = [w1a, w1b, w2a, w2b, w3, w4, w5]

        vm.document.labels = [
            NetLabel(name: "out", position: CGPoint(x: 200, y: 150))
        ]

        vm.recomputeJunctions()
        return vm
    }

    /// Canvas with an RC circuit driven by a PULSE source for transient analysis.
    ///
    /// Circuit topology (same as RC lowpass but with PULSE source):
    /// ```
    ///        in          out
    ///   V1+ ──── R1 ──┬── C1+
    ///                  │
    ///   V1- ───────────┴── C1- ── GND
    ///        (net "0")
    /// ```
    ///
    /// PULSE: 0→5V, delay=1μs, rise=0.1μs, fall=0.1μs, width=10μs, period=20μs
    /// tau = R*C = 1kΩ × 1nF = 1μs
    /// .tran 0.1u 20u
    public static func rcPulseStepViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let v1 = PlacedComponent(
            deviceKindID: "vsource",
            name: "V1",
            position: CGPoint(x: 100, y: 150),       // pos@(100,120) neg@(100,180)
            parameters: [
                "pulse_v1": 0, "pulse_v2": 5,
                "pulse_td": 1e-6, "pulse_tr": 0.1e-6, "pulse_tf": 0.1e-6,
                "pulse_pw": 10e-6, "pulse_per": 20e-6,
            ]
        )
        let r1 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R1",
            position: CGPoint(x: 200, y: 100),       // pos@(200,70) neg@(200,130)
            parameters: ["r": 1000]
        )
        let c1 = PlacedComponent(
            deviceKindID: "capacitor",
            name: "C1",
            position: CGPoint(x: 200, y: 200),       // pos@(200,170) neg@(200,230)
            parameters: ["c": 1e-9]
        )
        let gnd = PlacedComponent(
            deviceKindID: "ground",
            name: "GND1",
            position: CGPoint(x: 100, y: 250)        // gnd@(100,240)
        )

        vm.document.components = [v1, r1, c1, gnd]

        // Wires (same topology as rcLowpassViewModel)
        let w1a = Wire(
            startPoint: CGPoint(x: 100, y: 120),
            endPoint: CGPoint(x: 100, y: 70),
            startPin: PinReference(componentID: v1.id, portID: "pos")
        )
        let w1b = Wire(
            startPoint: CGPoint(x: 100, y: 70),
            endPoint: CGPoint(x: 200, y: 70),
            endPin: PinReference(componentID: r1.id, portID: "pos")
        )
        let w2a = Wire(
            startPoint: CGPoint(x: 200, y: 130),
            endPoint: CGPoint(x: 200, y: 150),
            startPin: PinReference(componentID: r1.id, portID: "neg")
        )
        let w2b = Wire(
            startPoint: CGPoint(x: 200, y: 170),
            endPoint: CGPoint(x: 200, y: 150),
            startPin: PinReference(componentID: c1.id, portID: "pos")
        )
        let w3 = Wire(
            startPoint: CGPoint(x: 200, y: 230),
            endPoint: CGPoint(x: 100, y: 230),
            startPin: PinReference(componentID: c1.id, portID: "neg")
        )
        let w4 = Wire(
            startPoint: CGPoint(x: 100, y: 180),
            endPoint: CGPoint(x: 100, y: 230),
            startPin: PinReference(componentID: v1.id, portID: "neg")
        )
        let w5 = Wire(
            startPoint: CGPoint(x: 100, y: 230),
            endPoint: CGPoint(x: 100, y: 240),
            endPin: PinReference(componentID: gnd.id, portID: "gnd")
        )

        vm.document.wires = [w1a, w1b, w2a, w2b, w3, w4, w5]

        vm.document.labels = [
            NetLabel(name: "out", position: CGPoint(x: 200, y: 150))
        ]

        vm.recomputeJunctions()
        return vm
    }

    /// Canvas with a diode forward bias circuit for OP analysis.
    ///
    /// Circuit topology:
    /// ```
    ///        in         anode
    ///   V1+ ──── R1 ──── D1+ (anode)
    ///                     │
    ///   V1- ──────────── D1- (cathode) ── GND
    ///        (net "0")
    /// ```
    ///
    /// V(anode) ≈ 0.6–0.7V (forward diode drop)
    public static func diodeForwardBiasViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

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
        let d1 = PlacedComponent(
            deviceKindID: "diode",
            name: "D1",
            position: CGPoint(x: 200, y: 200),       // anode@(200,170) cathode@(200,230)
            parameters: ["is": 1e-14, "n": 1.0]
        )
        let gnd = PlacedComponent(
            deviceKindID: "ground",
            name: "GND1",
            position: CGPoint(x: 100, y: 250)        // gnd@(100,240)
        )

        vm.document.components = [v1, r1, d1, gnd]

        // Net "in": V1.pos → corner(100,70) → R1.pos
        let w1a = Wire(
            startPoint: CGPoint(x: 100, y: 120),
            endPoint: CGPoint(x: 100, y: 70),
            startPin: PinReference(componentID: v1.id, portID: "pos")
        )
        let w1b = Wire(
            startPoint: CGPoint(x: 100, y: 70),
            endPoint: CGPoint(x: 200, y: 70),
            endPin: PinReference(componentID: r1.id, portID: "pos")
        )
        // Net "anode": R1.neg → D1.anode
        let w2a = Wire(
            startPoint: CGPoint(x: 200, y: 130),
            endPoint: CGPoint(x: 200, y: 150),
            startPin: PinReference(componentID: r1.id, portID: "neg")
        )
        let w2b = Wire(
            startPoint: CGPoint(x: 200, y: 170),
            endPoint: CGPoint(x: 200, y: 150),
            startPin: PinReference(componentID: d1.id, portID: "anode")
        )
        // Net "0": D1.cathode → junction(100,230)
        let w3 = Wire(
            startPoint: CGPoint(x: 200, y: 230),
            endPoint: CGPoint(x: 100, y: 230),
            startPin: PinReference(componentID: d1.id, portID: "cathode")
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

        vm.document.wires = [w1a, w1b, w2a, w2b, w3, w4, w5]

        vm.document.labels = [
            NetLabel(name: "anode", position: CGPoint(x: 200, y: 150))
        ]

        vm.recomputeJunctions()
        return vm
    }

    /// RC circuit with load resistor for observing effective time constant change.
    ///
    /// Circuit topology:
    /// ```
    ///        in          out
    ///   V1+ ──── R1 ──┬── C1+ ──┐
    ///                  │         │
    ///                  ├── Rload+┤
    ///                  │         │
    ///   V1- ───────────┴── GND ──┘
    ///        (net "0")
    /// ```
    ///
    /// R1=1kΩ, C1=100pF, Rload=10kΩ
    /// τ_unloaded = R1×C1 = 100ns
    /// τ_loaded = (R1‖Rload)×C1 = 909Ω×100pF ≈ 90.9ns
    public static func rcLoadedStepViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let v1 = PlacedComponent(
            deviceKindID: "vsource",
            name: "V1",
            position: CGPoint(x: 100, y: 150),       // pos@(100,120) neg@(100,180)
            parameters: [
                "pulse_v1": 0, "pulse_v2": 5,
                "pulse_td": 10e-9, "pulse_tr": 1e-9, "pulse_tf": 1e-9,
                "pulse_pw": 500e-9, "pulse_per": 1e-6,
            ]
        )
        let r1 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R1",
            position: CGPoint(x: 250, y: 100),       // pos@(250,70) neg@(250,130)
            parameters: ["r": 1000]
        )
        let c1 = PlacedComponent(
            deviceKindID: "capacitor",
            name: "C1",
            position: CGPoint(x: 250, y: 230),       // pos@(250,200) neg@(250,260)
            parameters: ["c": 100e-12]
        )
        let rload = PlacedComponent(
            deviceKindID: "resistor",
            name: "R2",
            position: CGPoint(x: 350, y: 230),       // pos@(350,200) neg@(350,260)
            parameters: ["r": 10000]
        )
        let gnd = PlacedComponent(
            deviceKindID: "ground",
            name: "GND1",
            position: CGPoint(x: 100, y: 320)        // gnd@(100,310)
        )

        vm.document.components = [v1, r1, c1, rload, gnd]

        // Net "in": V1.pos → corner(100,70) → R1.pos
        let w1a = Wire(
            startPoint: CGPoint(x: 100, y: 120),
            endPoint: CGPoint(x: 100, y: 70),
            startPin: PinReference(componentID: v1.id, portID: "pos")
        )
        let w1b = Wire(
            startPoint: CGPoint(x: 100, y: 70),
            endPoint: CGPoint(x: 250, y: 70),
            endPin: PinReference(componentID: r1.id, portID: "pos")
        )
        // Net "out": R1.neg → junction(250,165)
        let w2a = Wire(
            startPoint: CGPoint(x: 250, y: 130),
            endPoint: CGPoint(x: 250, y: 165),
            startPin: PinReference(componentID: r1.id, portID: "neg")
        )
        // Net "out": C1.pos → junction(250,165)
        let w2b = Wire(
            startPoint: CGPoint(x: 250, y: 200),
            endPoint: CGPoint(x: 250, y: 165),
            startPin: PinReference(componentID: c1.id, portID: "pos")
        )
        // Net "out": junction(250,165) → corner(350,165) → Rload.pos
        let w2c = Wire(
            startPoint: CGPoint(x: 250, y: 165),
            endPoint: CGPoint(x: 350, y: 165)
        )
        let w2d = Wire(
            startPoint: CGPoint(x: 350, y: 165),
            endPoint: CGPoint(x: 350, y: 200),
            endPin: PinReference(componentID: rload.id, portID: "pos")
        )
        // Net "0": C1.neg → junction(250,290)
        let w3a = Wire(
            startPoint: CGPoint(x: 250, y: 260),
            endPoint: CGPoint(x: 250, y: 290),
            startPin: PinReference(componentID: c1.id, portID: "neg")
        )
        // Net "0": Rload.neg → (350,290)
        let w3b = Wire(
            startPoint: CGPoint(x: 350, y: 260),
            endPoint: CGPoint(x: 350, y: 290),
            startPin: PinReference(componentID: rload.id, portID: "neg")
        )
        // Net "0": ground rail (250,290) → (350,290)
        let w3c = Wire(
            startPoint: CGPoint(x: 250, y: 290),
            endPoint: CGPoint(x: 350, y: 290)
        )
        // Net "0": ground rail (100,290) → (250,290)
        let w3d = Wire(
            startPoint: CGPoint(x: 100, y: 290),
            endPoint: CGPoint(x: 250, y: 290)
        )
        // Net "0": V1.neg → (100,290)
        let w4 = Wire(
            startPoint: CGPoint(x: 100, y: 180),
            endPoint: CGPoint(x: 100, y: 290),
            startPin: PinReference(componentID: v1.id, portID: "neg")
        )
        // Net "0": (100,290) → GND.gnd
        let w5 = Wire(
            startPoint: CGPoint(x: 100, y: 290),
            endPoint: CGPoint(x: 100, y: 310),
            endPin: PinReference(componentID: gnd.id, portID: "gnd")
        )

        vm.document.wires = [w1a, w1b, w2a, w2b, w2c, w2d, w3a, w3b, w3c, w3d, w4, w5]

        vm.document.labels = [
            NetLabel(name: "out", position: CGPoint(x: 250, y: 165))
        ]

        vm.recomputeJunctions()
        return vm
    }

    /// Series RLC circuit for observing damped oscillation.
    ///
    /// Circuit topology:
    /// ```
    ///        in      mid        out
    ///   V1+ ── R1 ──── L1 ──┬── C1+
    ///                        │
    ///   V1- ─────────────────┴── C1- ── GND
    ///        (net "0")
    /// ```
    ///
    /// R=50Ω, L=1μH, C=100pF
    /// f₀ = 1/(2π√LC) ≈ 15.9 MHz, period ≈ 63ns
    /// Q = (1/R)√(L/C) = 2 (underdamped, visible oscillation)
    public static func rlcDampedViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let v1 = PlacedComponent(
            deviceKindID: "vsource",
            name: "V1",
            position: CGPoint(x: 100, y: 170),       // pos@(100,140) neg@(100,200)
            parameters: [
                "pulse_v1": 0, "pulse_v2": 5,
                "pulse_td": 0, "pulse_tr": 0.1e-9, "pulse_tf": 0.1e-9,
                "pulse_pw": 250e-9, "pulse_per": 500e-9,
            ]
        )
        let r1 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R1",
            position: CGPoint(x: 250, y: 80),        // pos@(250,50) neg@(250,110)
            parameters: ["r": 50]
        )
        let l1 = PlacedComponent(
            deviceKindID: "inductor",
            name: "L1",
            position: CGPoint(x: 250, y: 180),       // pos@(250,150) neg@(250,210)
            parameters: ["l": 1e-6]
        )
        let c1 = PlacedComponent(
            deviceKindID: "capacitor",
            name: "C1",
            position: CGPoint(x: 250, y: 280),       // pos@(250,250) neg@(250,310)
            parameters: ["c": 100e-12]
        )
        let gnd = PlacedComponent(
            deviceKindID: "ground",
            name: "GND1",
            position: CGPoint(x: 100, y: 360)        // gnd@(100,350)
        )

        vm.document.components = [v1, r1, l1, c1, gnd]

        // Net "in": V1.pos → corner(100,50) → R1.pos
        let w1a = Wire(
            startPoint: CGPoint(x: 100, y: 140),
            endPoint: CGPoint(x: 100, y: 50),
            startPin: PinReference(componentID: v1.id, portID: "pos")
        )
        let w1b = Wire(
            startPoint: CGPoint(x: 100, y: 50),
            endPoint: CGPoint(x: 250, y: 50),
            endPin: PinReference(componentID: r1.id, portID: "pos")
        )
        // Net "mid": R1.neg → (250,130) ← L1.pos
        let w2a = Wire(
            startPoint: CGPoint(x: 250, y: 110),
            endPoint: CGPoint(x: 250, y: 130),
            startPin: PinReference(componentID: r1.id, portID: "neg")
        )
        let w2b = Wire(
            startPoint: CGPoint(x: 250, y: 150),
            endPoint: CGPoint(x: 250, y: 130),
            startPin: PinReference(componentID: l1.id, portID: "pos")
        )
        // Net "out": L1.neg → (250,230) ← C1.pos
        let w3a = Wire(
            startPoint: CGPoint(x: 250, y: 210),
            endPoint: CGPoint(x: 250, y: 230),
            startPin: PinReference(componentID: l1.id, portID: "neg")
        )
        let w3b = Wire(
            startPoint: CGPoint(x: 250, y: 250),
            endPoint: CGPoint(x: 250, y: 230),
            startPin: PinReference(componentID: c1.id, portID: "pos")
        )
        // Net "0": C1.neg → (250,340) → (100,340)
        let w4a = Wire(
            startPoint: CGPoint(x: 250, y: 310),
            endPoint: CGPoint(x: 250, y: 340),
            startPin: PinReference(componentID: c1.id, portID: "neg")
        )
        let w4b = Wire(
            startPoint: CGPoint(x: 250, y: 340),
            endPoint: CGPoint(x: 100, y: 340)
        )
        // Net "0": V1.neg → (100,340)
        let w5 = Wire(
            startPoint: CGPoint(x: 100, y: 200),
            endPoint: CGPoint(x: 100, y: 340),
            startPin: PinReference(componentID: v1.id, portID: "neg")
        )
        // Net "0": (100,340) → GND.gnd
        let w6 = Wire(
            startPoint: CGPoint(x: 100, y: 340),
            endPoint: CGPoint(x: 100, y: 350),
            endPin: PinReference(componentID: gnd.id, portID: "gnd")
        )

        vm.document.wires = [w1a, w1b, w2a, w2b, w3a, w3b, w4a, w4b, w5, w6]

        vm.document.labels = [
            NetLabel(name: "out", position: CGPoint(x: 250, y: 230))
        ]

        vm.recomputeJunctions()
        return vm
    }

    /// CMOS inverter with capacitive load for digital transient analysis.
    ///
    /// Circuit topology:
    /// ```
    ///          VDD (3.3V)
    ///           │
    ///       ┌─ PMOS (source,bulk→VDD)
    ///  IN ──┤   │
    ///       └─ NMOS (source,bulk→GND)  ── out ── Cload
    ///           │
    ///          GND
    /// ```
    ///
    /// PMOS: W=20μ, L=1μ, VTO=-0.7V
    /// NMOS: W=10μ, L=1μ, VTO=0.7V
    /// Cload=100fF, V_IN=PULSE(0→3.3V)
    public static func cmosInverterViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let vdd = PlacedComponent(
            deviceKindID: "vsource",
            name: "V1",
            position: CGPoint(x: 50, y: 80),         // pos@(50,50) neg@(50,110)
            parameters: ["dc": 3.3]
        )
        let vin = PlacedComponent(
            deviceKindID: "vsource",
            name: "V2",
            position: CGPoint(x: 120, y: 350),       // pos@(120,320) neg@(120,380)
            parameters: [
                "pulse_v1": 0, "pulse_v2": 3.3,
                "pulse_td": 1e-9, "pulse_tr": 0.5e-9, "pulse_tf": 0.5e-9,
                "pulse_pw": 10e-9, "pulse_per": 22e-9,
            ]
        )
        let mp = PlacedComponent(
            deviceKindID: "pmos_l1",
            name: "MP1",
            position: CGPoint(x: 250, y: 150),       // drain@(260,180) gate@(230,150) source@(260,120) bulk@(240,120)
            parameters: ["w": 20e-6, "l": 1e-6, "vto": -0.7, "kp": 50e-6]
        )
        let mn = PlacedComponent(
            deviceKindID: "nmos_l1",
            name: "MN1",
            position: CGPoint(x: 250, y: 310),       // drain@(260,280) gate@(230,310) source@(260,340) bulk@(240,340)
            parameters: ["w": 10e-6, "l": 1e-6, "vto": 0.7, "kp": 110e-6]
        )
        let cload = PlacedComponent(
            deviceKindID: "capacitor",
            name: "C1",
            position: CGPoint(x: 380, y: 230),       // pos@(380,200) neg@(380,260)
            parameters: ["c": 100e-15]
        )
        let gnd = PlacedComponent(
            deviceKindID: "ground",
            name: "GND1",
            position: CGPoint(x: 50, y: 440)         // gnd@(50,430)
        )

        vm.document.components = [vdd, vin, mp, mn, cload, gnd]

        // === VDD net ===
        // V1.pos(50,50) → (240,50) → (260,50) → PMOS.source(260,120)
        let wV1 = Wire(
            startPoint: CGPoint(x: 50, y: 50),
            endPoint: CGPoint(x: 240, y: 50),
            startPin: PinReference(componentID: vdd.id, portID: "pos")
        )
        let wV2 = Wire(
            startPoint: CGPoint(x: 240, y: 50),
            endPoint: CGPoint(x: 260, y: 50)
        )
        let wV3 = Wire(
            startPoint: CGPoint(x: 260, y: 50),
            endPoint: CGPoint(x: 260, y: 120),
            endPin: PinReference(componentID: mp.id, portID: "source")
        )
        // PMOS.bulk(240,120) → VDD rail at (240,50)
        let wV4 = Wire(
            startPoint: CGPoint(x: 240, y: 120),
            endPoint: CGPoint(x: 240, y: 50),
            startPin: PinReference(componentID: mp.id, portID: "bulk")
        )

        // === Input net ===
        // V_IN.pos(120,320) → (120,230) → (160,230) → split to gates
        let wI1 = Wire(
            startPoint: CGPoint(x: 120, y: 320),
            endPoint: CGPoint(x: 120, y: 230),
            startPin: PinReference(componentID: vin.id, portID: "pos")
        )
        let wI2 = Wire(
            startPoint: CGPoint(x: 120, y: 230),
            endPoint: CGPoint(x: 160, y: 230)
        )
        // Up to PMOS.gate(230,150)
        let wI3 = Wire(
            startPoint: CGPoint(x: 160, y: 230),
            endPoint: CGPoint(x: 160, y: 150)
        )
        let wI4 = Wire(
            startPoint: CGPoint(x: 160, y: 150),
            endPoint: CGPoint(x: 230, y: 150),
            endPin: PinReference(componentID: mp.id, portID: "gate")
        )
        // Down to NMOS.gate(230,310)
        let wI5 = Wire(
            startPoint: CGPoint(x: 160, y: 230),
            endPoint: CGPoint(x: 160, y: 310)
        )
        let wI6 = Wire(
            startPoint: CGPoint(x: 160, y: 310),
            endPoint: CGPoint(x: 230, y: 310),
            endPin: PinReference(componentID: mn.id, portID: "gate")
        )

        // === Output net ===
        // PMOS.drain(260,180) → junction(260,230) ← NMOS.drain(260,280)
        let wO1 = Wire(
            startPoint: CGPoint(x: 260, y: 180),
            endPoint: CGPoint(x: 260, y: 230),
            startPin: PinReference(componentID: mp.id, portID: "drain")
        )
        let wO2 = Wire(
            startPoint: CGPoint(x: 260, y: 280),
            endPoint: CGPoint(x: 260, y: 230),
            startPin: PinReference(componentID: mn.id, portID: "drain")
        )
        // junction(260,230) → Cload.pos(380,200)
        let wO3 = Wire(
            startPoint: CGPoint(x: 260, y: 230),
            endPoint: CGPoint(x: 380, y: 230)
        )
        let wO4 = Wire(
            startPoint: CGPoint(x: 380, y: 200),
            endPoint: CGPoint(x: 380, y: 230),
            startPin: PinReference(componentID: cload.id, portID: "pos")
        )

        // === GND net ===
        // NMOS bulk(240,340) → source(260,340)
        let wG_bs = Wire(
            startPoint: CGPoint(x: 240, y: 340),
            endPoint: CGPoint(x: 260, y: 340),
            startPin: PinReference(componentID: mn.id, portID: "bulk")
        )
        // NMOS.source(260,340) → ground rail (260,410)
        let wG_s = Wire(
            startPoint: CGPoint(x: 260, y: 340),
            endPoint: CGPoint(x: 260, y: 410),
            startPin: PinReference(componentID: mn.id, portID: "source")
        )
        // V1.neg(50,110) → ground rail (50,410)
        let wG_vdd = Wire(
            startPoint: CGPoint(x: 50, y: 110),
            endPoint: CGPoint(x: 50, y: 410),
            startPin: PinReference(componentID: vdd.id, portID: "neg")
        )
        // V_IN.neg(120,380) → ground rail (120,410)
        let wG_vin = Wire(
            startPoint: CGPoint(x: 120, y: 380),
            endPoint: CGPoint(x: 120, y: 410),
            startPin: PinReference(componentID: vin.id, portID: "neg")
        )
        // Cload.neg(380,260) → ground rail (380,410)
        let wG_c = Wire(
            startPoint: CGPoint(x: 380, y: 260),
            endPoint: CGPoint(x: 380, y: 410),
            startPin: PinReference(componentID: cload.id, portID: "neg")
        )
        // Ground rail segments
        let wG_r1 = Wire(
            startPoint: CGPoint(x: 50, y: 410),
            endPoint: CGPoint(x: 120, y: 410)
        )
        let wG_r2 = Wire(
            startPoint: CGPoint(x: 120, y: 410),
            endPoint: CGPoint(x: 260, y: 410)
        )
        let wG_r3 = Wire(
            startPoint: CGPoint(x: 260, y: 410),
            endPoint: CGPoint(x: 380, y: 410)
        )
        // GND symbol
        let wG_gnd = Wire(
            startPoint: CGPoint(x: 50, y: 410),
            endPoint: CGPoint(x: 50, y: 430),
            endPin: PinReference(componentID: gnd.id, portID: "gnd")
        )

        vm.document.wires = [
            wV1, wV2, wV3, wV4,
            wI1, wI2, wI3, wI4, wI5, wI6,
            wO1, wO2, wO3, wO4,
            wG_bs, wG_s, wG_vdd, wG_vin, wG_c,
            wG_r1, wG_r2, wG_r3, wG_gnd,
        ]

        vm.document.labels = [
            NetLabel(name: "vdd", position: CGPoint(x: 240, y: 50)),
            NetLabel(name: "in", position: CGPoint(x: 160, y: 230)),
            NetLabel(name: "out", position: CGPoint(x: 260, y: 230)),
        ]

        vm.recomputeJunctions()
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
