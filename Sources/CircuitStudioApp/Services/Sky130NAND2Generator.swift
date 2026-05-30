import Foundation
import LayoutCore
import LayoutTech

/// Generates a Sky130 CMOS NAND2 standard-cell LAYOUT directly in the layout IR that is
/// full-signoff clean: it passes real Magic Sky130 DRC and its Magic-extracted netlist
/// matches the reference schematic under real Netgen LVS. Y = NOT(A AND B).
///
/// Topology: a series NMOS pull-down (two gates on one n+ strip, contact-less shared
/// node n1) and a parallel PMOS pull-up (two gates on one p+ strip in n-well, shared Y
/// drain in the middle), joined by two vertical poly gates (A, B); Y is routed as an li1
/// L-jog from the PMOS shared drain to the NMOS top node, with p+/n+ taps to the rails.
public struct Sky130NAND2Generator: Sky130CellGenerator {

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

    /// The generated NAND2 layout (W = 0.42, L = 0.16 for all four FETs).
    public func generate(name: String = "nand2") -> LayoutDocument {
        var cell = LayoutCell(name: name, shapes: [
            // --- NMOS series pull-down (bottom): GND (left) - n1 (shared) - Y (right) ---
            rect("diff", 0.00, 0.00, 1.58, 0.42),
            rect("nsdm", -0.125, -0.125, 1.83, 0.67),
            rect("licon1", 0.10, 0.125, 0.17, 0.17),   // GND (left)
            rect("licon1", 1.31, 0.125, 0.17, 0.17),   // Y   (right); middle n1 = no contact
            // --- PMOS parallel pull-up (top): VDD (ends) - Y (middle shared drain) ---
            rect("diff", 0.00, 1.40, 1.58, 0.42),
            rect("psdm", -0.125, 1.275, 1.83, 0.67),
            rect("licon1", 0.10, 1.525, 0.17, 0.17),   // VDD (left)
            rect("licon1", 0.65, 1.525, 0.17, 0.17),   // Y   (middle)
            rect("licon1", 1.31, 1.525, 0.17, 0.17),   // VDD (right)
            // --- shared vertical poly gates ---
            rect("poly", 0.42, -0.13, 0.16, 2.08),     // gate A
            rect("poly", 1.00, -0.13, 0.16, 2.08),     // gate B
            // --- n-well around the PMOS + n-well tap ---
            rect("nwell", -0.21, 1.19, 2.00, 1.60),
            // --- p+ substrate tap (-> VGND), below the NMOS left ---
            rect("diff", 0.02, -0.785, 0.41, 0.41),
            rect("psdm", -0.105, -0.91, 0.66, 0.66),
            rect("licon1", 0.14, -0.665, 0.17, 0.17),
            rect("li1", 0.02, -0.81, 0.38, 1.185),     // VGND: NMOS GND + substrate tap
            // --- n+ n-well tap (-> VPWR), top middle ---
            rect("diff", 0.585, 2.20, 0.41, 0.41),
            rect("nsdm", 0.46, 2.075, 0.66, 0.66),
            rect("licon1", 0.705, 2.32, 0.17, 0.17),
            // --- VPWR: both PMOS sources + n-well tap joined by a top rail (clears Y) ---
            rect("li1", 0.02, 1.445, 0.33, 1.105),     // VDD-left up to rail
            rect("li1", 1.23, 1.445, 0.33, 1.105),     // VDD-right up to rail
            rect("li1", 0.02, 2.10, 1.54, 0.45),       // VPWR rail
            // --- output Y: L-jog from PMOS shared drain down to the NMOS top node ---
            rect("li1", 0.57, 0.045, 0.33, 1.73),      // vertical: PMOS Y down into the field
            rect("li1", 0.57, 0.045, 0.99, 0.33),      // horizontal: across to the NMOS Y
        ])
        cell.labels = [
            label("A", "poly", 0.50, 0.95),
            label("B", "poly", 1.08, 0.95),
            label("Y", "li1", 0.73, 0.20),
            label("VPWR", "li1", 0.78, 2.30),
            label("VGND", "li1", 0.18, 0.20),
        ]
        return LayoutDocument(name: name, cells: [cell], topCellID: cell.id)
    }

    /// The reference schematic the generated layout matches under LVS. Ports (A, B, Y,
    /// VPWR, VGND) match the layout's labeled-net ports by name; `n1` is the internal
    /// shared-diffusion node Netgen matches by topology.
    public func schematic(name: String = "nand2") -> String {
        """
        * generated Sky130 NAND2 reference
        .subckt \(name) A B Y VPWR VGND
        X0 Y A VPWR VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        X1 Y B VPWR VPWR sky130_fd_pr__pfet_01v8 w=0.42 l=0.16
        X2 Y B n1 VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        X3 n1 A VGND VGND sky130_fd_pr__nfet_01v8 w=0.42 l=0.16
        .ends
        """
    }
}
