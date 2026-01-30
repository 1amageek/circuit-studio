import SwiftUI
import CircuitStudioCore

/// Factory for creating SchematicViewModel instances populated with sample data for SwiftUI Previews.
@MainActor
public enum SchematicPreview {

    /// Empty canvas with default tools.
    public static func emptyViewModel() -> SchematicViewModel {
        SchematicViewModel()
    }

    /// Canvas with a simple voltage divider circuit.
    public static func voltageDividerViewModel() -> SchematicViewModel {
        let vm = SchematicViewModel()

        let v1 = PlacedComponent(
            deviceKindID: "vsource",
            name: "V1",
            position: CGPoint(x: 100, y: 150),
            parameters: ["dc": 5]
        )
        let r1 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R1",
            position: CGPoint(x: 200, y: 100),
            parameters: ["r": 1000]
        )
        let r2 = PlacedComponent(
            deviceKindID: "resistor",
            name: "R2",
            position: CGPoint(x: 200, y: 200),
            parameters: ["r": 1000]
        )
        let g1 = PlacedComponent(
            deviceKindID: "ground",
            name: "GND",
            position: CGPoint(x: 100, y: 250)
        )

        vm.document.components = [v1, r1, r2, g1]

        // Wires
        vm.document.wires = [
            Wire(startPoint: CGPoint(x: 100, y: 120), endPoint: CGPoint(x: 200, y: 70)),
            Wire(startPoint: CGPoint(x: 200, y: 130), endPoint: CGPoint(x: 200, y: 170)),
            Wire(startPoint: CGPoint(x: 200, y: 230), endPoint: CGPoint(x: 100, y: 230)),
            Wire(startPoint: CGPoint(x: 100, y: 180), endPoint: CGPoint(x: 100, y: 240)),
        ]

        // Label
        vm.document.labels = [
            NetLabel(name: "out", position: CGPoint(x: 220, y: 150))
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
