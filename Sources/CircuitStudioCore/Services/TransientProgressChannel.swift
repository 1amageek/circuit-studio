import Foundation
import Synchronization

/// Thread-safe FIFO channel for transient simulation data.
///
/// The simulation thread appends `(time, solution)` pairs via `append()`.
/// A separate polling thread drains accumulated data via `drain()`.
///
/// The Mutex protects only the pending buffer, which is small and
/// frequently cleared. The `drain()` method transfers ownership of the
/// arrays via `swap`, so no COW sharing occurs between the simulation
/// and polling threads.
public final class TransientProgressChannel: Sendable {
    public enum AppendError: Error, LocalizedError, Equatable, Sendable {
        case solutionWidthChanged(expected: Int, actual: Int)

        public var errorDescription: String? {
            switch self {
            case .solutionWidthChanged(let expected, let actual):
                return "Transient solution width changed from \(expected) to \(actual)."
            }
        }
    }

    private struct PendingData {
        var timePoints: [Double] = []
        var rowMajorSolutions: [Double] = []
        var sourceVariableCount: Int?
        var failure: AppendError?
    }

    private let pending: Mutex<PendingData>

    public init() {
        self.pending = Mutex(PendingData())
    }

    /// Append a single accepted timestep. Called from the simulation thread.
    public func append(time: Double, solution: [Double]) {
        pending.withLock { s in
            guard s.failure == nil else {
                return
            }
            if let sourceVariableCount = s.sourceVariableCount {
                guard sourceVariableCount == solution.count else {
                    s.failure = .solutionWidthChanged(expected: sourceVariableCount, actual: solution.count)
                    return
                }
            } else {
                s.sourceVariableCount = solution.count
            }
            s.timePoints.append(time)
            s.rowMajorSolutions.append(contentsOf: solution)
        }
    }

    /// Drain all pending data since the last drain.
    /// Returns nil if no new data has been appended.
    /// Ownership of the returned arrays is transferred to the caller via swap.
    public func drain() -> (timePoints: [Double], rowMajorSolutions: [Double], sourceVariableCount: Int)? {
        pending.withLock { s in
            guard !s.timePoints.isEmpty else { return nil }
            var tp: [Double] = []
            var sol: [Double] = []
            let sourceVariableCount = s.sourceVariableCount ?? 0
            swap(&tp, &s.timePoints)
            swap(&sol, &s.rowMajorSolutions)
            s.sourceVariableCount = nil
            return (tp, sol, sourceVariableCount)
        }
    }

    public func takeFailure() -> AppendError? {
        pending.withLock { s in
            let failure = s.failure
            s.failure = nil
            return failure
        }
    }
}
