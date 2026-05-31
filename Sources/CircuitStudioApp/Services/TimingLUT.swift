import Foundation

/// A non-linear delay model (NLDM) lookup table: one metric — a cell-delay or an
/// output-transition (slew) — sampled on a grid of input transition (rows) × output load
/// capacitance (columns), the standard Liberty table form. Values are bilinearly
/// interpolated; queries past the sampled edges are linearly EXTRAPOLATED from the two
/// nearest samples (not clamped), so a path whose slew/load lands outside the
/// characterization grid still gets a defined, monotone estimate rather than a silent flat
/// value. A one-sample axis collapses to a constant along that dimension.
public struct TimingLUT: Sendable, Hashable, Codable {

    public enum LUTError: Error, LocalizedError, Equatable {
        case empty
        case shapeMismatch(rows: Int, cols: Int)
        case axisNotAscending(String)

        public var errorDescription: String? {
            switch self {
            case .empty: return "A timing LUT needs at least one sample on each axis."
            case .shapeMismatch(let r, let c): return "LUT values must be \(r)x\(c) to match its axes."
            case .axisNotAscending(let a): return "LUT \(a) axis must be strictly ascending."
            }
        }
    }

    public let inputSlews: [Double]     // seconds, ascending
    public let outputLoads: [Double]    // farads, ascending
    public let values: [[Double]]       // values[i][j] at (inputSlews[i], outputLoads[j])

    public init(inputSlews: [Double], outputLoads: [Double], values: [[Double]]) throws {
        guard !inputSlews.isEmpty, !outputLoads.isEmpty else { throw LUTError.empty }
        guard values.count == inputSlews.count, values.allSatisfy({ $0.count == outputLoads.count }) else {
            throw LUTError.shapeMismatch(rows: inputSlews.count, cols: outputLoads.count)
        }
        guard Self.isAscending(inputSlews) else { throw LUTError.axisNotAscending("input-slew") }
        guard Self.isAscending(outputLoads) else { throw LUTError.axisNotAscending("output-load") }
        self.inputSlews = inputSlews
        self.outputLoads = outputLoads
        self.values = values
    }

    /// A degenerate constant table (one sample) — a placeholder before characterization.
    /// A single sample on each axis statically satisfies every invariant, so this builds
    /// directly without the throwing path.
    public static func constant(_ value: Double) -> TimingLUT {
        TimingLUT(constant: value)
    }

    private init(constant value: Double) {
        self.inputSlews = [0]
        self.outputLoads = [0]
        self.values = [[value]]
    }

    /// Bilinearly interpolate (linear extrapolation past the edges) at the query point.
    public func lookup(inputSlew: Double, outputLoad: Double) -> Double {
        let row = Self.bracket(inputSlews, inputSlew)
        let lo = Self.interpolate(outputLoads, values[row.lo], at: outputLoad)
        if row.lo == row.hi { return lo }
        let hi = Self.interpolate(outputLoads, values[row.hi], at: outputLoad)
        return lo + (hi - lo) * row.frac
    }

    // MARK: - interpolation helpers

    private static func isAscending(_ xs: [Double]) -> Bool {
        guard xs.count > 1 else { return true }
        return zip(xs, xs.dropFirst()).allSatisfy { $0 < $1 }
    }

    /// Bracketing indices + interpolation fraction for `x` on ascending axis `xs`. For a
    /// single-element axis, lo == hi. Past the ends, the fraction extrapolates (<0 or >1).
    private static func bracket(_ xs: [Double], _ x: Double) -> (lo: Int, hi: Int, frac: Double) {
        if xs.count == 1 { return (0, 0, 0) }
        if x <= xs[0] {
            let span = xs[1] - xs[0]
            return (0, 1, span == 0 ? 0 : (x - xs[0]) / span)
        }
        if x >= xs[xs.count - 1] {
            let n = xs.count
            let span = xs[n - 1] - xs[n - 2]
            return (n - 2, n - 1, span == 0 ? 1 : (x - xs[n - 2]) / span)
        }
        var hi = 1
        while xs[hi] < x { hi += 1 }
        let span = xs[hi] - xs[hi - 1]
        return (hi - 1, hi, span == 0 ? 0 : (x - xs[hi - 1]) / span)
    }

    /// 1-D interpolation of `ys` over ascending axis `xs` at `x`, with edge extrapolation.
    private static func interpolate(_ xs: [Double], _ ys: [Double], at x: Double) -> Double {
        let b = bracket(xs, x)
        if b.lo == b.hi { return ys[b.lo] }
        return ys[b.lo] + (ys[b.hi] - ys[b.lo]) * b.frac
    }
}
