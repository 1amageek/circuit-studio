import Foundation

/// One axis of signoff and its evidence. A verdict is only as trustworthy as the artifact
/// that backs it, so every axis carries a machine-readable pointer to the measurement or
/// tool output it rests on — the seed of the tapeout evidence bundle (BC4).
public struct ConstraintVerdict: Sendable, Hashable, Codable {

    public enum Axis: String, Sendable, Hashable, Codable {
        case functional   // golden-trace execution match
        case timing       // STA setup/hold closure
        case drc          // Magic design-rule check
        case lvs          // Netgen layout-vs-schematic
    }

    public let axis: Axis
    public let passed: Bool
    public let summary: String     // one-line human summary
    public let evidence: String    // pointer to the backing artifact / measured value

    public init(axis: Axis, passed: Bool, summary: String, evidence: String) {
        self.axis = axis
        self.passed = passed
        self.summary = summary
        self.evidence = evidence
    }
}

/// Folds the per-axis verdicts (functional, timing, physical) into ONE signoff verdict: the
/// design passes only when EVERY axis passes — a single failing axis fails the whole, never
/// a silent partial pass. This is the unified gate the spec-to-silicon loop drives toward;
/// BC1 wires functional + timing, and DRC/LVS join as they become available.
public struct MultiConstraintSignoff: Sendable {

    public enum SignoffError: Error, LocalizedError, Equatable {
        case noVerdicts
        case missingRequiredAxis(ConstraintVerdict.Axis)

        public var errorDescription: String? {
            switch self {
            case .noVerdicts: return "Multi-constraint signoff needs at least one axis verdict."
            case .missingRequiredAxis(let a): return "Signoff is missing the required \(a.rawValue) axis."
            }
        }
    }

    public struct Verdict: Sendable, Hashable, Codable {
        public let verdicts: [ConstraintVerdict]
        public var passed: Bool { !verdicts.isEmpty && verdicts.allSatisfy(\.passed) }
        public var failing: [ConstraintVerdict] { verdicts.filter { !$0.passed } }
        public func axis(_ a: ConstraintVerdict.Axis) -> ConstraintVerdict? { verdicts.first { $0.axis == a } }
    }

    private let requiredAxes: [ConstraintVerdict.Axis]

    /// `requiredAxes` must all be present (else the signoff throws) — so an axis cannot be
    /// silently dropped to make the design "pass". Physical axes are required only when the
    /// toolchain is available; the caller decides.
    public init(requiredAxes: [ConstraintVerdict.Axis] = [.functional, .timing]) {
        self.requiredAxes = requiredAxes
    }

    public func combine(_ verdicts: [ConstraintVerdict]) throws -> Verdict {
        guard !verdicts.isEmpty else { throw SignoffError.noVerdicts }
        let present = Set(verdicts.map(\.axis))
        for axis in requiredAxes where !present.contains(axis) {
            throw SignoffError.missingRequiredAxis(axis)
        }
        return Verdict(verdicts: verdicts)
    }

    // MARK: - axis verdict builders

    public static func functional(passed: Bool, cycles: Int, evidence: String) -> ConstraintVerdict {
        ConstraintVerdict(axis: .functional, passed: passed,
                          summary: passed ? "golden trace matched over \(cycles) cycles" : "golden trace diverged",
                          evidence: evidence)
    }

    public static func timing(_ report: TimingReport, evidence: String) -> ConstraintVerdict {
        let fmaxMHz = report.fmaxHz / 1e6
        return ConstraintVerdict(
            axis: .timing, passed: report.met,
            summary: String(format: "setup %@ (slack %.1f ps, fmax %.0f MHz)",
                            report.met ? "met" : "VIOLATED", report.worstSetupSlack * 1e12, fmaxMHz),
            evidence: evidence)
    }

    public static func drc(passed: Bool, violationCount: Int, evidence: String) -> ConstraintVerdict {
        ConstraintVerdict(axis: .drc, passed: passed,
                          summary: passed ? "DRC clean" : "\(violationCount) DRC violations", evidence: evidence)
    }

    public static func lvs(passed: Bool, evidence: String) -> ConstraintVerdict {
        ConstraintVerdict(axis: .lvs, passed: passed,
                          summary: passed ? "LVS matched" : "LVS mismatch", evidence: evidence)
    }
}
