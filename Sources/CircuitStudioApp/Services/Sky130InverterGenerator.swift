import Foundation
import LayoutCore
import LayoutTech

/// Generates a Sky130 CMOS inverter standard-cell LAYOUT directly in the layout IR,
/// on the real Sky130 tech, that is full-signoff clean: it passes real Magic Sky130
/// DRC and its Magic-extracted netlist matches the reference schematic under real
/// Netgen LVS. This is the Sky130-aware layout synthesis the agent loop needs — a
/// programmatic cell generator, not a hand-placed fixture.
///
/// The cell carries port net labels (A, Y, VPWR, VGND); the NMOS/PMOS bulks are tied
/// to their rails by p+/n+ substrate/well taps.
public struct Sky130InverterGenerator: Sendable {

    public init() {}

    private func rect(_ layer: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LayoutShape {
        LayoutShape(
            layer: Sky130LayoutTech.layer(layer),
            geometry: .rect(LayoutRect(origin: LayoutPoint(x: x, y: y), size: LayoutSize(width: w, height: h)))
        )
    }

    private func label(_ text: String, _ layer: String, _ x: Double, _ y: Double) -> LayoutLabel {
        LayoutLabel(text: text, position: LayoutPoint(x: x, y: y), layer: Sky130LayoutTech.layer(layer))
    }

    /// The narrowest device width whose fixed-position source/drain contact stays
    /// enclosed (0.125 from the diff bottom + 0.17 contact + 0.06 of diff above).
    public static let minWidth = 0.36

    /// The generated inverter layout for transistor width `width` (µm, both FETs;
    /// L = 0.16). The whole PMOS row, n-well, n-well tap, poly endcap, and routing are
    /// derived from the active height so the floorplan scales while keeping every
    /// Sky130 minimum (poly endcap 0.13, contact enclosures, tap-contact enclosure
    /// 0.12, n-well enclosure 0.18). Verified DRC + LVS clean across the supported range.
    public func generate(name: String = "inverter", width: Double = 0.42) -> LayoutDocument {
        let w = max(Self.minWidth, width)
        let pmosBot = w + 0.98                 // PMOS active bottom (field gap 0.98)
        let pmosTop = pmosBot + w              // PMOS active top
        let tapBot = pmosTop + 0.45            // n-well tap, clear of the poly endcap
        let shapes: [LayoutShape] = [
            // NMOS active + n+ implant + source/drain contacts
            rect("diff", 0.00, 0.00, 1.00, w),
            rect("nsdm", -0.125, -0.125, 1.25, w + 0.25),
            rect("licon1", 0.10, 0.125, 0.17, 0.17),
            rect("licon1", 0.73, 0.125, 0.17, 0.17),
            // PMOS active + p+ implant + source/drain contacts
            rect("diff", 0.00, pmosBot, 1.00, w),
            rect("psdm", -0.125, pmosBot - 0.125, 1.25, w + 0.25),
            rect("licon1", 0.10, pmosBot + 0.125, 0.17, 0.17),
            rect("licon1", 0.73, pmosBot + 0.125, 0.17, 0.17),
            // n-well enclosing the PMOS diff and the n-well tap by 0.18
            rect("nwell", -0.21, pmosBot - 0.21, 1.42, (tapBot + 0.41 + 0.18) - (pmosBot - 0.21)),
            // shared poly gate (input A), endcap 0.13 beyond both actives
            rect("poly", 0.42, -0.13, 0.16, (pmosTop + 0.13) - (-0.13)),
            // output li1 joining the two drains (Y)
            rect("li1", 0.65, 0.045, 0.33, (pmosBot + 0.375) - 0.045),
            // p+ substrate tap (-> VGND), fixed below the NMOS
            rect("diff", 0.045, -0.785, 0.41, 0.41),
            rect("psdm", -0.08, -0.91, 0.66, 0.66),
            rect("licon1", 0.165, -0.665, 0.17, 0.17),
            rect("li1", 0.02, -0.81, 0.41, 0.375 - (-0.81)),     // VGND: NMOS source + substrate tap
            // n+ n-well tap (-> VPWR), above the PMOS inside the n-well
            rect("diff", 0.045, tapBot, 0.41, 0.41),
            rect("nsdm", -0.08, tapBot - 0.125, 0.66, 0.66),
            rect("licon1", 0.165, tapBot + 0.12, 0.17, 0.17),
            rect("li1", 0.02, pmosBot + 0.045, 0.41, (tapBot + 0.29 + 0.08) - (pmosBot + 0.045)),  // VPWR
        ]
        var cell = LayoutCell(name: name, shapes: shapes)
        cell.labels = [
            label("A", "poly", 0.50, w + 0.50),
            label("Y", "li1", 0.81, 0.95),
            label("VPWR", "li1", 0.18, pmosBot + 0.50),
            label("VGND", "li1", 0.18, 0.20),
        ]
        return LayoutDocument(name: name, cells: [cell], topCellID: cell.id)
    }

    /// The reference schematic the generated layout matches under LVS (port-less, so
    /// it compares against the extracted cell's labeled nets directly).
    public func schematic(name: String = "inverter", width: Double = 0.42) -> String {
        let w = String(format: "%g", max(Self.minWidth, width))
        return """
        * generated Sky130 inverter reference
        .subckt \(name)
        X0 Y A VPWR VPWR sky130_fd_pr__pfet_01v8 w=\(w) l=0.16
        X1 Y A VGND VGND sky130_fd_pr__nfet_01v8 w=\(w) l=0.16
        .ends
        """
    }
}
