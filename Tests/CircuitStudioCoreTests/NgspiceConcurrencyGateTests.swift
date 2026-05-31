import Foundation
import Testing
@testable import CircuitStudioCore

@Suite("Ngspice concurrency gate")
struct NgspiceConcurrencyGateTests {
    private enum GateTestError: Error {
        case timeout(String)
    }

    @Test("Exclusive work is scheduled FIFO behind an earlier normal waiter", .timeLimit(.minutes(1)))
    func exclusiveWorkDoesNotBypassEarlierNormalWaiter() async throws {
        let gate = NgspiceConcurrencyGate(limit: 1)
        let order = GateOrder()
        try await gate.acquire()

        let normal = Task {
            try await gate.acquire()
            await order.append("normal")
            await gate.release()
        }
        try await waitUntil("normal waiter queued") {
            await gate.snapshot().queuedNormal == 1
        }

        let exclusive = Task {
            try await gate.acquireExclusive()
            await order.append("exclusive")
            await gate.releaseExclusive()
        }
        try await waitUntil("exclusive waiter queued") {
            await gate.snapshot().queuedExclusive == 1
        }

        await gate.release()
        try await normal.value
        try await exclusive.value
        #expect(await order.snapshot() == ["normal", "exclusive"])
    }

    @Test("Cancelled exclusive waiter is removed and does not block later work", .timeLimit(.minutes(1)))
    func cancelledExclusiveWaiterDoesNotBlockQueue() async throws {
        let gate = NgspiceConcurrencyGate(limit: 1)
        try await gate.acquire()

        let exclusive = Task {
            try await gate.acquireExclusive()
            await gate.releaseExclusive()
        }
        try await waitUntil("exclusive waiter queued") {
            await gate.snapshot().queuedExclusive == 1
        }

        let normal = Task {
            try await gate.acquire()
            await gate.release()
            return "normal"
        }
        try await waitUntil("normal waiter queued") {
            await gate.snapshot().queuedNormal == 1
        }

        exclusive.cancel()
        await #expect(throws: CancellationError.self) {
            try await exclusive.value
        }
        try await waitUntil("exclusive waiter removed") {
            await gate.snapshot().queuedExclusive == 0
        }

        await gate.release()
        let result = try await normal.value
        #expect(result == "normal")
        #expect(await gate.snapshot() == .init(activeNormal: 0, exclusiveInUse: false, queuedNormal: 0, queuedExclusive: 0))
    }

    @Test("Cancelled normal waiter is removed and does not consume capacity", .timeLimit(.minutes(1)))
    func cancelledNormalWaiterDoesNotConsumeCapacity() async throws {
        let gate = NgspiceConcurrencyGate(limit: 1)
        try await gate.acquire()

        let normal = Task {
            try await gate.acquire()
            await gate.release()
        }
        try await waitUntil("normal waiter queued") {
            await gate.snapshot().queuedNormal == 1
        }

        normal.cancel()
        await #expect(throws: CancellationError.self) {
            try await normal.value
        }
        try await waitUntil("normal waiter removed") {
            await gate.snapshot().queuedNormal == 0
        }

        await gate.release()
        #expect(await gate.snapshot() == .init(activeNormal: 0, exclusiveInUse: false, queuedNormal: 0, queuedExclusive: 0))
    }

    private func waitUntil(
        _ description: String,
        _ predicate: () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw GateTestError.timeout(description)
    }
}

private actor GateOrder {
    private var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }

    func snapshot() -> [String] {
        entries
    }
}
