import Foundation
import Testing
import LayoutCore
import LayoutTech
import LayoutIO
@testable import CircuitStudioApp

/// Proves the density axis is scored by a REAL tool, and that metal fill closes a sparse-metal
/// failure. A sparse met1 cell measured by Magic's `cif coverage` falls below the density floor;
/// after `MetalFillInserter` tiles fill across it, Magic re-measures the coverage inside the
/// window. Gated on the toolchain.
@Suite("Magic density signoff + fill (gated)")
struct MagicDensitySignoffTests {

    static let available = MagicDensitySignoff.locate() != nil

    private func rect(_ layer: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutShape {
        LayoutShape(
            layer: Sky130LayoutTech.layer(layer),
            geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h)))
        )
    }

    /// A 10 x 10 µm cell whose only metal is a thin met1 frame — its coverage is a few
    /// percent, far below any CMP density floor. The frame fixes the cell's bounding box
    /// (so `cif coverage` has a stable denominator) while leaving the interior empty.
    private func sparseMet1Frame(cell: String, span: Double = 10.0, bar: Double = 0.14) -> LayoutDocument {
        let shapes: [LayoutShape] = [
            rect("met1", 0, 0, span, bar),                 // bottom
            rect("met1", 0, span - bar, span, bar),        // top
            rect("met1", 0, 0, bar, span),                 // left
            rect("met1", span - bar, 0, bar, span),        // right
        ]
        let cellIR = LayoutCell(name: cell, shapes: shapes)
        return LayoutDocument(name: cell, cells: [cellIR], topCellID: cellIR.id)
    }

    private func measureDensity(cell: String, document: LayoutDocument, window: DensityWindow) async throws -> DensityReport {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sky130-density-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "\(cell).gds")
        try MaskDataFormatConverter(tech: try Sky130LayoutTech.tech()).exportDocument(document, to: gds, format: .gds)

        let density = try #require(MagicDensitySignoff.locate())
        return try await density.run(cell: cell, gds: gds, window: window, artifactDirectory: dir)
    }

    @Test("A sparse met1 cell is caught below the density floor, then metal fill closes it",
          .enabled(if: MagicDensitySignoffTests.available), .timeLimit(.minutes(5)))
    func sparseCaughtThenFilled() async throws {
        let window = DensityWindow(minDensity: 0.35, maxDensity: 0.85, layers: ["MET1"])

        // 1) Sparse frame: measured coverage is far below the 35% floor -> fails.
        let sparse = sparseMet1Frame(cell: "dens_sparse")
        let before = try await measureDensity(cell: "dens_sparse", document: sparse, window: window)
        let met1Before = try #require(before.layers.first { $0.layer == "MET1" })
        #expect(!before.passed, "sparse frame must fail; measured \(met1Before.status)")
        #expect(met1Before.coverage < window.minDensity)

        // 2) Tile metal fill over the cell (0.40 µm squares on 0.60 µm pitch ≈ 44% grid
        //    density), then RE-MEASURE with Magic. The fill brings MET1 into the window.
        let filled = MetalFillInserter().fill(
            sparse, config: .init(layerID: LayoutTechnologyResource.layer("met1"), fillSize: 0.40, pitch: 0.60))
        let after = try await measureDensity(cell: "dens_filled", document: renamed(filled, to: "dens_filled"), window: window)
        let met1After = try #require(after.layers.first { $0.layer == "MET1" })
        #expect(after.passed, "after fill MET1 must be within the window; measured \(met1After.status)")
        #expect(met1After.coverage > met1Before.coverage, "fill must raise measured coverage")
        #expect(met1After.coverage >= window.minDensity)
    }

    /// Rename a document + its top cell so two exported GDS files in one test don't collide
    /// on cell name when Magic loads them.
    private func renamed(_ document: LayoutDocument, to name: String) -> LayoutDocument {
        var doc = document
        doc.name = name
        if let idx = doc.topCellID.flatMap({ id in doc.cells.firstIndex { $0.id == id } }) ?? (doc.cells.isEmpty ? nil : 0) {
            doc.cells[idx].name = name
        }
        return doc
    }
}
