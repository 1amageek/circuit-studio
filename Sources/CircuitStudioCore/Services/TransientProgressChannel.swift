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

    private struct PendingData {
        var timePoints: [Double] = []
        var solutions: [[Double]] = []
    }

    private let pending: Mutex<PendingData>

    public init() {
        self.pending = Mutex(PendingData())
    }

    /// Append a single accepted timestep. Called from the simulation thread.
    public func append(time: Double, solution: [Double]) {
        pending.withLock { s in
            s.timePoints.append(time)
            s.solutions.append(solution)
        }
    }

    /// Drain all pending data since the last drain.
    /// Returns nil if no new data has been appended.
    /// Ownership of the returned arrays is transferred to the caller via swap.
    public func drain() -> (timePoints: [Double], solutions: [[Double]])? {
        pending.withLock { s in
            guard !s.timePoints.isEmpty else { return nil }
            var tp: [Double] = []
            var sol: [[Double]] = []
            swap(&tp, &s.timePoints)
            swap(&sol, &s.solutions)
            return (tp, sol)
        }
    }
}
