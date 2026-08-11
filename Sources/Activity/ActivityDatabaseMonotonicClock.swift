import Database

struct ActivityDatabaseMonotonicClock: StorageMonotonicClock {
    private let clock: ContinuousClock
    private let origin: ContinuousClock.Instant

    init() {
        let clock = ContinuousClock()
        self.clock = clock
        self.origin = clock.now
    }

    var now: StorageInstant {
        StorageInstant(durationSinceReference: origin.duration(to: clock.now))
    }

    func sleep(
        until deadline: StorageInstant
    ) async throws(StorageClockError) {
        let delay = now.duration(to: deadline)
        guard delay > .zero else { return }
        do {
            try await clock.sleep(for: delay)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unavailable
        }
    }
}
