import Foundation

/// The per-layer metal-density result for a layout: each checked layer's measured area
/// coverage against its density window. A failing layer is too sparse (CMP will dish the
/// dielectric) or too dense (CMP pulls the metal thin) — either way the fabricated geometry
/// drifts from drawn. The coverage is measured by Magic on the real GDS; the window is the
/// harness/PDK policy, so the measurement and the verdict have one source each.
public struct DensityReport: Sendable, Hashable, Codable {

    public struct LayerCoverage: Sendable, Hashable, Codable {
        public let layer: String          // CIF output layer name (e.g. MET1)
        public let coverage: Double        // measured fraction 0...1 (layer area / cell area)
        public let minDensity: Double      // window floor (inclusive)
        public let maxDensity: Double      // window ceiling (inclusive)

        public init(layer: String, coverage: Double, minDensity: Double, maxDensity: Double) {
            self.layer = layer
            self.coverage = coverage
            self.minDensity = minDensity
            self.maxDensity = maxDensity
        }

        public var passed: Bool { coverage >= minDensity && coverage <= maxDensity }

        public var status: String {
            if coverage < minDensity {
                return String(format: "%@ %.1f%% below %.0f%% floor", layer, coverage * 100, minDensity * 100)
            }
            if coverage > maxDensity {
                return String(format: "%@ %.1f%% above %.0f%% ceiling", layer, coverage * 100, maxDensity * 100)
            }
            return String(format: "%@ %.1f%% within [%.0f%%, %.0f%%]", layer, coverage * 100, minDensity * 100, maxDensity * 100)
        }
    }

    public let cell: String
    public let layers: [LayerCoverage]
    /// Positive proof the driver ran to a clean completion (`DENSITY_DONE` present). A pass
    /// requires this, so a truncated/aborted run can never be a silent clean density.
    public let completed: Bool
    public let logPath: String

    public init(cell: String, layers: [LayerCoverage], completed: Bool, logPath: String) {
        self.cell = cell
        self.layers = layers
        self.completed = completed
        self.logPath = logPath
    }

    public var passed: Bool { completed && !layers.isEmpty && layers.allSatisfy(\.passed) }
    public var failing: [LayerCoverage] { layers.filter { !$0.passed } }
    public var summary: String {
        passed
            ? "density within window on \(layers.count) layer(s)"
            : failing.map(\.status).joined(separator: "; ")
    }
}
