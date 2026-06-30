import Foundation

/// Closes the agent edit → signoff → iterate loop (roadmap G4) using REAL signoff.
///
/// The agent proposes a design candidate each iteration (typically by editing the
/// previous one in response to the last failing review); the loop runs real DRC +
/// LVS on it and converges the moment a candidate passes. The agent's edit logic
/// is injected as `nextCandidate`, so this type owns only the apply→verify→iterate
/// machinery and the convergence criterion (`ExternalSignoffReview.passed`).
public struct SignoffIterationLoop: Sendable {
    public typealias SignoffExecution = @Sendable (
        _ layoutGDS: URL,
        _ topCell: String,
        _ schematicNetlist: URL,
        _ artifactDirectory: URL
    ) async throws -> ExternalSignoffReview

    /// One design proposal to verify.
    public struct Candidate: Sendable, Hashable {
        public let layoutGDS: URL
        public let topCell: String
        public let schematicNetlist: URL
        public init(layoutGDS: URL, topCell: String, schematicNetlist: URL) {
            self.layoutGDS = layoutGDS
            self.topCell = topCell
            self.schematicNetlist = schematicNetlist
        }
    }

    public struct IterationOutcome: Sendable {
        public let index: Int
        public let candidate: Candidate
        public let review: ExternalSignoffReview
        public var passed: Bool { review.passed }
    }

    public struct LoopResult: Sendable {
        /// True when an iteration produced a passing review within the budget.
        public let converged: Bool
        public let iterations: [IterationOutcome]
    }

    public enum LoopError: Error, LocalizedError, Equatable {
        case nonPositiveIterationBudget

        public var errorDescription: String? {
            switch self {
            case .nonPositiveIterationBudget:
                return "The signoff iteration loop requires maxIterations >= 1."
            }
        }
    }

    private let runSignoff: SignoffExecution

    public init(signoff: LiveSignoffService) {
        self.runSignoff = { layoutGDS, topCell, schematicNetlist, artifactDirectory in
            try await signoff.run(
                layoutGDS: layoutGDS,
                topCell: topCell,
                schematicNetlist: schematicNetlist,
                artifactDirectory: artifactDirectory
            )
        }
    }

    public init(runSignoff: @escaping SignoffExecution) {
        self.runSignoff = runSignoff
    }

    /// Available only when the real signoff toolchain is installed.
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> SignoffIterationLoop? {
        LiveSignoffService.locate(environment: environment, fileManager: fileManager)
            .map(SignoffIterationLoop.init(signoff:))
    }

    /// Runs the loop until a candidate passes signoff or the budget/candidates are
    /// exhausted. `nextCandidate(index, lastReview)` is the agent's edit decision;
    /// returning nil stops the loop. Each iteration runs REAL DRC+LVS.
    public func run(
        maxIterations: Int,
        artifactDirectory: URL,
        nextCandidate: (_ index: Int, _ lastReview: ExternalSignoffReview?) async throws -> Candidate?
    ) async throws -> LoopResult {
        guard maxIterations >= 1 else { throw LoopError.nonPositiveIterationBudget }
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)

        var outcomes: [IterationOutcome] = []
        var lastReview: ExternalSignoffReview?

        for index in 0..<maxIterations {
            guard let candidate = try await nextCandidate(index, lastReview) else { break }
            let review = try await runSignoff(
                candidate.layoutGDS,
                candidate.topCell,
                candidate.schematicNetlist,
                artifactDirectory.appending(path: "iter-\(index)")
            )
            outcomes.append(IterationOutcome(index: index, candidate: candidate, review: review))
            if review.passed {
                return LoopResult(converged: true, iterations: outcomes)
            }
            lastReview = review
        }
        return LoopResult(converged: false, iterations: outcomes)
    }
}
