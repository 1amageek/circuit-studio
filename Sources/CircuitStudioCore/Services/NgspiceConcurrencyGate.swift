import Foundation

/// A process-wide scheduler for CPU-bound SPICE oracle work. Normal slots cap concurrent
/// ngspice subprocesses; exclusive slots let heavy in-process CoreSpice characterization
/// run without competing with ngspice. The queue is FIFO and cancellation-aware, so timed-out
/// tests do not leave dead continuations that later consume capacity.
public actor NgspiceConcurrencyGate {

    public static let shared = NgspiceConcurrencyGate(
        limit: max(2, ProcessInfo.processInfo.activeProcessorCount / 4))

    enum Mode: Sendable, Equatable {
        case normal
        case exclusive
    }

    struct Snapshot: Sendable, Equatable {
        let activeNormal: Int
        let exclusiveInUse: Bool
        let queuedNormal: Int
        let queuedExclusive: Int
    }

    private struct Waiter {
        let id: Int
        let mode: Mode
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let limit: Int
    private var activeNormal = 0
    private var exclusiveInUse = false
    private var nextWaiterID = 0
    private var waiters: [Waiter] = []

    public init(limit: Int) { self.limit = max(1, limit) }

    /// Wait until a slot is free, then take it.
    public func acquire() async throws {
        try await acquire(mode: .normal)
    }

    /// Return a slot, handing it directly to the next waiter if any (so `inUse` stays at the
    /// cap while work is queued, and never exceeds it).
    public func release() {
        activeNormal = max(0, activeNormal - 1)
        resumeWaiters()
    }

    /// Wait until no ngspice subprocess is active, then block normal slots. Heavy in-process
    /// CoreSpice characterization tests use this so they do not compete with ngspice tests
    /// for CPU and push otherwise-fast oracle checks past their time limits.
    public func acquireExclusive() async throws {
        try await acquire(mode: .exclusive)
    }

    /// Release an exclusive slot and resume queued work fairly.
    public func releaseExclusive() {
        exclusiveInUse = false
        resumeWaiters()
    }

    func snapshot() -> Snapshot {
        Snapshot(
            activeNormal: activeNormal,
            exclusiveInUse: exclusiveInUse,
            queuedNormal: waiters.filter { $0.mode == .normal }.count,
            queuedExclusive: waiters.filter { $0.mode == .exclusive }.count
        )
    }

    private func acquire(mode: Mode) async throws {
        try Task.checkCancellation()
        if waiters.isEmpty, canGrant(mode) {
            grant(mode)
            try releaseGrantIfCancelled(mode)
            return
        }

        let id = nextWaiterID
        nextWaiterID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters.append(Waiter(id: id, mode: mode, continuation: continuation))
                resumeWaiters()
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
        try releaseGrantIfCancelled(mode)
    }

    private func canGrant(_ mode: Mode) -> Bool {
        guard !exclusiveInUse else { return false }
        switch mode {
        case .normal:
            return activeNormal < limit
        case .exclusive:
            return activeNormal == 0
        }
    }

    private func grant(_ mode: Mode) {
        switch mode {
        case .normal:
            activeNormal += 1
        case .exclusive:
            exclusiveInUse = true
        }
    }

    private func releaseGrantIfCancelled(_ mode: Mode) throws {
        guard Task.isCancelled else { return }
        switch mode {
        case .normal:
            activeNormal = max(0, activeNormal - 1)
        case .exclusive:
            exclusiveInUse = false
        }
        resumeWaiters()
        throw CancellationError()
    }

    private func cancelWaiter(id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
        resumeWaiters()
    }

    private func resumeWaiters() {
        guard !exclusiveInUse else { return }

        while let next = waiters.first, canGrant(next.mode) {
            waiters.removeFirst()
            grant(next.mode)
            next.continuation.resume()
            if next.mode == .exclusive { return }
        }
    }
}
