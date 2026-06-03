import CircuitStudioBenchmarkSupport

@main
enum CircuitStudioBenchmarks {
    static func main() async throws {
        let enforcePerformanceThresholds = CommandLine.arguments.dropFirst().contains("--enforce")
        let report = try await CircuitStudioBenchmarkSuite.run()
        print("")
        for comparison in report.comparisons {
            print(comparison.summary)
        }

        if !report.measurements.isEmpty {
            print("")
            print("Measurement-only benchmarks are reported above and are not threshold-enforced.")
        }

        if !enforcePerformanceThresholds, !report.passed {
            print("")
            print("Performance thresholds were not enforced. Re-run with --enforce to return a non-zero status for threshold failures.")
        }

        guard !enforcePerformanceThresholds || report.passed else {
            throw BenchmarkFailure(messages: report.failureMessages)
        }
    }
}

struct BenchmarkFailure: Error, CustomStringConvertible {
    let messages: [String]

    var description: String {
        messages.joined(separator: "\n")
    }
}
