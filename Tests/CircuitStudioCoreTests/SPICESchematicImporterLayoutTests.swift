import CoreGraphics
import Testing
@testable import CircuitStudioCore
@testable import SchematicEditor

@Suite("SPICE Schematic Import Layout")
struct SPICESchematicImporterLayoutTests {
    @Test("Five-stage CMOS ring oscillator materializes as a readable signal chain")
    func ringOscillatorUsesCMOSStagesAndOrthogonalRouting() async throws {
        let result = try await SPICESchematicImporter().importTopLevel(
            source: Self.ringOscillatorSource,
            fileName: "ring-oscillator.cir",
            topCellName: "ring-oscillator"
        )
        let document = try #require(result.cells.first?.schematic)
        let componentsByName = Dictionary(
            document.components.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        #expect(document.components.count == 17)
        for stage in 0..<5 {
            let pmos = try #require(componentsByName["m\(stage * 2 + 1)"])
            let nmos = try #require(componentsByName["m\(stage * 2 + 2)"])
            #expect(pmos.position.x == nmos.position.x)
            #expect(pmos.position.y < nmos.position.y)
            if stage > 0 {
                let previousPMOS = try #require(componentsByName["m\(stage * 2 - 1)"])
                #expect(previousPMOS.position.x < pmos.position.x)
            }
        }

        let voltageSource = try #require(componentsByName["v1"])
        let currentSource = try #require(componentsByName["i1"])
        let firstCapacitor = try #require(componentsByName["c1"])
        let firstPMOS = try #require(componentsByName["m1"])
        #expect(abs(currentSource.position.x - firstCapacitor.position.x) >= 120)
        #expect(voltageSource.parameters["dc"] == 1.8)
        #expect(currentSource.parameters["pulse_v1"] == 0)
        #expect(approximatelyEqual(currentSource.parameters["pulse_v2"], 20e-6))
        #expect(currentSource.parameters["pulse_td"] == 0)
        #expect(approximatelyEqual(currentSource.parameters["pulse_tr"], 100e-12))
        #expect(approximatelyEqual(currentSource.parameters["pulse_tf"], 100e-12))
        #expect(approximatelyEqual(currentSource.parameters["pulse_pw"], 1e-9))
        #expect(approximatelyEqual(currentSource.parameters["pulse_per"], 100e-9))
        #expect(approximatelyEqual(firstPMOS.parameters["w"], 20e-6))
        #expect(approximatelyEqual(firstPMOS.parameters["l"], 1e-6))

        let catalog = DeviceCatalog.standard()
        let voltageKind = try #require(catalog.device(for: voltageSource.deviceKindID))
        let currentKind = try #require(catalog.device(for: currentSource.deviceKindID))
        let pmosKind = try #require(catalog.device(for: firstPMOS.deviceKindID))
        let voltageAnnotation = try #require(ComponentValueText.annotation(
            for: voltageSource,
            kind: voltageKind
        ))
        let currentAnnotation = try #require(ComponentValueText.annotation(
            for: currentSource,
            kind: currentKind
        ))
        let pmosAnnotation = try #require(ComponentValueText.annotation(
            for: firstPMOS,
            kind: pmosKind
        ))
        #expect(voltageAnnotation.contains("1.8"))
        #expect(!voltageAnnotation.contains("5 V"))
        #expect(currentAnnotation.contains("PULSE"))
        #expect(currentAnnotation.contains("20"))
        #expect(!currentAnnotation.contains("1 mA"))
        #expect(pmosAnnotation.contains("W="))
        #expect(pmosAnnotation.contains("L="))

        let regenerated = try NetlistGenerator().generate(
            from: document,
            title: "ring-oscillator-round-trip"
        )
        #expect(regenerated.contains("dc 1.8"))
        #expect(regenerated.contains("PULSE("))

        #expect(document.wires.allSatisfy { wire in
            wire.startPoint != wire.endPoint
                && (wire.startPoint.x == wire.endPoint.x
                    || wire.startPoint.y == wire.endPoint.y)
        })
        #expect(maximumEndpointFanIn(document.wires) <= 8)
        #expect(document.labels.filter { $0.name == "n5" }.count >= 2)

        let connections = connectionNamesByNet(document)
        #expect(Set(connections.keys) == Set(["0", "vdd", "n1", "n2", "n3", "n4", "n5"]))
        #expect(connections["vdd"] == Set([
            "v1.pos",
            "m1.source", "m1.bulk",
            "m3.source", "m3.bulk",
            "m5.source", "m5.bulk",
            "m7.source", "m7.bulk",
            "m9.source", "m9.bulk",
        ]))
        #expect(connections["0"] == Set([
            "v1.neg", "i1.neg",
            "m2.source", "m2.bulk",
            "m4.source", "m4.bulk",
            "m6.source", "m6.bulk",
            "m8.source", "m8.bulk",
            "m10.source", "m10.bulk",
            "c1.neg", "c2.neg", "c3.neg", "c4.neg", "c5.neg",
        ]))
        #expect(connections["n1"] == Set([
            "i1.pos", "m1.drain", "m2.drain", "m3.gate", "m4.gate", "c1.pos",
        ]))
        #expect(connections["n2"] == Set([
            "m3.drain", "m4.drain", "m5.gate", "m6.gate", "c2.pos",
        ]))
        #expect(connections["n3"] == Set([
            "m5.drain", "m6.drain", "m7.gate", "m8.gate", "c3.pos",
        ]))
        #expect(connections["n4"] == Set([
            "m7.drain", "m8.drain", "m9.gate", "m10.gate", "c4.pos",
        ]))
        #expect(connections["n5"] == Set([
            "m9.drain", "m10.drain", "m1.gate", "m2.gate", "c5.pos",
        ]))
    }

    @Test("Generic imports use orthogonal labeled stubs instead of averaged star wiring")
    func genericCircuitAvoidsStarWiring() async throws {
        let source = """
        V1 in 0 5
        R1 in out 1k
        C1 out 0 2p
        .end
        """
        let result = try await SPICESchematicImporter().importTopLevel(
            source: source,
            fileName: "divider.cir",
            topCellName: "divider"
        )
        let document = try #require(result.cells.first?.schematic)

        #expect(document.wires.allSatisfy { wire in
            wire.startPoint != wire.endPoint
                && (wire.startPoint.x == wire.endPoint.x
                    || wire.startPoint.y == wire.endPoint.y)
        })
        #expect(maximumEndpointFanIn(document.wires) <= 2)
        #expect(Set(connectionNamesByNet(document).keys) == Set(["0", "in", "out"]))
    }

    private func connectionNamesByNet(_ document: SchematicDocument) -> [String: Set<String>] {
        let namesByID = Dictionary(
            document.components.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        return Dictionary(
            uniqueKeysWithValues: NetExtractor().extract(from: document).map { net in
                let names = Set(net.connections.compactMap { pin -> String? in
                    guard let componentName = namesByID[pin.componentID] else { return nil }
                    return "\(componentName).\(pin.portID)"
                })
                return (net.name, names)
            }
        )
    }

    private func maximumEndpointFanIn(_ wires: [Wire]) -> Int {
        var counts: [PointKey: Int] = [:]
        for wire in wires {
            counts[PointKey(wire.startPoint), default: 0] += 1
            counts[PointKey(wire.endPoint), default: 0] += 1
        }
        return counts.values.max() ?? 0
    }

    private func approximatelyEqual(_ actual: Double?, _ expected: Double) -> Bool {
        guard let actual else { return false }
        let tolerance = max(1e-18, abs(expected) * 1e-12)
        return abs(actual - expected) <= tolerance
    }

    private struct PointKey: Hashable {
        let x: Int
        let y: Int

        init(_ point: CGPoint) {
            x = Int(point.x.rounded())
            y = Int(point.y.rounded())
        }
    }

    private static let ringOscillatorSource = """
    * Five-stage CMOS ring oscillator
    V1 vdd 0 dc 1.8
    I1 n1 0 PULSE(0 20u 0 100p 100p 1n 100n)
    M1 n1 n5 vdd vdd GENERIC_PMOS W=20u L=1u
    M2 n1 n5 0 0 GENERIC_NMOS W=10u L=1u
    M3 n2 n1 vdd vdd GENERIC_PMOS W=20u L=1u
    M4 n2 n1 0 0 GENERIC_NMOS W=10u L=1u
    M5 n3 n2 vdd vdd GENERIC_PMOS W=20u L=1u
    M6 n3 n2 0 0 GENERIC_NMOS W=10u L=1u
    M7 n4 n3 vdd vdd GENERIC_PMOS W=20u L=1u
    M8 n4 n3 0 0 GENERIC_NMOS W=10u L=1u
    M9 n5 n4 vdd vdd GENERIC_PMOS W=20u L=1u
    M10 n5 n4 0 0 GENERIC_NMOS W=10u L=1u
    C1 n1 0 20f
    C2 n2 0 20f
    C3 n3 0 20f
    C4 n4 0 20f
    C5 n5 0 20f
    .model GENERIC_PMOS PMOS level=1 gamma=0.4 kp=5e-05 lambda=0.04 phi=0.65 vto=-0.7
    .model GENERIC_NMOS NMOS level=1 gamma=0.4 kp=0.00011 lambda=0.04 phi=0.65 vto=0.7
    .tran 20p 50n
    .end
    """
}
