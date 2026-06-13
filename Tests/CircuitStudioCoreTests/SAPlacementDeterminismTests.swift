import Foundation
import CircuitPhysicalDesign
import Testing
import SchematicEditor
import CircuitStudioCore
@testable import CircuitStudioApp

/// The SA placement determinism oracle. Component UUIDs are freshly
/// random on every run, so any dictionary-order dependence in the
/// annealer (instance picks, floating-point accumulation order) forks
/// the trajectory despite the seeded RNG — which is exactly how the
/// headless round-trip tests used to fail at random: a tail-of-the-
/// distribution placement scattered cells until contact arrays sat
/// inside each other's spacing and a net became unroutable.
@Suite("SA placement determinism", .timeLimit(.minutes(3)))
struct SAPlacementDeterminismTests {
    @MainActor
    @Test func optimizedPlacementIsIdenticalAcrossFreshUUIDRuns() throws {
        var summaries: Set<String> = []
        for _ in 0..<5 {
            let document = SchematicPreview.cmosInverterViewModel().document
            let output = try CircuitLayoutSynthesizer().generate(
                from: document,
                catalog: .standard(),
                placementStrategy: .optimized
            )
            let top = output.document.cells.first(where: { $0.name == "TOP" })
            let placements = top?.instances
                .map { "\($0.name)@(\($0.transform.translation.x),\($0.transform.translation.y))" }
                .sorted()
                .joined(separator: " ") ?? "-"
            summaries.insert(
                "placements=\(placements) unrouted=\(output.unroutedNets.sorted()) violations=\(output.drcResult.violations.count)"
            )
        }
        #expect(summaries.count == 1, "SA placement varies across identical inputs: \(summaries)")
    }
}
