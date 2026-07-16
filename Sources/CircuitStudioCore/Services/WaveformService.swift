import Foundation
import CoreSpiceWaveform
import CoreSpiceIO

/// Service providing decimated waveform data for display.
public struct WaveformService: WaveformProviding, Sendable {

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
        guard !waveform.isComplex else {
            return waveform
        }

        let sweepValues = waveform.sweepValues
        guard sweepValues.count > maxPoints, maxPoints > 0 else {
            return waveform
        }

        guard let sweepFirst = sweepValues.first, let sweepLast = sweepValues.last else {
            return waveform
        }
        let effectiveRange = range ?? (sweepFirst...sweepLast)

        let startIdx = lowerBound(in: sweepValues, for: effectiveRange.lowerBound)
        let endExclusive = upperBound(in: sweepValues, for: effectiveRange.upperBound)
        let endIdx = endExclusive - 1

        guard startIdx < endExclusive else {
            return waveform
        }

        let rangeCount = endIdx - startIdx + 1
        guard rangeCount > maxPoints else {
            return slicedWaveform(
                waveform: waveform,
                sweepValues: sweepValues,
                startIdx: startIdx,
                endIdx: endIdx
            )
        }

        let bucketTarget = max(maxPoints / 2, 1)
        let bucketSize = Double(rangeCount) / Double(bucketTarget)
        guard bucketSize > 0 else { return waveform }

        if let decimated = waveform.withRealRowMajorBuffer({ buffer in
            decimatedWaveform(
                waveform: waveform,
                sweepValues: sweepValues,
                startIdx: startIdx,
                endIdx: endIdx,
                bucketSize: bucketSize,
                buffer: buffer
            )
        }) {
            return decimated
        }

