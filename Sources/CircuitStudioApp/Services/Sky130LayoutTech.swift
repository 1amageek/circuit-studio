import Foundation
import LayoutCore
import LayoutTech

/// A `LayoutTechDatabase` for the open Sky130 PDK: the real GDS layer numbers and
/// the core design rules, so a generated layout exports to Sky130-layer GDS that
/// Magic's Sky130 DRC can actually see and check. The generic `sampleProcess()` tech
/// uses ~180nm logical layers Magic's Sky130 techfile does not recognize.
///
/// Layer numbers are the canonical Sky130 drawing layers (datatype 20 for shapes,
/// 44 for contacts/vias); dimensions are the Sky130 minimum width/spacing rules.
public enum Sky130LayoutTech {

    /// A layer id by name on the drawing purpose (e.g. `layer("met1")`).
    public static func layer(_ name: String) -> LayoutLayerID {
        LayoutLayerID(name: name, purpose: name.contains("con") ? "cut" : "drawing")
    }

    private static func def(
        _ name: String, _ display: String, _ gds: Int, _ dt: Int,
        rgb: (Double, Double, Double), fill: LayoutFillPattern = .forwardDiagonal
    ) -> LayoutLayerDefinition {
        LayoutLayerDefinition(
            id: layer(name), displayName: display, gdsLayer: gds, gdsDatatype: dt,
            color: LayoutColor(red: rgb.0, green: rgb.1, blue: rgb.2), fillPattern: fill
        )
    }

    private static func rules(_ name: String, width: Double, spacing: Double, area: Double = 0) -> LayoutLayerRuleSet {
        LayoutLayerRuleSet(
            layerID: layer(name), minWidth: width, minSpacing: spacing,
            minArea: area, minDensity: 0.0, maxDensity: 1.0
        )
    }

    public static func tech() -> LayoutTechDatabase {
        let layers: [LayoutLayerDefinition] = [
            def("nwell", "N-Well", 64, 20, rgb: (0.4, 0.2, 0.2)),
            def("diff", "Diffusion", 65, 20, rgb: (0.2, 0.6, 0.2)),
            def("tap", "Tap", 65, 44, rgb: (0.3, 0.5, 0.3)),
            def("nsdm", "N+ Implant", 93, 44, rgb: (0.5, 0.5, 0.2)),
            def("psdm", "P+ Implant", 94, 20, rgb: (0.5, 0.2, 0.5)),
            def("poly", "Poly", 66, 20, rgb: (0.8, 0.1, 0.1)),
            def("npc", "Nitride Poly Cut", 95, 20, rgb: (0.6, 0.3, 0.3)),
            def("licon1", "Diff/Poly Contact", 66, 44, rgb: (0.7, 0.7, 0.2), fill: .crosshatch),
            def("li1", "Local Interconnect", 67, 20, rgb: (0.7, 0.4, 0.7)),
            def("mcon", "li-met1 Via", 67, 44, rgb: (0.8, 0.8, 0.2), fill: .crosshatch),
            def("met1", "Metal1", 68, 20, rgb: (0.3, 0.5, 0.9)),
            def("via", "met1-met2 Via", 68, 44, rgb: (0.8, 0.6, 0.2), fill: .crosshatch),
            def("met2", "Metal2", 69, 20, rgb: (0.2, 0.7, 0.7)),
            def("via2", "met2-met3 Via", 69, 44, rgb: (0.7, 0.5, 0.3), fill: .crosshatch),
            def("met3", "Metal3", 70, 20, rgb: (0.5, 0.3, 0.7)),
            def("via3", "met3-met4 Via", 70, 44, rgb: (0.6, 0.4, 0.4), fill: .crosshatch),
            def("met4", "Metal4", 71, 20, rgb: (0.4, 0.4, 0.7)),
        ]

        // Sky130 minimum width / spacing (µm) for the layers an inverter uses.
        let layerRules: [LayoutLayerRuleSet] = [
            rules("nwell", width: 0.84, spacing: 1.27),
            rules("diff", width: 0.15, spacing: 0.27),
            rules("tap", width: 0.15, spacing: 0.27),
            rules("nsdm", width: 0.38, spacing: 0.38),
            rules("psdm", width: 0.38, spacing: 0.38),
            rules("poly", width: 0.15, spacing: 0.21),
            rules("npc", width: 0.27, spacing: 0.27),
            rules("licon1", width: 0.17, spacing: 0.17),
            rules("li1", width: 0.17, spacing: 0.17, area: 0.0561),
            rules("mcon", width: 0.17, spacing: 0.19),
            rules("met1", width: 0.14, spacing: 0.14),
            rules("via", width: 0.15, spacing: 0.17),
            rules("met2", width: 0.14, spacing: 0.14),
            rules("via2", width: 0.20, spacing: 0.20),
            rules("met3", width: 0.30, spacing: 0.30),
            rules("via3", width: 0.20, spacing: 0.20),
            rules("met4", width: 0.30, spacing: 0.30),
        ]

        // licon1: diff/poly -> li1; mcon: li1 -> met1.
        let vias: [LayoutViaDefinition] = [
            LayoutViaDefinition(
                id: "licon1", cutLayer: layer("licon1"), topLayer: layer("li1"), bottomLayer: layer("diff"),
                cutSize: LayoutSize(width: 0.17, height: 0.17),
                enclosure: LayoutViaEnclosure(top: 0.08, bottom: 0.06), cutSpacing: 0.17
            ),
            LayoutViaDefinition(
                id: "mcon", cutLayer: layer("mcon"), topLayer: layer("met1"), bottomLayer: layer("li1"),
                cutSize: LayoutSize(width: 0.17, height: 0.17),
                enclosure: LayoutViaEnclosure(top: 0.06, bottom: 0.0), cutSpacing: 0.19
            ),
            // via: met1 -> met2 (the second routing layer for channel routing).
            LayoutViaDefinition(
                id: "via", cutLayer: layer("via"), topLayer: layer("met2"), bottomLayer: layer("met1"),
                cutSize: LayoutSize(width: 0.15, height: 0.15),
                enclosure: LayoutViaEnclosure(top: 0.055, bottom: 0.055), cutSpacing: 0.17
            ),
            // via2: met2 -> met3 (the third layer — over-the-cell global routing for
            // multi-row designs, breaking the 2-layer single-channel ceiling).
            LayoutViaDefinition(
                id: "via2", cutLayer: layer("via2"), topLayer: layer("met3"), bottomLayer: layer("met2"),
                cutSize: LayoutSize(width: 0.20, height: 0.20),
                enclosure: LayoutViaEnclosure(top: 0.065, bottom: 0.085), cutSpacing: 0.20
            ),
            // via3: met3 -> met4 (the fourth layer — gives the maze router a second
            // over-the-cell direction, so many nets route Manhattan above the cells).
            LayoutViaDefinition(
                id: "via3", cutLayer: layer("via3"), topLayer: layer("met4"), bottomLayer: layer("met3"),
                cutSize: LayoutSize(width: 0.20, height: 0.20),
                enclosure: LayoutViaEnclosure(top: 0.065, bottom: 0.065), cutSpacing: 0.20
            ),
        ]

        return LayoutTechDatabase(
            units: .defaultUnits,
            grid: 0.005,
            layers: layers,
            vias: vias,
            layerRules: layerRules
        )
    }
}
