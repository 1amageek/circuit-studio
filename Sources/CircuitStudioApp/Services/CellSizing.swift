import Foundation

/// The drive-strength ladder for timing closure: each base cell ("inv", "nand2", "nor2")
/// has sized variants ("inv_x2", "inv_x4", …) whose transistor widths are scaled up. The
/// sizing loop upsizes a critical-path cell by swapping it for the next rung, trading input
/// capacitance for lower drive resistance. Naming is the library key: a variant's timing is
/// characterized at its absolute geometry, so the netlist and the library stay consistent.
public enum CellSizing {

    /// Absolute width multipliers (relative to the base cell), in ascending drive strength.
    public static let factors: [Double] = [1.0, 2.0, 4.0]

    private static func suffix(for factor: Double) -> String { factor == 1.0 ? "" : "_x\(Int(factor))" }

    /// The variant name for a base cell at a drive factor (e.g. ("inv", 2) -> "inv_x2").
    public static func name(base: String, factor: Double) -> String { base + suffix(for: factor) }

    /// All sized variants of a base cell, ascending (base first).
    public static func variants(of base: CMOSGateNetlist) -> [CMOSGateNetlist] {
        factors.map { factor in
            factor == 1.0 ? base : base.scaled(widthFactor: factor, name: name(base: base.name, factor: factor))
        }
    }

    /// The base cell name with any drive suffix stripped ("nand2_x4" -> "nand2").
    public static func baseName(of cellName: String) -> String {
        guard let range = cellName.range(of: "_x") else { return cellName }
        return String(cellName[..<range.lowerBound])
    }

    /// The absolute drive factor encoded in a cell name (default 1.0 for the base).
    public static func factor(of cellName: String) -> Double {
        guard let range = cellName.range(of: "_x"),
              let value = Double(cellName[range.upperBound...]) else { return 1.0 }
        return value
    }

    /// The next rung up for a cell, or nil if already at the strongest. Returns the new name
    /// and the relative width multiplier to apply to the CURRENT cell to reach it.
    public static func nextLarger(of cellName: String) -> (name: String, relativeFactor: Double)? {
        let current = factor(of: cellName)
        guard let index = factors.firstIndex(of: current), index + 1 < factors.count else { return nil }
        let next = factors[index + 1]
        return (name(base: baseName(of: cellName), factor: next), next / current)
    }
}
