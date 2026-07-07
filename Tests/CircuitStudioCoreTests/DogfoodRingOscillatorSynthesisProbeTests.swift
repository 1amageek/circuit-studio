import Foundation
import Testing
import CircuitPhysicalDesign
@testable import CircuitStudioApp

/// Regression gate for the ring-oscillator dogfood design: the synthesis
/// pipeline (place, route, repair loop, same-net sliver bridging) must
/// hand the round trip a DRC-clean, fully routed layout. When it fails,
/// the violations are printed with their owning nets and geometry so the
/// gap is attributable, not just counted.
@Suite("Dogfood ring oscillator synthesis", .timeLimit(.minutes(3)))
struct DogfoodRingOscillatorSynthesisProbeTests {

    @Test func synthesizedRingOscillatorIsDRCCleanAndFullyRouted() throws {
        let workspaceRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let specURL = workspaceRoot
            .appending(path: "dogfood/ring-oscillator-001/ring-oscillator.design.json")
        let data = try Data(contentsOf: specURL)
        let spec = try JSONDecoder().decode(DesignFlowDesignSpec.self, from: data)
        let design = try spec.build()

        let output = try CircuitLayoutSynthesizer().generate(
            from: design.schematic,
            catalog: .standard(),
            placementStrategy: .optimized
        )

        let cellsByID = Dictionary(uniqueKeysWithValues: output.document.cells.map { ($0.id, $0) })
        for violation in output.drcResult.violations {
            print("VIOLATION kind=\(violation.kind.rawValue) message=\(violation.message) region=\(violation.region)")
            for cell in cellsByID.values {
                for shape in cell.shapes where violation.shapeIDs.contains(shape.id) {
                    let netName = cell.nets.first { $0.id == shape.netID }?.name ?? "<none>"
                    print("  SHAPE cell=\(cell.name) layer=\(shape.layer.name) net=\(netName) geom=\(shape.geometry)")
                }
            }
        }
        #expect(output.unroutedNets.isEmpty)
        #expect(output.drcResult.violations.isEmpty)
    }
}