        return decimatedWaveform(
            waveform: waveform,
            sweepValues: sweepValues,
            startIdx: startIdx,
            endIdx: endIdx,
            bucketSize: bucketSize
        )
    }

    private func decimatedWaveform(
        waveform: WaveformData,
        sweepValues: [Double],
        startIdx: Int,
        endIdx: Int,
        bucketSize: Double,
        buffer: RealRowMajorBuffer
    ) -> WaveformData {
        let estimatedOutputCount = min(waveform.pointCount, (endIdx - startIdx + 1) * 2)
        var decimatedSweep: [Double] = []
        decimatedSweep.reserveCapacity(estimatedOutputCount)
        var decimatedValues: [Double] = []
        decimatedValues.reserveCapacity(estimatedOutputCount * waveform.variableCount)

        guard buffer.pointCount == waveform.pointCount,
              buffer.variableCount == waveform.variableCount else {
            return decimatedWaveform(
                waveform: waveform,
                sweepValues: sweepValues,
                startIdx: startIdx,
                endIdx: endIdx,
                bucketSize: bucketSize
            )
        }

        let sourceBase = buffer.values.baseAddress

        var bucketStart = startIdx
        while bucketStart <= endIdx {
            let bucketEnd = min(Int(Double(bucketStart - startIdx) + bucketSize) + startIdx, endIdx)
            guard bucketEnd >= bucketStart else { break }

            // Find min/max point indices within this bucket using the first variable
            var minIdx = bucketStart
            var maxIdx = bucketStart

            if waveform.variableCount > 0, let sourceBase {
                var minValue = realValue(sourceBase: sourceBase, buffer: buffer, point: bucketStart, variable: 0)
                var maxValue = minValue
                for point in bucketStart...bucketEnd {
                    guard point < waveform.pointCount else { break }
                    let value = realValue(sourceBase: sourceBase, buffer: buffer, point: point, variable: 0)
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
                if waveform.variableCount > 0, let sourceBase {
                    let sourceOffset = buffer.startOffset + (idx * buffer.rowStride)
                    decimatedValues.append(
                        contentsOf: UnsafeBufferPointer(
                            start: sourceBase.advanced(by: sourceOffset),
                            count: waveform.variableCount
                        )
                    )
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

    private func decimatedWaveform(
        waveform: WaveformData,
        sweepValues: [Double],
        startIdx: Int,
        endIdx: Int,
        bucketSize: Double
    ) -> WaveformData {
        let estimatedOutputCount = min(waveform.pointCount, (endIdx - startIdx + 1) * 2)
        var decimatedSweep: [Double] = []
        decimatedSweep.reserveCapacity(estimatedOutputCount)
        var decimatedValues: [Double] = []
        decimatedValues.reserveCapacity(estimatedOutputCount * waveform.variableCount)

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

    private func slicedWaveform(
        waveform: WaveformData,
        sweepValues: [Double],
        startIdx: Int,
        endIdx: Int
    ) -> WaveformData {
        guard startIdx > 0 || endIdx < waveform.pointCount - 1 else {
            return waveform
        }

        if let sliced = waveform.withRealRowMajorBuffer({ buffer in
            rowMajorSlicedWaveform(
                waveform: waveform,
                sweepValues: sweepValues,
                startIdx: startIdx,
                endIdx: endIdx,
                buffer: buffer
            )
        }) {
            return sliced
        }

        var values: [Double] = []
        values.reserveCapacity((endIdx - startIdx + 1) * waveform.variableCount)
        for point in startIdx...endIdx {
            if let rowWasAppended = waveform.withRealValues(at: point, { row in
                values.append(contentsOf: row)
                return true
            }), rowWasAppended {
                continue
            }
            for variable in 0..<waveform.variableCount {
                values.append(waveform.realValue(variable: variable, point: point) ?? 0)
            }
        }

        let slicedSweepValues = Array(sweepValues[startIdx...endIdx])
        return WaveformData(
            metadata: waveform.metadata,
            sweepVariable: waveform.sweepVariable,
            sweepValues: slicedSweepValues,
            variables: waveform.variables,
            realRowMajorData: values,
            pointCount: slicedSweepValues.count,
            variableCount: waveform.variableCount
        )
    }

    private func rowMajorSlicedWaveform(
        waveform: WaveformData,
        sweepValues: [Double],
        startIdx: Int,
        endIdx: Int,
        buffer: RealRowMajorBuffer
    ) -> WaveformData {
        let pointCount = endIdx - startIdx + 1
        var values: [Double] = []
        values.reserveCapacity(pointCount * waveform.variableCount)

        if waveform.variableCount > 0, let sourceBase = buffer.values.baseAddress {
            for point in startIdx...endIdx {
                let sourceOffset = buffer.startOffset + (point * buffer.rowStride)
                values.append(
                    contentsOf: UnsafeBufferPointer(
                        start: sourceBase.advanced(by: sourceOffset),
                        count: waveform.variableCount
                    )
                )
            }
        }

        let slicedSweepValues = Array(sweepValues[startIdx...endIdx])
        return WaveformData(
            metadata: waveform.metadata,
            sweepVariable: waveform.sweepVariable,
            sweepValues: slicedSweepValues,
            variables: waveform.variables,
            realRowMajorData: values,
            pointCount: slicedSweepValues.count,
            variableCount: waveform.variableCount
        )
    }

    private func lowerBound(in values: [Double], for target: Double) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let middle = (low + high) / 2
            if values[middle] < target {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func upperBound(in values: [Double], for target: Double) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let middle = (low + high) / 2
            if values[middle] <= target {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func realValue(
        sourceBase: UnsafePointer<Double>,
        buffer: RealRowMajorBuffer,
        point: Int,
        variable: Int
    ) -> Double {
        sourceBase[buffer.startOffset + (point * buffer.rowStride) + variable]
    }

    /// Export waveform data to a file. Format is inferred from the file extension.
    public func export(waveform: WaveformData, to url: URL) async throws {
        let registry = SPICEIO.defaultExporterRegistry()
        _ = try await registry.export(waveform, toPath: url.path)
    }
}
