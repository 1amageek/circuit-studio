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
    public static func rcLowpassViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let v1 = PlacedComponent(
            deviceKindID: "vsource",
            name: "V1",
            position: CGPoint(x: 100, y: 150),
            parameters: ["dc": 0, "ac": 1]
        )
        let r1 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R1",
            position: CGPoint(x: 200, y: 100),
            parameters: ["r": 1000]
        )
        let c1 = PlacedComponent(
            deviceKindID: "capacitor",
            name: "C1",
            position: CGPoint(x: 200, y: 200),
            parameters: ["c": 1e-6]
        )
        let gnd = PlacedComponent(
            deviceKindID: "ground",
            name: "GND1",
            position: CGPoint(x: 100, y: 250)
        )

        vm.document.components = [v1, r1, c1, gnd]

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

    /// Canvas with an RC circuit driven by a PULSE source for transient analysis.
    public static func rcPulseStepViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let v1 = PlacedComponent(
            deviceKindID: "vsource",
            name: "V1",
            position: CGPoint(x: 100, y: 150),
            parameters: [
                "pulse_v1": 0, "pulse_v2": 5,
                "pulse_td": 1e-6, "pulse_tr": 0.1e-6, "pulse_tf": 0.1e-6,
                "pulse_pw": 10e-6, "pulse_per": 20e-6,
            ]
        )
        let r1 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R1",
            position: CGPoint(x: 200, y: 100),
            parameters: ["r": 1000]
        )
        let c1 = PlacedComponent(
            deviceKindID: "capacitor",
            name: "C1",
            position: CGPoint(x: 200, y: 200),
            parameters: ["c": 1e-9]
        )
        let gnd = PlacedComponent(
            deviceKindID: "ground",
            name: "GND1",
            position: CGPoint(x: 100, y: 250)
        )

        vm.document.components = [v1, r1, c1, gnd]

        let w1a = Wire(startPoint: CGPoint(x: 100, y: 120), endPoint: CGPoint(x: 100, y: 70), startPin: PinReference(componentID: v1.id, portID: "pos"))
        let w1b = Wire(startPoint: CGPoint(x: 100, y: 70), endPoint: CGPoint(x: 200, y: 70), endPin: PinReference(componentID: r1.id, portID: "pos"))
        let w2a = Wire(startPoint: CGPoint(x: 200, y: 130), endPoint: CGPoint(x: 200, y: 150), startPin: PinReference(componentID: r1.id, portID: "neg"))
        let w2b = Wire(startPoint: CGPoint(x: 200, y: 170), endPoint: CGPoint(x: 200, y: 150), startPin: PinReference(componentID: c1.id, portID: "pos"))
        let w3 = Wire(startPoint: CGPoint(x: 200, y: 230), endPoint: CGPoint(x: 100, y: 230), startPin: PinReference(componentID: c1.id, portID: "neg"))
        let w4 = Wire(startPoint: CGPoint(x: 100, y: 180), endPoint: CGPoint(x: 100, y: 230), startPin: PinReference(componentID: v1.id, portID: "neg"))
        let w5 = Wire(startPoint: CGPoint(x: 100, y: 230), endPoint: CGPoint(x: 100, y: 240), endPin: PinReference(componentID: gnd.id, portID: "gnd"))

        vm.document.wires = [w1a, w1b, w2a, w2b, w3, w4, w5]
        vm.document.labels = [NetLabel(name: "out", position: CGPoint(x: 200, y: 150))]
        vm.recomputeJunctions()
        return vm
    }

    /// Canvas with a diode forward bias circuit for OP analysis.
    public static func diodeForwardBiasViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let v1 = PlacedComponent(deviceKindID: "vsource", name: "V1", position: CGPoint(x: 100, y: 150), parameters: ["dc": 5])
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 200, y: 100), parameters: ["r": 1000])
        let d1 = PlacedComponent(deviceKindID: "diode", name: "D1", position: CGPoint(x: 200, y: 200), parameters: ["is": 1e-14, "n": 1.0])
        let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: CGPoint(x: 100, y: 250))

        vm.document.components = [v1, r1, d1, gnd]

        let w1a = Wire(startPoint: CGPoint(x: 100, y: 120), endPoint: CGPoint(x: 100, y: 70), startPin: PinReference(componentID: v1.id, portID: "pos"))
        let w1b = Wire(startPoint: CGPoint(x: 100, y: 70), endPoint: CGPoint(x: 200, y: 70), endPin: PinReference(componentID: r1.id, portID: "pos"))
        let w2a = Wire(startPoint: CGPoint(x: 200, y: 130), endPoint: CGPoint(x: 200, y: 150), startPin: PinReference(componentID: r1.id, portID: "neg"))
        let w2b = Wire(startPoint: CGPoint(x: 200, y: 170), endPoint: CGPoint(x: 200, y: 150), startPin: PinReference(componentID: d1.id, portID: "anode"))
        let w3 = Wire(startPoint: CGPoint(x: 200, y: 230), endPoint: CGPoint(x: 100, y: 230), startPin: PinReference(componentID: d1.id, portID: "cathode"))
        let w4 = Wire(startPoint: CGPoint(x: 100, y: 180), endPoint: CGPoint(x: 100, y: 230), startPin: PinReference(componentID: v1.id, portID: "neg"))
        let w5 = Wire(startPoint: CGPoint(x: 100, y: 230), endPoint: CGPoint(x: 100, y: 240), endPin: PinReference(componentID: gnd.id, portID: "gnd"))

        vm.document.wires = [w1a, w1b, w2a, w2b, w3, w4, w5]
        vm.document.labels = [NetLabel(name: "anode", position: CGPoint(x: 200, y: 150))]
        vm.recomputeJunctions()
        return vm
    }

    /// RC circuit with load resistor for observing effective time constant change.
    public static func rcLoadedStepViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let v1 = PlacedComponent(deviceKindID: "vsource", name: "V1", position: CGPoint(x: 100, y: 150), parameters: ["pulse_v1": 0, "pulse_v2": 5, "pulse_td": 10e-9, "pulse_tr": 1e-9, "pulse_tf": 1e-9, "pulse_pw": 500e-9, "pulse_per": 1e-6])
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 250, y: 100), parameters: ["r": 1000])
        let c1 = PlacedComponent(deviceKindID: "capacitor", name: "C1", position: CGPoint(x: 250, y: 230), parameters: ["c": 100e-12])
        let rload = PlacedComponent(deviceKindID: "resistor", name: "R2", position: CGPoint(x: 350, y: 230), parameters: ["r": 10000])
        let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: CGPoint(x: 100, y: 320))

        vm.document.components = [v1, r1, c1, rload, gnd]

        let w1a = Wire(startPoint: CGPoint(x: 100, y: 120), endPoint: CGPoint(x: 100, y: 70), startPin: PinReference(componentID: v1.id, portID: "pos"))
        let w1b = Wire(startPoint: CGPoint(x: 100, y: 70), endPoint: CGPoint(x: 250, y: 70), endPin: PinReference(componentID: r1.id, portID: "pos"))
        let w2a = Wire(startPoint: CGPoint(x: 250, y: 130), endPoint: CGPoint(x: 250, y: 165), startPin: PinReference(componentID: r1.id, portID: "neg"))
        let w2b = Wire(startPoint: CGPoint(x: 250, y: 200), endPoint: CGPoint(x: 250, y: 165), startPin: PinReference(componentID: c1.id, portID: "pos"))
        let w2c = Wire(startPoint: CGPoint(x: 250, y: 165), endPoint: CGPoint(x: 350, y: 165))
        let w2d = Wire(startPoint: CGPoint(x: 350, y: 165), endPoint: CGPoint(x: 350, y: 200), endPin: PinReference(componentID: rload.id, portID: "pos"))
        let w3a = Wire(startPoint: CGPoint(x: 250, y: 260), endPoint: CGPoint(x: 250, y: 290), startPin: PinReference(componentID: c1.id, portID: "neg"))
        let w3b = Wire(startPoint: CGPoint(x: 350, y: 260), endPoint: CGPoint(x: 350, y: 290), startPin: PinReference(componentID: rload.id, portID: "neg"))
        let w3c = Wire(startPoint: CGPoint(x: 250, y: 290), endPoint: CGPoint(x: 350, y: 290))
        let w3d = Wire(startPoint: CGPoint(x: 100, y: 290), endPoint: CGPoint(x: 250, y: 290))
        let w4 = Wire(startPoint: CGPoint(x: 100, y: 180), endPoint: CGPoint(x: 100, y: 290), startPin: PinReference(componentID: v1.id, portID: "neg"))
        let w5 = Wire(startPoint: CGPoint(x: 100, y: 290), endPoint: CGPoint(x: 100, y: 310), endPin: PinReference(componentID: gnd.id, portID: "gnd"))

        vm.document.wires = [w1a, w1b, w2a, w2b, w2c, w2d, w3a, w3b, w3c, w3d, w4, w5]
        vm.document.labels = [NetLabel(name: "out", position: CGPoint(x: 250, y: 165))]
        vm.recomputeJunctions()
        return vm
    }

    /// Series RLC circuit for observing damped oscillation.
    public static func rlcDampedViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let v1 = PlacedComponent(deviceKindID: "vsource", name: "V1", position: CGPoint(x: 100, y: 170), parameters: ["pulse_v1": 0, "pulse_v2": 5, "pulse_td": 0, "pulse_tr": 0.1e-9, "pulse_tf": 0.1e-9, "pulse_pw": 250e-9, "pulse_per": 500e-9])
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 250, y: 80), parameters: ["r": 50])
        let l1 = PlacedComponent(deviceKindID: "inductor", name: "L1", position: CGPoint(x: 250, y: 180), parameters: ["l": 1e-6])
        let c1 = PlacedComponent(deviceKindID: "capacitor", name: "C1", position: CGPoint(x: 250, y: 280), parameters: ["c": 100e-12])
        let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: CGPoint(x: 100, y: 360))

        vm.document.components = [v1, r1, l1, c1, gnd]

        let w1a = Wire(startPoint: CGPoint(x: 100, y: 140), endPoint: CGPoint(x: 100, y: 50), startPin: PinReference(componentID: v1.id, portID: "pos"))
        let w1b = Wire(startPoint: CGPoint(x: 100, y: 50), endPoint: CGPoint(x: 250, y: 50), endPin: PinReference(componentID: r1.id, portID: "pos"))
        let w2a = Wire(startPoint: CGPoint(x: 250, y: 110), endPoint: CGPoint(x: 250, y: 130), startPin: PinReference(componentID: r1.id, portID: "neg"))
        let w2b = Wire(startPoint: CGPoint(x: 250, y: 150), endPoint: CGPoint(x: 250, y: 130), startPin: PinReference(componentID: l1.id, portID: "pos"))
        let w3a = Wire(startPoint: CGPoint(x: 250, y: 210), endPoint: CGPoint(x: 250, y: 230), startPin: PinReference(componentID: l1.id, portID: "neg"))
        let w3b = Wire(startPoint: CGPoint(x: 250, y: 250), endPoint: CGPoint(x: 250, y: 230), startPin: PinReference(componentID: c1.id, portID: "pos"))
        let w4a = Wire(startPoint: CGPoint(x: 250, y: 310), endPoint: CGPoint(x: 250, y: 340), startPin: PinReference(componentID: c1.id, portID: "neg"))
        let w4b = Wire(startPoint: CGPoint(x: 250, y: 340), endPoint: CGPoint(x: 100, y: 340))
        let w5 = Wire(startPoint: CGPoint(x: 100, y: 200), endPoint: CGPoint(x: 100, y: 340), startPin: PinReference(componentID: v1.id, portID: "neg"))
        let w6 = Wire(startPoint: CGPoint(x: 100, y: 340), endPoint: CGPoint(x: 100, y: 350), endPin: PinReference(componentID: gnd.id, portID: "gnd"))

        vm.document.wires = [w1a, w1b, w2a, w2b, w3a, w3b, w4a, w4b, w5, w6]
        vm.document.labels = [NetLabel(name: "out", position: CGPoint(x: 250, y: 230))]
        vm.recomputeJunctions()
        return vm
    }

    /// CMOS inverter with capacitive load for digital transient analysis.
    public static func cmosInverterViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let vdd = PlacedComponent(deviceKindID: "vsource", name: "V1", position: CGPoint(x: 50, y: 80), parameters: ["dc": 3.3])
        let vin = PlacedComponent(deviceKindID: "vsource", name: "V2", position: CGPoint(x: 120, y: 350), parameters: ["pulse_v1": 0, "pulse_v2": 3.3, "pulse_td": 1e-9, "pulse_tr": 0.5e-9, "pulse_tf": 0.5e-9, "pulse_pw": 10e-9, "pulse_per": 22e-9])
        let mp = PlacedComponent(deviceKindID: "pmos_l1", name: "MP1", position: CGPoint(x: 250, y: 150), parameters: ["w": 20e-6, "l": 1e-6, "vto": -0.7, "kp": 50e-6])
        let mn = PlacedComponent(deviceKindID: "nmos_l1", name: "MN1", position: CGPoint(x: 250, y: 310), parameters: ["w": 10e-6, "l": 1e-6, "vto": 0.7, "kp": 110e-6])
        let cload = PlacedComponent(deviceKindID: "capacitor", name: "C1", position: CGPoint(x: 380, y: 260), parameters: ["c": 100e-15])
        let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: CGPoint(x: 50, y: 440))

        vm.document.components = [vdd, vin, mp, mn, cload, gnd]

        // VDD net
        let wV1 = Wire(startPoint: CGPoint(x: 50, y: 50), endPoint: CGPoint(x: 240, y: 50), startPin: PinReference(componentID: vdd.id, portID: "pos"))
        let wV2 = Wire(startPoint: CGPoint(x: 240, y: 50), endPoint: CGPoint(x: 260, y: 50))
        let wV3 = Wire(startPoint: CGPoint(x: 260, y: 50), endPoint: CGPoint(x: 260, y: 120), endPin: PinReference(componentID: mp.id, portID: "source"))
        let wV4 = Wire(startPoint: CGPoint(x: 240, y: 120), endPoint: CGPoint(x: 240, y: 50), startPin: PinReference(componentID: mp.id, portID: "bulk"))

        // Input net
        let wI1 = Wire(startPoint: CGPoint(x: 120, y: 320), endPoint: CGPoint(x: 120, y: 230), startPin: PinReference(componentID: vin.id, portID: "pos"))
        let wI2 = Wire(startPoint: CGPoint(x: 120, y: 230), endPoint: CGPoint(x: 160, y: 230))
        let wI3 = Wire(startPoint: CGPoint(x: 160, y: 230), endPoint: CGPoint(x: 160, y: 150))
        let wI4 = Wire(startPoint: CGPoint(x: 160, y: 150), endPoint: CGPoint(x: 230, y: 150), endPin: PinReference(componentID: mp.id, portID: "gate"))
        let wI5 = Wire(startPoint: CGPoint(x: 160, y: 230), endPoint: CGPoint(x: 160, y: 310))
        let wI6 = Wire(startPoint: CGPoint(x: 160, y: 310), endPoint: CGPoint(x: 230, y: 310), endPin: PinReference(componentID: mn.id, portID: "gate"))

        // Output net
        let wO1 = Wire(startPoint: CGPoint(x: 260, y: 180), endPoint: CGPoint(x: 260, y: 230), startPin: PinReference(componentID: mp.id, portID: "drain"))
        let wO2 = Wire(startPoint: CGPoint(x: 260, y: 280), endPoint: CGPoint(x: 260, y: 230), startPin: PinReference(componentID: mn.id, portID: "drain"))
        let wO3 = Wire(startPoint: CGPoint(x: 260, y: 230), endPoint: CGPoint(x: 380, y: 230), endPin: PinReference(componentID: cload.id, portID: "pos"))

        // GND net
        let wG_bs = Wire(startPoint: CGPoint(x: 240, y: 340), endPoint: CGPoint(x: 260, y: 340), startPin: PinReference(componentID: mn.id, portID: "bulk"))
        let wG_s = Wire(startPoint: CGPoint(x: 260, y: 340), endPoint: CGPoint(x: 260, y: 410), startPin: PinReference(componentID: mn.id, portID: "source"))
        let wG_vdd = Wire(startPoint: CGPoint(x: 50, y: 110), endPoint: CGPoint(x: 50, y: 410), startPin: PinReference(componentID: vdd.id, portID: "neg"))
        let wG_vin = Wire(startPoint: CGPoint(x: 120, y: 380), endPoint: CGPoint(x: 120, y: 410), startPin: PinReference(componentID: vin.id, portID: "neg"))
        let wG_c = Wire(startPoint: CGPoint(x: 380, y: 290), endPoint: CGPoint(x: 380, y: 410), startPin: PinReference(componentID: cload.id, portID: "neg"))
        let wG_r1 = Wire(startPoint: CGPoint(x: 50, y: 410), endPoint: CGPoint(x: 120, y: 410))
        let wG_r2 = Wire(startPoint: CGPoint(x: 120, y: 410), endPoint: CGPoint(x: 260, y: 410))
        let wG_r3 = Wire(startPoint: CGPoint(x: 260, y: 410), endPoint: CGPoint(x: 380, y: 410))
        let wG_gnd = Wire(startPoint: CGPoint(x: 50, y: 410), endPoint: CGPoint(x: 50, y: 430), endPin: PinReference(componentID: gnd.id, portID: "gnd"))

        vm.document.wires = [
            wV1, wV2, wV3, wV4,
            wI1, wI2, wI3, wI4, wI5, wI6,
            wO1, wO2, wO3,
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

    /// NMOS current mirror with resistive load for DC operating point analysis.
    ///
    /// Circuit topology:
    /// ```
    ///            VDD
    ///             |
    ///        R_ref          R_load
    ///             |              |
    ///        M1 drain       M2 drain  ── out
    ///       (diode-conn)
    ///    M1 gate ─────── M2 gate
    ///             |              |
    ///        M1 source      M2 source
    ///             |              |
    ///            GND            GND
    /// ```
    ///
    /// Nets:
    /// - "vdd": V1.pos, R_ref.pos, R_load.pos
    /// - "ref": R_ref.neg, M1.drain, M1.gate, M2.gate  (diode connection)
    /// - "out": R_load.neg, M2.drain
    /// - "0" (ground): V1.neg, M1.source, M1.bulk, M2.source, M2.bulk, GND.gnd
    public static func currentMirrorViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        // --- Components ---
        // Pin offsets (from component center):
        //   vsource:  pos=(0,-30), neg=(0,+30)
        //   resistor: pos=(0,-30), neg=(0,+30)
        //   nmos_l1:  gate=(-20,0), drain=(+10,-30), source=(+10,+30), bulk=(-10,+30)
        //   ground:   gnd=(0,-10)

        let vdd = PlacedComponent(deviceKindID: "vsource", name: "V1", position: CGPoint(x: 100, y: 80), parameters: ["dc": 5.0])
        let rref = PlacedComponent(deviceKindID: "resistor", name: "R_ref", position: CGPoint(x: 250, y: 120), parameters: ["r": 10000])
        let rload = PlacedComponent(deviceKindID: "resistor", name: "R_load", position: CGPoint(x: 430, y: 120), parameters: ["r": 10000])
        let m1 = PlacedComponent(deviceKindID: "nmos_l1", name: "M1", position: CGPoint(x: 260, y: 280), parameters: ["w": 10e-6, "l": 1e-6, "vto": 0.7, "kp": 110e-6])
        let m2 = PlacedComponent(deviceKindID: "nmos_l1", name: "M2", position: CGPoint(x: 420, y: 280), parameters: ["w": 10e-6, "l": 1e-6, "vto": 0.7, "kp": 110e-6])
        let gnd = PlacedComponent(deviceKindID: "ground", name: "GND1", position: CGPoint(x: 100, y: 420))

        vm.document.components = [vdd, rref, rload, m1, m2, gnd]

        // Pin world positions:
        //   V1:     pos(100,50)  neg(100,110)
        //   R_ref:  pos(250,90)  neg(250,150)
        //   R_load: pos(430,90)  neg(430,150)
        //   M1:     gate(240,280)  drain(270,250)  source(270,310)  bulk(250,310)
        //   M2:     gate(400,280)  drain(430,250)  source(430,310)  bulk(410,310)
        //   GND1:   gnd(100,410)

        // === VDD net (rail at y=40) ===
        let wV1 = Wire(startPoint: CGPoint(x: 100, y: 50), endPoint: CGPoint(x: 100, y: 40), startPin: PinReference(componentID: vdd.id, portID: "pos"))
        let wV2 = Wire(startPoint: CGPoint(x: 100, y: 40), endPoint: CGPoint(x: 250, y: 40))
        let wV3 = Wire(startPoint: CGPoint(x: 250, y: 40), endPoint: CGPoint(x: 250, y: 90), endPin: PinReference(componentID: rref.id, portID: "pos"))
        let wV4 = Wire(startPoint: CGPoint(x: 250, y: 40), endPoint: CGPoint(x: 430, y: 40))
        let wV5 = Wire(startPoint: CGPoint(x: 430, y: 40), endPoint: CGPoint(x: 430, y: 90), endPin: PinReference(componentID: rload.id, portID: "pos"))

        // === Reference net (M1 diode + gate bus) ===
        // R_ref.neg → junction at (250, 200)
        let wR1 = Wire(startPoint: CGPoint(x: 250, y: 150), endPoint: CGPoint(x: 250, y: 200), startPin: PinReference(componentID: rref.id, portID: "neg"))
        // M1.drain → (270, 200) → junction
        let wR2 = Wire(startPoint: CGPoint(x: 270, y: 250), endPoint: CGPoint(x: 270, y: 200), startPin: PinReference(componentID: m1.id, portID: "drain"))
        let wR3 = Wire(startPoint: CGPoint(x: 270, y: 200), endPoint: CGPoint(x: 250, y: 200))
        // M1.gate diode connection: gate(240,280) → left → up → junction
        let wR4 = Wire(startPoint: CGPoint(x: 240, y: 280), endPoint: CGPoint(x: 200, y: 280), startPin: PinReference(componentID: m1.id, portID: "gate"))
        let wR5 = Wire(startPoint: CGPoint(x: 200, y: 280), endPoint: CGPoint(x: 200, y: 200))
        let wR6 = Wire(startPoint: CGPoint(x: 200, y: 200), endPoint: CGPoint(x: 250, y: 200))
        // Gate bus: below transistors → M2.gate
        let wR7 = Wire(startPoint: CGPoint(x: 200, y: 280), endPoint: CGPoint(x: 200, y: 340))
        let wR8 = Wire(startPoint: CGPoint(x: 200, y: 340), endPoint: CGPoint(x: 400, y: 340))
        let wR9 = Wire(startPoint: CGPoint(x: 400, y: 340), endPoint: CGPoint(x: 400, y: 280), endPin: PinReference(componentID: m2.id, portID: "gate"))

        // === Output net (junction at y=200) ===
        let wO1 = Wire(startPoint: CGPoint(x: 430, y: 150), endPoint: CGPoint(x: 430, y: 200), startPin: PinReference(componentID: rload.id, portID: "neg"))
        let wO2 = Wire(startPoint: CGPoint(x: 430, y: 250), endPoint: CGPoint(x: 430, y: 200), startPin: PinReference(componentID: m2.id, portID: "drain"))

        // === GND net (rail at y=380) ===
        let wG1 = Wire(startPoint: CGPoint(x: 100, y: 110), endPoint: CGPoint(x: 100, y: 380), startPin: PinReference(componentID: vdd.id, portID: "neg"))
        let wG2 = Wire(startPoint: CGPoint(x: 270, y: 310), endPoint: CGPoint(x: 270, y: 380), startPin: PinReference(componentID: m1.id, portID: "source"))
        let wG3 = Wire(startPoint: CGPoint(x: 250, y: 310), endPoint: CGPoint(x: 270, y: 310), startPin: PinReference(componentID: m1.id, portID: "bulk"))
        let wG4 = Wire(startPoint: CGPoint(x: 430, y: 310), endPoint: CGPoint(x: 430, y: 380), startPin: PinReference(componentID: m2.id, portID: "source"))
        let wG5 = Wire(startPoint: CGPoint(x: 410, y: 310), endPoint: CGPoint(x: 430, y: 310), startPin: PinReference(componentID: m2.id, portID: "bulk"))
        let wG6 = Wire(startPoint: CGPoint(x: 100, y: 380), endPoint: CGPoint(x: 270, y: 380))
        let wG7 = Wire(startPoint: CGPoint(x: 270, y: 380), endPoint: CGPoint(x: 430, y: 380))
        let wG8 = Wire(startPoint: CGPoint(x: 100, y: 380), endPoint: CGPoint(x: 100, y: 410), endPin: PinReference(componentID: gnd.id, portID: "gnd"))

        vm.document.wires = [
            wV1, wV2, wV3, wV4, wV5,
            wR1, wR2, wR3, wR4, wR5, wR6, wR7, wR8, wR9,
            wO1, wO2,
            wG1, wG2, wG3, wG4, wG5, wG6, wG7, wG8,
        ]

        vm.document.labels = [
            NetLabel(name: "vdd", position: CGPoint(x: 250, y: 40)),
            NetLabel(name: "ref", position: CGPoint(x: 250, y: 200)),
            NetLabel(name: "out", position: CGPoint(x: 430, y: 200)),
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
