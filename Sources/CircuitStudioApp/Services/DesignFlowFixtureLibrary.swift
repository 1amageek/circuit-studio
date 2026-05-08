import Foundation
import CircuitStudioCore
import SchematicEditor

public struct DesignFlowFixture {
    public let name: String
    public let title: String
    public let schematic: SchematicDocument
    public let testbench: Testbench
    public let postLayoutCommand: AnalysisCommand
    public let pexIR: PEXParasiticIR

    public init(
        name: String,
        title: String,
        schematic: SchematicDocument,
        testbench: Testbench,
        postLayoutCommand: AnalysisCommand,
        pexIR: PEXParasiticIR
    ) {
        self.name = name
        self.title = title
        self.schematic = schematic
        self.testbench = testbench
        self.postLayoutCommand = postLayoutCommand
        self.pexIR = pexIR
    }
}

public enum DesignFlowFixtureError: Error, LocalizedError, Equatable {
    case unknownFixture(String)

    public var errorDescription: String? {
        switch self {
        case .unknownFixture(let name):
            return "Unknown fixture: \(name)"
        }
    }
}

public enum DesignFlowFixtureLibrary {
    public static let defaultFixtureName = "voltage-divider"
    public static let fixtureNames = [
        "cmos-inverter",
        "voltage-divider",
        "resistor-divider",
    ]

    @MainActor
    public static func fixture(named name: String) throws -> DesignFlowFixture {
        switch name {
        case "cmos-inverter":
            let command = AnalysisCommand.tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9))
            return DesignFlowFixture(
                name: name,
                title: "CMOS inverter headless round trip",
                schematic: SchematicPreview.cmosInverterViewModel().document,
                testbench: Testbench(name: "Transient", analysisCommands: [command]),
                postLayoutCommand: command,
                pexIR: PEXParasiticIR(
                    version: "1.0",
                    cornerID: "tt_25c_1v0",
                    elements: [
                        PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 1.0),
                        PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 2e-15),
                    ]
                )
            )
        case "voltage-divider":
            return DesignFlowFixture(
                name: name,
                title: "Voltage divider headless round trip",
                schematic: SchematicPreview.voltageDividerViewModel().document,
                testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
                postLayoutCommand: .op,
                pexIR: PEXParasiticIR(
                    version: "1.0",
                    cornerID: "tt_25c_1v0",
                    elements: [
                        PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.5),
                        PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
                    ]
                )
            )
        case "resistor-divider":
            return DesignFlowFixture(
                name: name,
                title: "Resistor divider headless round trip",
                schematic: SchematicPreview.voltageDividerViewModel().document,
                testbench: Testbench(name: "Operating Point", analysisCommands: [.op]),
                postLayoutCommand: .op,
                pexIR: PEXParasiticIR(
                    version: "1.0",
                    cornerID: "tt_25c_1v0",
                    elements: [
                        PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.75),
                        PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1.5e-15),
                    ]
                )
            )
        default:
            throw DesignFlowFixtureError.unknownFixture(name)
        }
    }
}
