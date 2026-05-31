import Foundation

/// A process-wide limit on how many ngspice subprocesses run at once. ngspice is CPU-bound,
/// so spawning one per concurrent caller thrashes the machine — each run then takes far
/// longer than it would alone (observed: a 3 s cross-check ballooning past a 120 s test
/// limit under full parallelism). This actor caps concurrency to a small fraction of the
/// cores; callers `acquire()` a slot before launching ngspice and `release()` it after.
public actor NgspiceConcurrencyGate {

    public static let shared = NgspiceConcurrencyGate(
        limit: max(2, ProcessInfo.processInfo.activeProcessorCount / 4))

    private let limit: Int
    private var inUse = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int) { self.limit = max(1, limit) }

    /// Wait until a slot is free, then take it.
    public func acquire() async {
        if inUse < limit {
            inUse += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Return a slot, handing it directly to the next waiter if any (so `inUse` stays at the
    /// cap while work is queued, and never exceeds it).
    public func release() {
        if waiters.isEmpty {
            inUse = max(0, inUse - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}
