import Foundation
import LayoutCore
import Testing
@testable import CircuitStudioApp

@Suite("Layout trust evaluation")
struct LayoutTrustEvaluationServiceTests {

    @Test("Property-owned route geometry passes topology evaluation")
    func propertyOwnedRoutePasses() throws {
        let document = document(shapes: [
            rect("met3", -0.25, -0.25, 0.50, 0.50, properties: [
                NetAwareLayoutEvaluator.netNameProperty: "n"
            ]),
            rect("via3", -0.10, -0.10, 0.20, 0.20, properties: [
                NetAwareLayoutEvaluator.netNameProperty: "n"
            ]),
            rect("met4", -0.25, -0.25, 0.50, 0.50, properties: [
                NetAwareLayoutEvaluator.netNameProperty: "n"
            ]),
        ])

        let report = try LayoutTrustEvaluationService().evaluate(document: document, tech: Sky130LayoutTech.tech())

        #expect(report.passed)
        #expect(report.ownedShapeCount == 3)
        #expect(report.unownedShapeCount == 0)
        #expect(report.netAwareReport.passed)
    }

    @Test("LayoutNet IDs resolve shape ownership without a string property")
    func netIDOwnershipPasses() throws {
        let netID = UUID(uuidString: "00000000-0000-0000-0000-000000001001")!
        let document = document(
            shapes: [
                rect("met3", 0.0, 0.0, 1.0, 0.30, netID: netID),
                rect("met3", 0.9, 0.0, 1.0, 0.30, netID: netID),
            ],
            nets: [LayoutNet(id: netID, name: "sig")]
        )

        let report = try LayoutTrustEvaluationService().evaluate(document: document, tech: Sky130LayoutTech.tech())

        #expect(report.passed)
        #expect(report.ownershipMap.records.allSatisfy { $0.netName == "sig" })
    }

    @Test("LayoutVia objects participate in net-aware connectivity")
    func layoutViaConnectsAdjacentLayers() throws {
        let netID = UUID(uuidString: "00000000-0000-0000-0000-000000001101")!
        let cell = LayoutCell(
            name: "TOP",
            shapes: [
                rect("met3", -0.25, -0.25, 0.50, 0.50, netID: netID),
                rect("met4", -0.25, -0.25, 0.50, 0.50, netID: netID),
            ],
            vias: [LayoutVia(viaDefinitionID: "via3", position: LayoutPoint(x: 0, y: 0), netID: netID)],
            nets: [LayoutNet(id: netID, name: "sig")]
        )
        let document = LayoutDocument(name: "via-trust", cells: [cell], topCellID: cell.id)

        let report = try LayoutTrustEvaluationService().evaluate(document: document, tech: Sky130LayoutTech.tech())

        #expect(report.passed)
        #expect(report.ownedShapeCount == 3)
    }

    @Test("Unowned evaluated routing geometry fails but still writes evidence artifacts")
    func unownedRoutingShapeFailsAndWritesArtifacts() throws {
        let root = try temporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let document = document(shapes: [
            rect("met3", 0.0, 0.0, 1.0, 0.30),
        ])

        let report = try LayoutTrustEvaluationService().evaluate(document: document, tech: Sky130LayoutTech.tech())
        let artifacts = try LayoutTrustArtifactWriter().write(
            document: document,
            report: report,
            to: root.appending(path: "layout-trust")
        )

        #expect(!report.passed)
        #expect(report.unownedShapeCount == 1)
        #expect(FileManager.default.fileExists(atPath: artifacts.canonicalLayoutPath))
        #expect(FileManager.default.fileExists(atPath: artifacts.ownershipMapPath))
        #expect(FileManager.default.fileExists(atPath: artifacts.netAwareReportPath))
        #expect(FileManager.default.fileExists(atPath: artifacts.layoutTrustReportPath))
    }

    @Test("Non-policy layers are ignored rather than silently treated as trusted routes")
    func nonPolicyLayersAreIgnored() throws {
        let document = document(shapes: [
            rect("diff", 0.0, 0.0, 1.0, 0.30),
        ])

        let report = try LayoutTrustEvaluationService().evaluate(document: document, tech: Sky130LayoutTech.tech())

        #expect(report.passed)
        #expect(report.ignoredShapeCount == 1)
        #expect(report.evaluatedShapeCount == 0)
    }

    @Test("Explicit exemptions keep non-net route-layer geometry reviewable")
    func explicitExemptionIsRecorded() throws {
        let document = document(shapes: [
            rect("met3", 0.0, 0.0, 1.0, 0.30, properties: [
                "layout.trust.purpose": "fill"
            ]),
        ])

        let report = try LayoutTrustEvaluationService().evaluate(document: document, tech: Sky130LayoutTech.tech())

        #expect(report.passed)
        #expect(report.exemptShapeCount == 1)
        #expect(report.ownershipMap.records.first?.status == .exempt)
    }

    private func document(
        shapes: [LayoutShape],
        nets: [LayoutNet] = []
    ) -> LayoutDocument {
        let cell = LayoutCell(name: "TOP", shapes: shapes, nets: nets)
        return LayoutDocument(name: "trust", cells: [cell], topCellID: cell.id)
    }

    private func rect(
        _ layer: String,
        _ x: Double,
        _ y: Double,
        _ w: Double,
        _ h: Double,
        netID: UUID? = nil,
        properties: [String: String] = [:]
    ) -> LayoutShape {
        LayoutShape(
            layer: Sky130LayoutTech.layer(layer),
            netID: netID,
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: x, y: y),
                size: LayoutSize(width: w, height: h)
            )),
            properties: properties
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "layout-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryDirectory(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove temporary directory: \(error.localizedDescription)")
        }
    }
}
