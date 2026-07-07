import Foundation
import SwiftUI
import CircuitStudioCore
import CoreSpice
import CoreSpiceWaveform
import WaveformViewer

public enum WaveformPipelineBenchmarkOperations {
    public static func transientBuilderComparison() throws -> BenchmarkComparison {
        let pointCount = 12_000
        let variableCount = 12
        let timePoints = (0..<pointCount).map { Double($0) * 1.0e-9 }
        let solutions = WaveformBenchmarkFixture.rowMajorSolutions(
            pointCount: pointCount,
            variableCount: variableCount
        )
        let variableMap = WaveformBenchmarkFixture.transientVariableMap(variableCount: variableCount)
        let nodeNamesByID = WaveformBenchmarkFixture.nodeNamesByID(variableCount: variableCount)

        let currentReference = sum(
            buildTransientWaveform(
                timePoints: timePoints,
                rowMajorSolutions: solutions,
                sourceVariableCount: variableCount,
                variableMap: variableMap,
                nodeNamesByID: nodeNamesByID
            )
        )
        let baselineReference = sum(
            legacyTransientWaveform(
                timePoints: timePoints,
                rowMajorSolutions: solutions,
                sourceVariableCount: variableCount
            )
        )
        try assertClose(
            "circuit.transientBuilder",
            currentReference,
            baselineReference
        )

        let measured = try BenchmarkRunner.measure(
            "circuit.transientBuilderRowMajor",
            iterationsPerSample: 4
        ) {
            sum(
                buildTransientWaveform(
                    timePoints: timePoints,
                    rowMajorSolutions: solutions,
                    sourceVariableCount: variableCount,
                    variableMap: variableMap,
                    nodeNamesByID: nodeNamesByID
                )
            )
        }

        let baseline = try BenchmarkRunner.measure(
            "circuit.transientBuilderNestedBaseline",
            iterationsPerSample: 3
        ) {
            sum(
                legacyTransientWaveform(
                    timePoints: timePoints,
                    rowMajorSolutions: solutions,
                    sourceVariableCount: variableCount
                )
            )
        }

        return BenchmarkComparison(
            name: "transient builder row-major ingestion",
            measured: measured,
            baseline: baseline,
            maximumRatio: 0.75,
            requirement: "Streaming transient ingestion should avoid per-point nested row allocation."
        )
    }

    public static func waveformServiceDecimationComparison() throws -> BenchmarkComparison {
        let waveform = WaveformBenchmarkFixture.waveform()
        let service = WaveformService()
        let range = waveform.sweepValues[1_000]...waveform.sweepValues[11_000]

        let measuredReference = sum(
            service.fetch(
                waveform: waveform,
                variables: [],
                range: range,
                maxPoints: 2_000
            )
        )
        let baselineReference = sum(
            legacyFetch(
                waveform: waveform,
                range: range,
                maxPoints: 2_000
            )
        )
        try assertClose(
            "circuit.waveformServiceDecimation",
            measuredReference,
            baselineReference
        )

        let measured = try BenchmarkRunner.measure(
            "circuit.waveformServiceRowMajorDecimation",
            iterationsPerSample: 20
        ) {
            sum(
                service.fetch(
                    waveform: waveform,
                    variables: [],
                    range: range,
                    maxPoints: 2_000
                )
            )
        }

        let baseline = try BenchmarkRunner.measure(
            "circuit.waveformServiceLegacyDecimation",
            iterationsPerSample: 12
        ) {
            sum(
                legacyFetch(
                    waveform: waveform,
                    range: range,
                    maxPoints: 2_000
                )
            )
        }

        return BenchmarkComparison(
            name: "waveform service row-major decimation",
            measured: measured,
            baseline: baseline,
            maximumRatio: 0.85,
            requirement: "Display decimation should use binary range search and row-major row copies."
        )
    }

