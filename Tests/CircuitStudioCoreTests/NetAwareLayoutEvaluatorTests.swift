import Foundation
import LayoutCore
import Testing
@testable import CircuitStudioApp

@Suite("Net-aware layout evaluator")
struct NetAwareLayoutEvaluatorTests {

    @Test("Same-layer geometry owned by different nets is reported as a physical short")
    func detectsSameLayerShort() {
        let report = NetAwareLayoutEvaluator().evaluate(shapes: [
            owned("a", rect("met3", 0.0, 0.0, 1.15, 0.30)),
            owned("b", rect("met3", 0.85, 0.0, 1.15, 0.30)),
        ], tech: Sky130LayoutTech.tech())

        #expect(!report.passed)
        #expect(report.shorts.count == 1)
        #expect(report.shorts.first?.netNames == ["a", "b"])
        #expect(report.opens.isEmpty)
    }

    @Test("Different routing layers may cross without a cut-layer bridge")
    func allowsLayerCrossingWithoutBridge() {
        let report = NetAwareLayoutEvaluator().evaluate(shapes: [
            owned("h", rect("met3", -0.15, -0.15, 2.30, 0.30)),
            owned("v", rect("met4", 0.85, -1.15, 0.30, 2.30)),
        ], tech: Sky130LayoutTech.tech())

        #expect(report.passed)
    }

    @Test("Cut-layer bridge connects the same net across adjacent conductors")
    func connectsThroughVia() {
        let report = NetAwareLayoutEvaluator().evaluate(shapes: [
            owned("n", rect("met3", -0.25, -0.25, 0.50, 0.50)),
            owned("n", rect("via3", -0.10, -0.10, 0.20, 0.20)),
            owned("n", rect("met4", -0.25, -0.25, 0.50, 0.50)),
        ], tech: Sky130LayoutTech.tech())

        #expect(report.passed)
    }

    @Test("Disconnected geometry owned by one net is reported as an open")
    func detectsOpen() {
        let report = NetAwareLayoutEvaluator().evaluate(shapes: [
            owned("n", rect("met3", 0.0, 0.0, 0.50, 0.30)),
            owned("n", rect("met3", 2.0, 0.0, 0.50, 0.30)),
        ], tech: Sky130LayoutTech.tech())

        #expect(!report.passed)
        #expect(report.opens.count == 1)
        #expect(report.opens.first?.netName == "n")
        #expect(report.shorts.isEmpty)
    }

    @Test("Tagged shape evaluation fails loud when a generated shape has no net owner")
    func taggedEvaluationRequiresNetOwner() {
        let tagged = rect("met3", 0.0, 0.0, 0.50, 0.30, properties: [
            NetAwareLayoutEvaluator.netNameProperty: "n"
        ])
        let unowned = rect("met3", 2.0, 0.0, 0.50, 0.30)

        let report = NetAwareLayoutEvaluator().evaluateTaggedShapes(
            [tagged, unowned],
            tech: Sky130LayoutTech.tech()
        )

        #expect(!report.passed)
        #expect(report.unownedShapes.count == 1)
    }

    @Test("Owned-shape evaluation treats blank net names as unowned geometry")
    func ownedEvaluationRejectsBlankNetOwner() {
        let report = NetAwareLayoutEvaluator().evaluate(shapes: [
            owned(" ", rect("met3", 0.0, 0.0, 0.50, 0.30)),
        ], tech: Sky130LayoutTech.tech())

        #expect(!report.passed)
        #expect(report.unownedShapes.count == 1)
        #expect(report.shorts.isEmpty)
        #expect(report.opens.isEmpty)
    }

    private func owned(_ netName: String, _ shape: LayoutShape) -> NetAwareLayoutEvaluator.OwnedShape {
        NetAwareLayoutEvaluator.OwnedShape(netName: netName, shape: shape)
    }

    private func rect(
        _ layer: String,
        _ x: Double,
        _ y: Double,
        _ w: Double,
        _ h: Double,
        properties: [String: String] = [:]
    ) -> LayoutShape {
        LayoutShape(
            layer: Sky130LayoutTech.layer(layer),
            geometry: .rect(LayoutRect(
                origin: LayoutPoint(x: x, y: y),
                size: LayoutSize(width: w, height: h)
            )),
            properties: properties
        )
    }
}
