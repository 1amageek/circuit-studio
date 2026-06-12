import Testing
import CoreGraphics
@testable import CircuitStudioCore

@Suite("Analysis Candidates Tests")
struct AnalysisCandidatesTests {

    // MARK: - From Parsed Netlist

    @Test func fromNetlistKeepsOnlyIndependentSources() {
        let info = NetlistInfo(
            title: "Test",
            components: [
                ComponentSummary(name: "V1", type: "V", nodes: ["in", "0"], modelName: nil, primaryValue: "5"),
                ComponentSummary(name: "I1", type: "I", nodes: ["out", "0"], modelName: nil, primaryValue: "1m"),
                ComponentSummary(name: "R1", type: "R", nodes: ["in", "out"], modelName: nil, primaryValue: "1k"),
                ComponentSummary(name: "M1", type: "M", nodes: ["out", "in", "0", "0"], modelName: "nmos", primaryValue: nil),
            ],
            nodes: ["0", "in", "out"],
            analyses: [],
            models: [],
            diagnostics: [],
            hasErrors: false
        )

        let candidates = AnalysisCandidates.from(netlist: info)

        #expect(candidates.sourceNames == ["V1", "I1"])
        #expect(candidates.nodeNames == ["in", "out"])
    }

    @Test func fromNetlistExcludesGroundNode() {
        let info = NetlistInfo(
            title: nil,
            components: [],
            nodes: ["0"],
            analyses: [],
            models: [],
            diagnostics: [],
            hasErrors: false
        )

        let candidates = AnalysisCandidates.from(netlist: info)

        #expect(candidates.nodeNames.isEmpty)
    }

    @Test func fromNetlistDeduplicatesPreservingOrder() {
        let info = NetlistInfo(
            title: nil,
            components: [
                ComponentSummary(name: "V1", type: "V", nodes: [], modelName: nil, primaryValue: nil),
                ComponentSummary(name: "V1", type: "V", nodes: [], modelName: nil, primaryValue: nil),
                ComponentSummary(name: "V2", type: "V", nodes: [], modelName: nil, primaryValue: nil),
            ],
            nodes: ["out", "in", "out"],
            analyses: [],
            models: [],
            diagnostics: [],
            hasErrors: false
        )

        let candidates = AnalysisCandidates.from(netlist: info)

        #expect(candidates.sourceNames == ["V1", "V2"])
        #expect(candidates.nodeNames == ["out", "in"])
    }

    // MARK: - From Schematic Document

    @Test func fromDocumentUsesSpicePrefixForSources() {
        let v1 = PlacedComponent(deviceKindID: "vsource", name: "V1", position: .zero, parameters: ["dc": 5])
        let i1 = PlacedComponent(deviceKindID: "isource", name: "I1", position: CGPoint(x: 200, y: 0))
        let r1 = PlacedComponent(deviceKindID: "resistor", name: "R1", position: CGPoint(x: 100, y: 0), parameters: ["r": 1000])
        let document = SchematicDocument(components: [v1, i1, r1], wires: [])

        let candidates = AnalysisCandidates.from(document: document, catalog: .standard())

        #expect(candidates.sourceNames == ["V1", "I1"])
    }

    @Test func fromDocumentExcludesGroundNet() {
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
        let document = SchematicDocument(components: [v1, r1, gnd], wires: [wireVR, wireRGnd])

        let candidates = AnalysisCandidates.from(document: document, catalog: .standard())

        #expect(!candidates.nodeNames.isEmpty)
        #expect(!candidates.nodeNames.contains("0"))
    }

    @Test func fromDocumentWithUnknownDeviceKindSkipsComponent() {
        let unknown = PlacedComponent(deviceKindID: "no-such-kind", name: "X1", position: .zero)
        let document = SchematicDocument(components: [unknown], wires: [])

        let candidates = AnalysisCandidates.from(document: document, catalog: .standard())

        #expect(candidates.sourceNames.isEmpty)
    }

    @Test func emptyCandidatesAreEmpty() {
        #expect(AnalysisCandidates.empty.sourceNames.isEmpty)
        #expect(AnalysisCandidates.empty.nodeNames.isEmpty)
    }
}
