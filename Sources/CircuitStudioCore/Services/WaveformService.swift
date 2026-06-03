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

        var decimatedSweep: [Double] = []
        decimatedSweep.reserveCapacity(maxPoints)
        var decimatedValues: [Double] = []
        decimatedValues.reserveCapacity(maxPoints * waveform.variableCount)

        var bucketStart = startIdx
        while bucketStart <= endIdx {
            let bucketEnd = min(Int(Double(bucketStart - startIdx) + bucketSize) + startIdx, endIdx)
            guard bucketEnd >= bucketStart else { break }

            // Find min/max point indices within this bucket using the first variable
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

            // Emit in sweep order
            let indices = minIdx <= maxIdx ? [minIdx, maxIdx] : [maxIdx, minIdx]
            for idx in indices {
                guard idx <= endIdx, idx < waveform.pointCount else { continue }
                decimatedSweep.append(sweepValues[idx])
                if let rowWasAppended = waveform.withRealValues(at: idx, { values in
                    decimatedValues.append(contentsOf: values)
                    return true
                }), rowWasAppended {
                    continue
                }
                for variable in 0..<waveform.variableCount {
                    decimatedValues.append(waveform.realValue(variable: variable, point: idx) ?? 0)
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

    /// Export waveform data to a file. Format is inferred from the file extension.
    public func export(waveform: WaveformData, to url: URL) async throws {
        let registry = SPICEIO.defaultExporterRegistry()
        _ = try await registry.export(waveform, toPath: url.path)
    }
}