    public static func postLayoutComparisonComparison() throws -> BenchmarkComparison {
        let service = PostLayoutComparisonService()
        let preRowMajor = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: WaveformBenchmarkFixture.waveform()
        )
        let postRowMajor = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: WaveformBenchmarkFixture.waveform(offset: 1.0e-6)
        )
        let preNested = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: WaveformBenchmarkFixture.nestedWaveform()
        )
        let postNested = SimulationResult(
            experimentID: UUID(),
            status: .completed,
            waveform: WaveformBenchmarkFixture.nestedWaveform(offset: 1.0e-6)
        )

        let measuredReference = try compareChecksum(
            service.compare(preLayoutResult: preRowMajor, postLayoutResult: postRowMajor)
        )
        let baselineReference = try compareChecksum(
            service.compare(preLayoutResult: preNested, postLayoutResult: postNested)
        )
        try assertClose(
            "circuit.postLayoutComparison",
            measuredReference,
            baselineReference
        )

        let measured = try BenchmarkRunner.measure(
            "circuit.postLayoutRowMajorCompare",
            iterationsPerSample: 8
        ) {
            try compareChecksum(
                service.compare(preLayoutResult: preRowMajor, postLayoutResult: postRowMajor)
            )
        }

        let baseline = try BenchmarkRunner.measure(
            "circuit.postLayoutNestedCompare",
            iterationsPerSample: 5
        ) {
            try compareChecksum(
                service.compare(preLayoutResult: preNested, postLayoutResult: postNested)
            )
        }

        return BenchmarkComparison(
            name: "post-layout row-major comparison",
            measured: measured,
            baseline: baseline,
            maximumRatio: 0.85,
            requirement: "Post-layout comparison should scan row-major buffers instead of nested rows."
        )
    }

    public static func ngspiceParseMeasurement() throws -> BenchmarkResult {
        let rawURL = try WaveformBenchmarkFixture.rawFile(pointCount: 2_000, variableCount: 8)
        defer {
            do {
                try FileManager.default.removeItem(at: rawURL.deletingLastPathComponent())
            } catch {
                print("Failed to remove benchmark RAW fixture: \(error)")
            }
        }
        let parser = NgspiceRawParser()

        return try BenchmarkRunner.measure(
            "circuit.ngspiceRawParseToRowMajor",
            iterationsPerSample: 3
        ) {
            sum(try parser.parse(rawURL: rawURL, fallbackAnalysis: nil))
        }
    }

    public static func chartSeriesMeasurement() async throws -> BenchmarkResult {
        let waveform = WaveformBenchmarkFixture.waveform()
        return try await BenchmarkRunner.measureAsync(
            "circuit.waveformViewModelChartSeries",
            iterationsPerSample: 8
        ) {
            await chartSeriesChecksum(waveform: waveform)
        }
    }

    @MainActor
    private static func chartSeriesChecksum(waveform: WaveformData) -> Double {
        let viewModel = WaveformViewModel()
        viewModel.load(waveform: waveform)
        return viewModel.chartSeries.reduce(0.0) { partial, series in
            partial + series.points.reduce(0.0) { pointPartial, point in
                pointPartial + point.sweep + point.value
            }
        }
    }

    private static func buildTransientWaveform(
        timePoints: [Double],
        rowMajorSolutions: [Double],
        sourceVariableCount: Int,
        variableMap: [MNAVariable: Int],
        nodeNamesByID: [Int: String]
    ) -> WaveformData {
        var builder = TransientWaveformBuilder(
            variableMap: variableMap,
            nodeNamesByID: nodeNamesByID
        )
        builder.appendBatch(
            timePoints: timePoints,
            rowMajorSolutions: rowMajorSolutions,
            sourceVariableCount: sourceVariableCount
        )
        return builder.buildWaveformData()
    }

    private static func legacyTransientWaveform(
        timePoints: [Double],
        rowMajorSolutions: [Double],
        sourceVariableCount: Int
    ) -> WaveformData {
        let variableCount = sourceVariableCount
        let variables = (0..<variableCount).map { index in
            VariableDescriptor.voltage(node: "n\(index)", index: index)
        }
        var rows: [[Double]] = []
        rows.reserveCapacity(timePoints.count)
        for point in 0..<timePoints.count {
            var row: [Double] = []
            row.reserveCapacity(variableCount)
            let sourceOffset = point * sourceVariableCount
            for variable in 0..<variableCount {
                row.append(rowMajorSolutions[sourceOffset + variable])
            }
            rows.append(row)
        }
        return WaveformData(
            metadata: SimulationMetadata(
                title: "Benchmark",
                analysisType: .transient,
                pointCount: timePoints.count,
                variableCount: variableCount
            ),
            sweepVariable: .time(),
            sweepValues: timePoints,
            variables: variables,
            realData: rows
        )
    }

    private static func legacyFetch(
        waveform: WaveformData,
        range: ClosedRange<Double>?,
        maxPoints: Int
    ) -> WaveformData {
        let sweepValues = waveform.sweepValues
        guard sweepValues.count > maxPoints, maxPoints > 0 else {
            return waveform
        }
        guard let sweepFirst = sweepValues.first, let sweepLast = sweepValues.last else {
            return waveform
        }
        let effectiveRange = range ?? (sweepFirst...sweepLast)
        let startIdx = sweepValues.firstIndex(where: { $0 >= effectiveRange.lowerBound }) ?? 0
        let endIdx = sweepValues.lastIndex(where: { $0 <= effectiveRange.upperBound }) ?? (sweepValues.count - 1)
        guard endIdx >= startIdx else {
            return waveform
        }

        let rangeCount = endIdx - startIdx + 1
        guard rangeCount > maxPoints else {
            return legacySlice(waveform: waveform, startIdx: startIdx, endIdx: endIdx)
        }

        let bucketSize = Double(rangeCount) / Double(max(maxPoints / 2, 1))
        guard bucketSize > 0 else { return waveform }

        var decimatedSweep: [Double] = []
        decimatedSweep.reserveCapacity(maxPoints)
        var decimatedValues: [Double] = []
        decimatedValues.reserveCapacity(maxPoints * waveform.variableCount)

        var bucketStart = startIdx
        while bucketStart <= endIdx {
            let bucketEnd = min(Int(Double(bucketStart - startIdx) + bucketSize) + startIdx, endIdx)
            guard bucketEnd >= bucketStart else { break }

            var minIdx = bucketStart
            var maxIdx = bucketStart

            if let initialValue = waveform.realValue(variable: 0, point: bucketStart) {
                var minValue = initialValue
                var maxValue = initialValue
                for point in bucketStart...bucketEnd {
                    guard point < waveform.pointCount else { break }
                    guard let value = waveform.realValue(variable: 0, point: point) else { continue }
                    if value < minValue {
                        minValue = value
                        minIdx = point
                    }
                    if value > maxValue {
                        maxValue = value
                        maxIdx = point
                    }
                }
            }

            let indices = minIdx <= maxIdx ? [minIdx, maxIdx] : [maxIdx, minIdx]
            for index in indices {
                guard index <= endIdx, index < waveform.pointCount else { continue }
                decimatedSweep.append(sweepValues[index])
                if let rowWasAppended = waveform.withRealValues(at: index, { values in
                    decimatedValues.append(contentsOf: values)
                    return true
                }), rowWasAppended {
                    continue
                }
                for variable in 0..<waveform.variableCount {
                    decimatedValues.append(waveform.realValue(variable: variable, point: index) ?? 0)
                }
            }

            bucketStart = bucketEnd + 1
        }

        return WaveformData(
            metadata: waveform.metadata,
            sweepVariable: waveform.sweepVariable,
            sweepValues: decimatedSweep,
            variables: waveform.variables,
            realRowMajorData: decimatedValues,
            pointCount: decimatedSweep.count,
            variableCount: waveform.variableCount
        )
    }

    private static func legacySlice(
        waveform: WaveformData,
        startIdx: Int,
        endIdx: Int
    ) -> WaveformData {
        guard startIdx > 0 || endIdx < waveform.pointCount - 1 else {
            return waveform
        }

        var values: [Double] = []
        values.reserveCapacity((endIdx - startIdx + 1) * waveform.variableCount)
        for point in startIdx...endIdx {
            for variable in 0..<waveform.variableCount {
                values.append(waveform.realValue(variable: variable, point: point) ?? 0)
            }
        }
        let sweepValues = Array(waveform.sweepValues[startIdx...endIdx])
        return WaveformData(
            metadata: waveform.metadata,
            sweepVariable: waveform.sweepVariable,
            sweepValues: sweepValues,
            variables: waveform.variables,
            realRowMajorData: values,
            pointCount: sweepValues.count,
            variableCount: waveform.variableCount
        )
    }

    private static func compareChecksum(_ report: PostLayoutComparisonReport) throws -> Double {
        guard report.status == "compared" else {
            throw BenchmarkError.unexpectedReportStatus(report.status)
        }
        return report.comparedVariables.reduce(report.maxAbsoluteDelta + report.maxRelativeDelta) { partial, item in
            partial + item.maxAbsoluteDelta + item.maxRelativeDelta
        }
    }

    private static func sum(_ waveform: WaveformData) -> Double {
        if let value = waveform.withRealRowMajorBuffer({ buffer -> Double in
            guard let sourceBase = buffer.values.baseAddress else { return 0.0 }
            var total = 0.0
            for point in 0..<buffer.pointCount {
                let sourceOffset = buffer.startOffset + (point * buffer.rowStride)
                for variable in 0..<buffer.variableCount {
                    total += sourceBase[sourceOffset + variable]
                }
            }
            return total
        }) {
            return value
        }

        var total = 0.0
        for point in 0..<waveform.pointCount {
            for variable in 0..<waveform.variableCount {
                total += waveform.realValue(variable: variable, point: point) ?? 0
            }
        }
        return total
    }

    private static func assertClose(_ name: String, _ lhs: Double, _ rhs: Double) throws {
        let scale = max(abs(lhs), abs(rhs), 1.0)
        guard abs(lhs - rhs) <= scale * 1.0e-9 else {
            throw BenchmarkError.referenceMismatch(name: name, lhs: lhs, rhs: rhs)
        }
    }
}
