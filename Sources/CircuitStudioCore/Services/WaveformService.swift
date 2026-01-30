import Foundation
import CoreSpiceWaveform
import CoreSpiceIO

/// Protocol for waveform data access.
public protocol WaveformServiceProtocol: Sendable {
    func fetch(
        waveform: WaveformData,
        variables: [String],
        range: ClosedRange<Double>?,
        maxPoints: Int
    ) -> WaveformData

    func listVariables(waveform: WaveformData) -> [VariableDescriptor]
}

/// Service providing decimated waveform data for display.
public struct WaveformService: WaveformServiceProtocol, Sendable {

    public init() {}

    public func listVariables(waveform: WaveformData) -> [VariableDescriptor] {
        waveform.variables
    }

    /// Returns a decimated waveform for efficient display.
    /// Uses min/max envelope decimation to preserve signal peaks.
    ///
    /// WaveformData stores realData as `[point][variable]`.
    public func fetch(
        waveform: WaveformData,
        variables: [String],
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
            return waveform
        }

        let bucketSize = Double(rangeCount) / Double(maxPoints / 2)
        guard bucketSize > 0 else { return waveform }

        // realData shape: [point][variable]
        var decimatedSweep: [Double] = []
        var decimatedData: [[Double]] = []

        var bucketStart = startIdx
        while bucketStart <= endIdx {
            let bucketEnd = min(Int(Double(bucketStart - startIdx) + bucketSize) + startIdx, endIdx)
            guard bucketEnd >= bucketStart else { break }

            // Find min/max point indices within this bucket using the first variable
            var minIdx = bucketStart
            var maxIdx = bucketStart

            // Access first variable value at each point: data[point][0]
            if let firstPointData = waveform.allRealData, !firstPointData.isEmpty {
                var minVal = waveform.realValue(variable: 0, point: bucketStart) ?? 0
                var maxVal = minVal
                for i in bucketStart...bucketEnd {
                    guard i < waveform.pointCount else { break }
                    let val = waveform.realValue(variable: 0, point: i) ?? 0
                    if val < minVal { minVal = val; minIdx = i }
                    if val > maxVal { maxVal = val; maxIdx = i }
                }
            }

            // Emit in sweep order
            let indices = minIdx <= maxIdx ? [minIdx, maxIdx] : [maxIdx, minIdx]
            for idx in indices {
                guard idx <= endIdx, idx < waveform.pointCount else { continue }
                decimatedSweep.append(sweepValues[idx])
                // Build one point row: [var0, var1, var2, ...]
                var pointRow: [Double] = []
                for varIdx in 0..<waveform.variableCount {
                    pointRow.append(waveform.realValue(variable: varIdx, point: idx) ?? 0)
                }
                decimatedData.append(pointRow)
            }

            bucketStart = bucketEnd + 1
        }

        return WaveformData(
            metadata: waveform.metadata,
            sweepVariable: waveform.sweepVariable,
            sweepValues: decimatedSweep,
            variables: waveform.variables,
            realData: decimatedData
        )
    }

    /// Export waveform data to a file. Format is inferred from the file extension.
    public func export(waveform: WaveformData, to url: URL) async throws {
        let registry = SPICEIO.defaultExporterRegistry()
        _ = try await registry.export(waveform, toPath: url.path)
    }
}
