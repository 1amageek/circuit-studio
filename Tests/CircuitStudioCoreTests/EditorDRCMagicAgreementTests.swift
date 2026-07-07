import Foundation
import Testing
import LayoutCore
import LayoutIO
import LayoutTech
import LayoutVerify
@testable import CircuitStudioApp

/// Trust anchor for the editor's live DRC: on the same Sky130 geometry,
/// the in-process `LayoutDRCService` (which powers every live verdict in
/// the layout editor) and REAL Magic must point the same way — clean
/// agrees clean, violation agrees violation — for both healthy fixtures
/// and injected faults. This is the DRC counterpart of the Netgen LVS
/// agreement gate.
///
/// The gate compares verdict DIRECTION, not violation counts: the two
/// engines partition findings differently (Magic reports per-edge,
/// the editor per-pair), but a design one calls dirty and the other
/// calls clean would make the editor's "clean" badge a lie.
private let magicToolchainAvailable = MagicDRCSignoff.locate() != nil

@Suite(
    "Editor DRC vs Magic agreement",
    .serialized,
    .enabled(if: magicToolchainAvailable),
    .timeLimit(.minutes(8))
)
struct EditorDRCMagicAgreementTests {

    // MARK: - Agreement cases

    @Test("Clean met1 wire: both engines agree clean")
    func cleanWireAgreesClean() async throws {
        let document = Self.document(cell: "agree_clean", shapes: [
            Self.rect("met1", 0, 0, 2.0, 0.20)
        ])
        try await Self.expectAgreement(document: document, cell: "agree_clean", expectClean: true)
    }

    @Test("met1 spacing fault: both engines agree dirty")
    func spacingFaultAgreesDirty() async throws {
        // Two met1 wires 0.10 um apart against the 0.14 um met1.2 rule.
        let document = Self.document(cell: "agree_spacing", shapes: [
            Self.rect("met1", 0, 0, 2.0, 0.20),
            Self.rect("met1", 0, 0.30, 2.0, 0.20),
        ])
        try await Self.expectAgreement(document: document, cell: "agree_spacing", expectClean: false)
    }

    @Test("met1 width fault: both engines agree dirty")
    func widthFaultAgreesDirty() async throws {
        // 0.10 um wide met1 against the 0.14 um met1.1 rule.
        let document = Self.document(cell: "agree_width", shapes: [
            Self.rect("met1", 0, 0, 2.0, 0.10)
        ])
        try await Self.expectAgreement(document: document, cell: "agree_width", expectClean: false)
    }

    @Test("Clean li1-mcon-met1 contact stack: both engines agree clean")
    func cleanContactStackAgreesClean() async throws {
        // mcon cut 0.17 x 0.17 with generous li1/met1 cover on both sides.
        let document = Self.document(cell: "agree_stack", shapes: [
            Self.rect("li1", 0, 0, 0.6, 0.6),
            Self.rect("mcon", 0.215, 0.215, 0.17, 0.17),
            Self.rect("met1", 0, 0, 0.6, 0.6),
        ])
        try await Self.expectAgreement(document: document, cell: "agree_stack", expectClean: true)
    }

    @Test("Repaired fault: the N1 repair flips BOTH engines back to clean")
    func repairedSpacingFaultAgreesCleanAgain() async throws {
        // The full loop the repair engine promises: a fault both engines
        // see, repaired in-process, must satisfy Magic too — otherwise
        // the editor would 'fix' designs into states the signoff tool
        // still rejects.
        let tech = try Sky130LayoutTech.tech()
        var document = Self.document(cell: "agree_repair", shapes: [
            Self.rect("met1", 0, 0, 2.0, 0.20),
            Self.rect("met1", 0, 0.30, 2.0, 0.20),
        ])
        let cellID = try #require(document.topCellID)
        let violation = try #require(
            LayoutDRCService().run(document: document, tech: tech).violations
                .first { $0.kind == .minSpacing }
        )
        let engine = LayoutRepairEngine(document: document, tech: tech, cellID: cellID)
        guard case .repair(let repair) = try engine.repair(for: violation) else {
            Issue.record("the spacing fault must be repairable")
            return
        }
        guard var cell = document.cell(withID: cellID) else {
            Issue.record("fixture cell missing")
            return
        }
        for shape in repair.delta.updatedShapes {
            if let index = cell.shapes.firstIndex(where: { $0.id == shape.id }) {
                cell.shapes[index] = shape
            }
        }
        cell.shapes.append(contentsOf: repair.delta.addedShapes)
        document.updateCell(cell)

        try await Self.expectAgreement(document: document, cell: "agree_repair", expectClean: true)
    }

    // MARK: - Harness

    /// Runs both engines and requires the expected direction from each;
    /// a disagreement names which engine dissents.
    private static func expectAgreement(
        document: LayoutDocument,
        cell: String,
        expectClean: Bool
    ) async throws {
        let tech = try Sky130LayoutTech.tech()
        let editorViolations = LayoutDRCService().run(document: document, tech: tech).violations
        let editorClean = editorViolations.isEmpty
        #expect(
            editorClean == expectClean,
            "editor DRC dissents: \(editorViolations.map { ($0.kind.rawValue, $0.message) })"
        )

        let magicReport = try await runMagic(cell: cell, document: document, tech: tech)
        #expect(
            magicReport.passed == expectClean,
            "Magic dissents: \(magicReport.diagnostics.map { ($0.ruleID ?? "?", $0.message) })"
        )
    }

    private static func runMagic(
        cell: String,
        document: LayoutDocument,
        tech: LayoutTechDatabase
    ) async throws -> ExternalSignoffToolReport {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "editor-magic-agreement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gds = dir.appending(path: "\(cell).gds")
        try MaskDataFormatConverter(tech: tech).exportDocument(document, to: gds, format: .gds)

        let drc = try #require(MagicDRCSignoff.locate())
        let result = try await ExternalSignoffCommandService(parser: MagicDRCSignoff.reportParser).run(
            command: drc.command(cell: cell, gds: gds, artifactDirectory: dir),
            artifactDirectory: dir
        )
        return result.report
    }

    private static func rect(
        _ layer: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double
    ) -> LayoutShape {
        LayoutShape(
            layer: Sky130LayoutTech.layer(layer),
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: x, y: y),
                size: LayoutSize(width: w, height: h)
            ))
        )
    }

    private static func document(cell: String, shapes: [LayoutShape]) -> LayoutDocument {
        let layoutCell = LayoutCell(name: cell, shapes: shapes)
        return LayoutDocument(name: cell, cells: [layoutCell], topCellID: layoutCell.id)
    }
}
