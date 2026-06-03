public enum CircuitStudioBenchmarkSuite {
    public static func run() async throws -> BenchmarkSuiteReport {
        let comparisons = [
            try WaveformPipelineBenchmarkOperations.transientBuilderComparison(),
            try WaveformPipelineBenchmarkOperations.waveformServiceDecimationComparison(),
            try WaveformPipelineBenchmarkOperations.postLayoutComparisonComparison(),
        ]
        let measurements = [
            try WaveformPipelineBenchmarkOperations.ngspiceParseMeasurement(),
            try await WaveformPipelineBenchmarkOperations.chartSeriesMeasurement(),
        ]
        return BenchmarkSuiteReport(comparisons: comparisons, measurements: measurements)
    }
}
