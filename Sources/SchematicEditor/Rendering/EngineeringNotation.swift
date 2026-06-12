import Foundation

/// Formats numeric values in engineering notation with SI prefixes
/// (4.7k, 100n, 2.2µ) — the standard way component values appear on
/// professional schematics.
public enum EngineeringNotation {
    private static let prefixes: [(exponent: Int, symbol: String)] = [
        (12, "T"), (9, "G"), (6, "M"), (3, "k"),
        (0, ""),
        (-3, "m"), (-6, "\u{00B5}"), (-9, "n"), (-12, "p"), (-15, "f"),
    ]

    /// Formats a value with an SI prefix and unit suffix, e.g.
    /// `format(4700, unit: "Ω")` → `"4.7kΩ"`.
    public static func format(_ value: Double, unit: String = "") -> String {
        guard value.isFinite else { return "\(value)\(unit)" }
        guard value != 0 else { return "0\(unit)" }

        let magnitude = abs(value)
        for (exponent, symbol) in prefixes {
            let scale = pow(10.0, Double(exponent))
            if magnitude >= scale {
                return mantissaText(value / scale) + symbol + unit
            }
        }
        // Below all prefixes (< 1e-15): plain scientific notation.
        return String(format: "%g", value) + unit
    }

    /// Up to four significant digits with trailing zeros trimmed.
    private static func mantissaText(_ scaled: Double) -> String {
        String(format: "%.4g", scaled)
    }
}
