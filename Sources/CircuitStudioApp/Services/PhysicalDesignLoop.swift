import Foundation
import LayoutCore

/// Closes the PHYSICAL design loop the way `SpecDrivenDesignLoop` closes the electrical
/// one: it drives a layout parameter to DRC-clean, failure-driven from the named
/// violations — not a fixed script. Each iteration builds the geometry at the current
/// parameter, runs real DRC, and routes the report through `SignoffEvaluationService`
/// (the Explain stage); when the only blocking findings are ones the tunable addresses,
/// it grows the parameter (the Decide+Edit) and re-checks.
///
/// It never gives up silently: a violation the tunable cannot address, or hitting the
/// parameter bound while still failing, is thrown — the caller must see it. This is the
/// Explain → Decide → Edit half of the loop, on the physical axis.
public struct PhysicalDesignLoop: Sendable {

    /// The geometry parameter the controller grows to clear a class of violation, and
    /// which classified failure / layer it addresses.
    public struct Tunable: Sendable, Hashable {
        public let parameter: String      // human-readable parameter label
        public let fixesReason: String    // classified reason it clears
        public let onLayer: String        // the rule id must mention this logical layer
        public let stepFactor: Double     // > 1; the parameter grows to fix
        public let minValue: Double
        public let maxValue: Double

        public init(
            parameter: String, fixesReason: String, onLayer: String,
            stepFactor: Double, minValue: Double, maxValue: Double
        ) {
            self.parameter = parameter
            self.fixesReason = fixesReason
            self.onLayer = onLayer
            self.stepFactor = stepFactor
            self.minValue = minValue
            self.maxValue = maxValue
        }
    }

    public struct Iteration: Sendable {
        public let index: Int
        public let parameterValue: Double
        public let passed: Bool
        public let blockingRules: [String]
    }

    public struct Outcome: Sendable {
        public let converged: Bool
        public let iterations: [Iteration]
        public let finalParameter: Double
        public let finalReport: ExternalSignoffToolReport
    }

    public enum LoopError: Error, LocalizedError, Equatable {
        case nonPositiveBudget
        case unfixableViolations([String])
        case boundReached(parameter: Double, rules: [String])
        case missingFinalReport

        public var errorDescription: String? {
            switch self {
            case .nonPositiveBudget:
                return "The physical loop requires maxIterations >= 1."
            case .unfixableViolations(let rules):
                return "The tunable cannot address these violations: \(rules.joined(separator: ", "))."
            case .boundReached(let value, let rules):
                return "Parameter reached its bound (\(value)) but still violates: \(rules.joined(separator: ", "))."
            case .missingFinalReport:
                return "The physical loop exhausted its budget without retaining a final signoff report."
            }
        }
    }

    private let drc: LayoutDRCChecking
    private let evaluator: SignoffEvaluationService

    public init(drc: LayoutDRCChecking, evaluator: SignoffEvaluationService = SignoffEvaluationService()) {
        self.drc = drc
        self.evaluator = evaluator
    }

    /// Drive `build(parameter)` to DRC-clean. Returns once clean; throws on a violation
    /// the tunable cannot address or on hitting the bound while still failing.
    public func run(
        initial: Double,
        tunable: Tunable,
        cellName: String,
        into directory: URL,
        maxIterations: Int,
        build: @Sendable (Double) -> LayoutDocument
    ) async throws -> Outcome {
        guard maxIterations >= 1 else { throw LoopError.nonPositiveBudget }

        var value = initial
        var iterations: [Iteration] = []
        var lastReport: ExternalSignoffToolReport?

        for index in 0..<maxIterations {
            let cellDir = directory.appending(path: "iter-\(index)")
            let report = try await drc.check(build(value), cell: cellName, in: cellDir)
            lastReport = report
            let evaluation = evaluator.evaluate(ExternalSignoffReview(reports: [report]))
            let blocking = evaluation.blockingFindings
            iterations.append(Iteration(
                index: index, parameterValue: value, passed: report.passed,
                blockingRules: blocking.compactMap { $0.ruleID }
            ))
            if report.passed {
                return Outcome(converged: true, iterations: iterations, finalParameter: value, finalReport: report)
            }

            // Decide from the Explain stage: every blocking finding must be one this
            // tunable addresses, otherwise we cannot honestly claim to fix it.
            let unfixable = blocking.filter { !addresses($0, with: tunable) }
            guard unfixable.isEmpty else {
                throw LoopError.unfixableViolations(unfixable.compactMap { $0.ruleID })
            }

            // Edit: grow the parameter toward clearing the violation.
            let next = min(tunable.maxValue, max(tunable.minValue, value * tunable.stepFactor))
            guard next != value else {
                throw LoopError.boundReached(parameter: value, rules: blocking.compactMap { $0.ruleID })
            }
            value = next
        }

        // Budget exhausted while still failing — report it honestly (the last report is
        // non-nil because maxIterations >= 1 guarantees at least one check ran).
        guard let finalReport = lastReport else {
            throw LoopError.missingFinalReport
        }
        return Outcome(
            converged: false,
            iterations: iterations,
            finalParameter: iterations.last?.parameterValue ?? value,
            finalReport: finalReport
        )
    }

    private func addresses(_ finding: SignoffEvaluationService.Finding, with tunable: Tunable) -> Bool {
        finding.reason == tunable.fixesReason
            && (finding.ruleID ?? "").lowercased().contains(tunable.onLayer.lowercased())
    }
}
