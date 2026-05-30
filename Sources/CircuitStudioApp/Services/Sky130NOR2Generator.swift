import Foundation
import LayoutCore
import LayoutTech

/// Generates a Sky130 CMOS NOR2 standard-cell LAYOUT directly in the layout IR that is
/// full-signoff clean (real Magic DRC + Netgen LVS). Y = NOT(A OR B) — the dual of the
/// NAND2.
///
/// Topology: a parallel NMOS pull-down (two gates on one n+ strip, shared Y drain in the
/// middle, GND at both ends) and a series PMOS pull-up (two gates on one p+ strip in
/// n-well, contact-less shared node n1), joined by two vertical poly gates (A, B); Y is
/// an li1 L-jog from the NMOS shared drain up to the PMOS top node. VGND is a bottom rail
/// joining both NMOS sources + the p+ substrate tap; VPWR is a single landing at the
/// PMOS source + the n+ n-well tap.
public struct Sky130NOR2Generator: Sky130CellGenerator {

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

    /// The generated NOR2 layout (W = 0.42, L = 0.16 for all four FETs).
    public func generate(name: String = "nor2") -> LayoutDocument {
        var cell = LayoutCell(name: name, shapes: [
            // --- NMOS parallel pull-down (bottom): GND (ends) - Y (middle shared drain) ---
            rect("diff", 0.00, 0.00, 1.58, 0.42),
            rect("nsdm", -0.125, -0.125, 1.83, 0.67),
            rect("licon1", 0.10, 0.125, 0.17, 0.17),   // GND (left)
            rect("licon1", 0.65, 0.125, 0.17, 0.17),   // Y   (middle)
            rect("licon1", 1.31, 0.125, 0.17, 0.17),   // GND (right)
            // --- PMOS series pull-up (top): VDD (left) - n1 (shared) - Y (right) ---
            rect("diff", 0.00, 1.40, 1.58, 0.42),
            rect("psdm", -0.125, 1.275, 1.83, 0.67),
            rect("licon1", 0.10, 1.525, 0.17, 0.17),   // VDD (left)
            rect("licon1", 1.31, 1.525, 0.17, 0.17),   // Y   (right); middle n1 = no contact
            // --- shared vertical poly gates ---
            rect("poly", 0.42, -0.13, 0.16, 2.08),     // gate A
            rect("poly", 1.00, -0.13, 0.16, 2.08),     // gate B
            // --- n-well around the PMOS + n-well tap ---
            rect("nwell", -0.21, 1.19, 2.00, 1.57),
            // --- VGND: both NMOS sources + p+ substrate tap joined by a bottom rail ---
            rect("li1", 0.02, -1.08, 0.33, 1.455),     // GND-left down to rail
            rect("li1", 1.23, -1.08, 0.33, 1.455),     // GND-right down to rail
            rect("li1", 0.02, -1.08, 1.54, 0.62),      // VGND rail (below the NMOS, clears Y)
            rect("diff", 0.585, -1.20, 0.41, 0.41),    // p+ substrate tap
            rect("psdm", 0.46, -1.325, 0.66, 0.66),
            rect("licon1", 0.705, -1.08, 0.17, 0.17),
            // --- VPWR: PMOS source + n+ n-well tap, single left landing ---
            rect("li1", 0.02, 1.445, 0.38, 1.185),     // VPWR: VDD source + n-well tap
            rect("diff", 0.02, 2.17, 0.41, 0.41),      // n+ n-well tap
            rect("nsdm", -0.105, 2.045, 0.66, 0.66),
            rect("licon1", 0.14, 2.29, 0.17, 0.17),
            // --- output Y: L-jog from the NMOS shared drain up to the PMOS top node ---
            rect("li1", 0.57, 0.045, 0.33, 1.735),     // vertical: NMOS Y up into the field
            rect("li1", 0.57, 1.445, 0.99, 0.33),      // horizontal: across to the PMOS Y
        ])
        cell.labels = [
            label("A", "poly", 0.50, 0.90),
            label("B", "poly", 1.08, 0.90),
            label("Y", "li1", 0.73, 0.95),
            label("VPWR", "li1", 0.18, 2.00),
            label("VGND", "li1", 0.18, -0.70),
        ]
        return LayoutDocument(name: name, cells: [cell], topCellID: cell.id)
    }

    /// The reference schematic the generated layout matches under LVS. Ports (A, B, Y,
    /// VPWR, VGND) match the layout's labeled-net ports by name; `n1` is the internal
    /// series-PMOS node Netgen matches by topology.
    public func schematic(name: String = "nor2") -> String {
        """
        * generated Sky130 NOR2 reference
        .subckt \(name) A B Y VPWR VGND
        X0 n1 A VPWR VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        X1 Y B n1 VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        X2 Y A VGND VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        X3 Y B VGND VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        .ends
        """
    }
}
