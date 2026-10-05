import Foundation
import Testing
import CircuitPhysicalDesign
import LayoutAutoGen
import LayoutCore
import LayoutTech
import LayoutVerify

@Suite("Finite-resistance physical verification", .timeLimit(.minutes(1)))
struct DeviceElectricalVerificationTests {
    private func source() throws -> LayoutDocument {
        let cell = try ResistorCellGenerator().generateCell(deviceKindID: "resistor", instanceName: "R",
            parameters: ["r": 1_000], tech: .sampleProcess())
        let a = UUID(), b = UUID(), c = UUID()
        let root = LayoutCell(name: "ROOT", instances: [
            .init(cellID: cell.id, name: "R1", terminalNetIDs: ["neg": a, "pos": b]),
            .init(cellID: cell.id, name: "R2", transform: .init(translation: .init(x: 5, y: 0)),
                terminalNetIDs: ["neg": b, "pos": c])],
            nets: [.init(id: a, name: "A"), .init(id: b, name: "B"), .init(id: c, name: "C")])
        return .init(name: "resistor-verification", cells: [root, cell], topCellID: root.id)
    }

    @Test func actualGeneratorRolesSeparateBodiesAndRemainInSerializedNativeReport() throws {
        let document = try source()
        let report = PhysicalVerificationService().runDRC(document: document, tech: .sampleProcess())
        let native = try #require(report.nativeResult)
        #expect(native.electricalContext == .deviceAwareMOSAndPolyResistors(
            polyLayer: ResistorCellGenerator.polyLayerID, bodyMarkerLayer: ResistorCellGenerator.bodyMarkerLayerID))
        #expect(!native.violations.contains { $0.kind == .overlapShort })
        #expect(native.diagnostics.isEmpty)
        #expect(report.passed)
        let hierarchy = try #require(native.sourceHierarchy)
        #expect(hierarchy.occurrences.count == 3)
        #expect(hierarchy.shapes.filter { $0.layer == ResistorCellGenerator.bodyMarkerLayerID }.count == 2)
        #expect(hierarchy.pins.count == 4)
        let decoded = try JSONDecoder().decode(LayoutDRCResult.self, from: JSONEncoder().encode(native))
        #expect(decoded == native)
    }

    @Test func invalidBodyIsFailedInspectionAndActualTerminalBypassIsStillAShort() throws {
        var document = try source()
        let marker = try #require(document.cells[1].shapes.firstIndex {
            $0.layer == ResistorCellGenerator.bodyMarkerLayerID
        })
        document.cells[1].shapes[marker].geometry = .rect(.init(origin: .init(x: 1, y: 0.1),
            size: .init(width: 0.1, height: 0.1)))
        let failed = PhysicalVerificationService().runDRC(document: document, tech: .sampleProcess())
        #expect(!failed.passed)
        #expect(failed.nativeResult?.diagnostics.contains { $0.severity == .error } == true)
        document = try source()
        let left = try #require(document.cells[1].pins.first { $0.name == "neg" })
        let right = try #require(document.cells[1].pins.first { $0.name == "pos" })
        document.cells[1].shapes.append(.init(layer: .init(name: "M1", purpose: "drawing"),
            geometry: .polygon(.init(points: [.init(x: left.position.x, y: 0.1),
                .init(x: right.position.x, y: 0.1), .init(x: right.position.x, y: 0.3),
                .init(x: left.position.x, y: 0.3)]))))
        let short = PhysicalVerificationService().runDRC(document: document, tech: .sampleProcess())
        #expect(!short.passed)
        #expect(short.nativeResult?.violations.filter { $0.kind == .overlapShort }.count == 2)
    }
}
