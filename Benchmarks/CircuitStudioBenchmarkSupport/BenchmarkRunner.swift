public enum BenchmarkRunner {
    public static func measure(
        _ name: String,
        warmupIterations: Int = 2,
        samples: Int = 7,
        iterationsPerSample: Int,
        operation: () throws -> Double
    ) throws -> BenchmarkResult {
        precondition(samples > 0, "samples must be positive")
        precondition(iterationsPerSample > 0, "iterationsPerSample must be positive")

        var checksum = 0.0
        for _ in 0..<warmupIterations {
            checksum += try operation()
        }

        let clock = ContinuousClock()
        var sampleSeconds: [Double] = []
        sampleSeconds.reserveCapacity(samples)
        for _ in 0..<samples {
            let start = clock.now
            for _ in 0..<iterationsPerSample {
                checksum += try operation()
            }
            let duration = start.duration(to: clock.now)
            sampleSeconds.append(seconds(from: duration))
        }

        return try validatedResult(
            BenchmarkResult(
                name: name,
                iterationsPerSample: iterationsPerSample,
                sampleSeconds: sampleSeconds,
                checksum: checksum
            )
        )
    }

    public static func measureAsync(
        _ name: String,
        warmupIterations: Int = 2,
        samples: Int = 7,
        iterationsPerSample: Int,
        operation: () async throws -> Double
    ) async throws -> BenchmarkResult {
        precondition(samples > 0, "samples must be positive")
        precondition(iterationsPerSample > 0, "iterationsPerSample must be positive")

        var checksum = 0.0
        for _ in 0..<warmupIterations {
            checksum += try await operation()
        }

        let clock = ContinuousClock()
        var sampleSeconds: [Double] = []
        sampleSeconds.reserveCapacity(samples)
        for _ in 0..<samples {
            let start = clock.now
            for _ in 0..<iterationsPerSample {
                checksum += try await operation()
            }
            let duration = start.duration(to: clock.now)
            sampleSeconds.append(seconds(from: duration))
        }

        return try validatedResult(
            BenchmarkResult(
                name: name,
                iterationsPerSample: iterationsPerSample,
                sampleSeconds: sampleSeconds,
                checksum: checksum
            )
        )
    }

    private static func validatedResult(_ result: BenchmarkResult) throws -> BenchmarkResult {
        print(result.description)
        guard result.checksum.isFinite else {
            throw BenchmarkError.nonFiniteChecksum(result.name)
        }
        guard result.medianSecondsPerIteration > 0.0 else {
            throw BenchmarkError.nonPositiveDuration(result.name)
        }
        return result
    }

    private static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000.0
    }
}
