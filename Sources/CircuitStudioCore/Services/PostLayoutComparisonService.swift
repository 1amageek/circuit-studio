import Foundation
import CoreSpiceWaveform

public struct PostLayoutComparisonService: Sendable {
    private static let defaultRelativeDeltaDenominatorFloor = 1.0e-30

    private let sweepTolerance: Double

    public init(sweepTolerance: Double = 1.0e-12) {
        self.sweepTolerance = sweepTolerance
    }

    public func compare(
        preLayoutResult: SimulationResult,
        postLayoutResult: SimulationResult,
        oscillationMetricVariableNames: [String] = []
    ) -> PostLayoutComparisonReport {
        return compare(
            preLayoutResult: preLayoutResult,
            postLayoutResult: postLayoutResult,
            oscillationMetricVariableNames: oscillationMetricVariableNames,
            relativeDeltaDenominatorFloor: Self.defaultRelativeDeltaDenominatorFloor,
            domainRelativeDeltaDenominatorFloors: [:],
            variableRelativeDeltaDenominatorFloors: [:]
        )
    }

    private func compare(
        preLayoutResult: SimulationResult,
        postLayoutResult: SimulationResult,
        oscillationMetricVariableNames: [String],
        relativeDeltaDenominatorFloor: Double,
        domainRelativeDeltaDenominatorFloors: [PostLayoutSignalDomain: Double],
        variableRelativeDeltaDenominatorFloors: [String: Double]
    ) -> PostLayoutComparisonReport {
        guard let preLayoutWaveform = preLayoutResult.waveform else {
            return missingWaveformReport(message: "Pre-layout waveform is missing.")
        }
        guard let postLayoutWaveform = postLayoutResult.waveform else {
            return missingWaveformReport(message: "Post-layout waveform is missing.")
        }

        let preVariableNames = preLayoutWaveform.variables.map(\.name)
        let postVariableNames = postLayoutWaveform.variables.map(\.name)
        let postNameSet = Set(postVariableNames)
        let preNameSet = Set(preVariableNames)
        let commonVariableNames = preVariableNames.filter { postNameSet.contains($0) }
        var diagnostics: [String] = []
        if preLayoutWaveform.sweepVariable.name != postLayoutWaveform.sweepVariable.name {
            diagnostics.append(
                "Sweep variable mismatch: \(preLayoutWaveform.sweepVariable.name) vs \(postLayoutWaveform.sweepVariable.name)."
            )
        }

        let alignment = sweepAlignment(
            preLayoutValues: preLayoutWaveform.sweepValues,
            postLayoutValues: postLayoutWaveform.sweepValues
        )
        diagnostics.append(contentsOf: alignment.diagnostics)

        guard diagnostics.isEmpty else {
            return PostLayoutComparisonReport(
                status: "not-comparable",
                preLayoutPointCount: preLayoutWaveform.pointCount,
                postLayoutPointCount: postLayoutWaveform.pointCount,
                sweepVariable: preLayoutWaveform.sweepVariable.name,
                comparedPointCount: 0,
                maxAbsoluteDelta: 0,
                maxRelativeDelta: 0,
                comparedVariables: [],
                oscillationMetrics: [],
                missingInPostLayout: preVariableNames.filter { !postNameSet.contains($0) },
                addedInPostLayout: postVariableNames.filter { !preNameSet.contains($0) },
                diagnostics: diagnostics
            )
        }

        var comparisonDiagnostics: [String] = []
        if alignment.usesInterpolation {
            comparisonDiagnostics.append(
                "Post-layout waveform values were linearly interpolated onto the pre-layout sweep grid."
            )
        }
        let comparedPointCount = alignment.points.count
        let comparisons = commonVariableNames.compactMap { variableName in
            let domain = signalDomain(for: variableDescriptor(named: variableName, in: preLayoutWaveform))
            return compareVariable(
                named: variableName,
                alignedPoints: alignment.points,
                preLayoutWaveform: preLayoutWaveform,
                postLayoutWaveform: postLayoutWaveform,
                relativeDeltaDenominatorFloor: variableRelativeDeltaDenominatorFloors[variableName]
                    ?? domainRelativeDeltaDenominatorFloors[domain]
                    ?? relativeDeltaDenominatorFloor
            )
        }

        if comparisons.isEmpty {
            comparisonDiagnostics.append("No common waveform variables were available for comparison.")
        }

        let maxAbsoluteDelta = comparisons.map(\.maxAbsoluteDelta).max() ?? 0
        let maxRelativeDelta = comparisons.map(\.maxRelativeDelta).max() ?? 0
        let requestedOscillationMetricNames = requestedMetricNames(
            requestedNames: oscillationMetricVariableNames,
            availableNames: commonVariableNames
        )
        let oscillationMetrics = requestedOscillationMetricNames.compactMap { variableName in
            compareOscillationMetric(
                named: variableName,
                preLayoutWaveform: preLayoutWaveform,
                postLayoutWaveform: postLayoutWaveform
            )
        }

        return PostLayoutComparisonReport(
            status: comparisons.isEmpty ? "not-comparable" : "compared",
            preLayoutPointCount: preLayoutWaveform.pointCount,
            postLayoutPointCount: postLayoutWaveform.pointCount,
            sweepVariable: preLayoutWaveform.sweepVariable.name,
            comparedPointCount: comparedPointCount,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            comparedVariables: comparisons,
            oscillationMetrics: oscillationMetrics,
            missingInPostLayout: preVariableNames.filter { !postNameSet.contains($0) },
            addedInPostLayout: postVariableNames.filter { !preNameSet.contains($0) },
            diagnostics: comparisonDiagnostics
        )
    }

    public func compare(
        preLayoutResult: SimulationResult,
        postLayoutResult: SimulationResult,
        limits: PostLayoutComparisonLimits?
    ) -> PostLayoutComparisonReport {
        var domainFloors: [PostLayoutSignalDomain: Double] = [:]
        for limit in limits?.domainLimits ?? [] {
            guard domainFloors[limit.domain] == nil,
                  let floor = limit.relativeDeltaDenominatorFloor else {
                continue
            }
            domainFloors[limit.domain] = Self.normalizedRelativeDeltaDenominatorFloor(floor)
        }
        var variableFloors: [String: Double] = [:]
        for limit in limits?.variableLimits ?? [] {
            guard variableFloors[limit.variableName] == nil,
                  let floor = limit.relativeDeltaDenominatorFloor else {
                continue
            }
            variableFloors[limit.variableName] = Self.normalizedRelativeDeltaDenominatorFloor(floor)
        }
        return compare(
            preLayoutResult: preLayoutResult,
            postLayoutResult: postLayoutResult,
            oscillationMetricVariableNames: limits?.requestedOscillationMetricVariableNames ?? [],
            relativeDeltaDenominatorFloor: Self.normalizedRelativeDeltaDenominatorFloor(
                limits?.relativeDeltaDenominatorFloor
            ),
            domainRelativeDeltaDenominatorFloors: domainFloors,
            variableRelativeDeltaDenominatorFloors: variableFloors
        ).applyingLimits(limits)
    }

    public func aggregate(
        cornerReports: [PostLayoutCornerComparisonReport]
    ) -> PostLayoutMultiCornerComparisonReport {
        PostLayoutMultiCornerComparisonReport(cornerReports: cornerReports)
    }

    private struct AlignedPoint {
        let prePoint: Int
        let postPoint: Int?
        let lowerPostPoint: Int?
        let upperPostPoint: Int?
        let interpolationFraction: Double

        var usesInterpolation: Bool {
            lowerPostPoint != nil && upperPostPoint != nil
        }
    }

    private struct SweepAlignment {
        let points: [AlignedPoint]
        let usesInterpolation: Bool
        let diagnostics: [String]
    }

    private func sweepAlignment(preLayoutValues: [Double], postLayoutValues: [Double]) -> SweepAlignment {
        guard !preLayoutValues.isEmpty, !postLayoutValues.isEmpty else {
            return SweepAlignment(
                points: [],
                usesInterpolation: false,
                diagnostics: ["Sweep values are missing."]
            )
        }
        guard isStrictlyIncreasing(preLayoutValues) else {
            return SweepAlignment(
                points: [],
                usesInterpolation: false,
                diagnostics: ["Pre-layout sweep values are not strictly increasing."]
            )
        }
        guard isStrictlyIncreasing(postLayoutValues) else {
            return SweepAlignment(
                points: [],
                usesInterpolation: false,
                diagnostics: ["Post-layout sweep values are not strictly increasing."]
            )
        }

        if preLayoutValues.count == postLayoutValues.count {
            let maxDelta = zip(preLayoutValues, postLayoutValues)
                .map { abs($0 - $1) }
                .max() ?? 0
            if maxDelta <= sweepTolerance {
                return SweepAlignment(
                    points: preLayoutValues.indices.map { index in
                        AlignedPoint(
                            prePoint: index,
                            postPoint: index,
                            lowerPostPoint: nil,
                            upperPostPoint: nil,
                            interpolationFraction: 0
                        )
                    },
                    usesInterpolation: false,
                    diagnostics: []
                )
            }
        }

        let postStart = postLayoutValues[0]
        let postEnd = postLayoutValues[postLayoutValues.count - 1]
        var points: [AlignedPoint] = []
        points.reserveCapacity(preLayoutValues.count)
        var searchIndex = 0

        for preIndex in preLayoutValues.indices {
            let target = preLayoutValues[preIndex]
            guard target + sweepTolerance >= postStart,
                  target - sweepTolerance <= postEnd else {
                continue
            }

            while searchIndex + 1 < postLayoutValues.count
                && postLayoutValues[searchIndex + 1] < target - sweepTolerance {
                searchIndex += 1
            }

            if abs(postLayoutValues[searchIndex] - target) <= sweepTolerance {
                points.append(AlignedPoint(
                    prePoint: preIndex,
                    postPoint: searchIndex,
                    lowerPostPoint: nil,
                    upperPostPoint: nil,
                    interpolationFraction: 0
                ))
                continue
            }

            let upperIndex = searchIndex + 1
            if upperIndex < postLayoutValues.count,
               abs(postLayoutValues[upperIndex] - target) <= sweepTolerance {
                points.append(AlignedPoint(
                    prePoint: preIndex,
                    postPoint: upperIndex,
                    lowerPostPoint: nil,
                    upperPostPoint: nil,
                    interpolationFraction: 0
                ))
                continue
            }

            guard upperIndex < postLayoutValues.count else {
                continue
            }

            let lowerSweep = postLayoutValues[searchIndex]
            let upperSweep = postLayoutValues[upperIndex]
            guard lowerSweep < target, target < upperSweep else {
                continue
            }
            let fraction = (target - lowerSweep) / (upperSweep - lowerSweep)
            points.append(AlignedPoint(
                prePoint: preIndex,
                postPoint: nil,
                lowerPostPoint: searchIndex,
                upperPostPoint: upperIndex,
                interpolationFraction: fraction
            ))
        }

        guard !points.isEmpty else {
            return SweepAlignment(
                points: [],
                usesInterpolation: false,
                diagnostics: ["No overlapping sweep values were available for comparison."]
            )
        }

        return SweepAlignment(
            points: points,
            usesInterpolation: points.contains { $0.usesInterpolation },
            diagnostics: []
        )
    }

    private func isStrictlyIncreasing(_ values: [Double]) -> Bool {
        guard values.count > 1 else {
            return true
        }
        for index in 1..<values.count {
            guard values[index] > values[index - 1] else {
                return false
            }
        }
        return true
    }

    private func requestedMetricNames(requestedNames: [String], availableNames: [String]) -> [String] {
        let availableNameSet = Set(availableNames)
        var names: [String] = []
        var seen = Set<String>()
        for requestedName in requestedNames
            where availableNameSet.contains(requestedName) && seen.insert(requestedName).inserted {
            names.append(requestedName)
        }
        return names
    }

    private func compareVariable(
        named variableName: String,
        alignedPoints: [AlignedPoint],
        preLayoutWaveform: WaveformData,
        postLayoutWaveform: WaveformData,
        relativeDeltaDenominatorFloor: Double
    ) -> PostLayoutVariableComparison? {
        guard let preIndex = preLayoutWaveform.variableIndex(named: variableName),
              let postIndex = postLayoutWaveform.variableIndex(named: variableName),
              !alignedPoints.isEmpty else {
            return nil
        }

        var maxAbsoluteDelta = 0.0
        var maxRelativeDelta = 0.0
        var firstPreLayoutValue: Double?
        var firstPostLayoutValue: Double?
        var lastPreLayoutValue: Double?
        var lastPostLayoutValue: Double?

        var rowMajorComparison: PostLayoutVariableComparison?
        _ = preLayoutWaveform.withRealRowMajorBuffer { preBuffer in
            _ = postLayoutWaveform.withRealRowMajorBuffer { postBuffer in
                rowMajorComparison = compareVariable(
                    named: variableName,
                    alignedPoints: alignedPoints,
                    preLayoutWaveform: preLayoutWaveform,
                    postLayoutWaveform: postLayoutWaveform,
                    preIndex: preIndex,
                    postIndex: postIndex,
                    preBuffer: preBuffer,
                    postBuffer: postBuffer,
                    relativeDeltaDenominatorFloor: relativeDeltaDenominatorFloor
                )
            }
        }
        if let rowMajorComparison {
            return rowMajorComparison
        }

        for (alignedIndex, point) in alignedPoints.enumerated() {
            guard let preValue = comparableValue(
                waveform: preLayoutWaveform,
                variable: preIndex,
                point: point.prePoint
            ), let postValue = alignedPostValue(
                waveform: postLayoutWaveform,
                variable: postIndex,
                point: point
            ) else {
                continue
            }

            if alignedIndex == 0 {
                firstPreLayoutValue = preValue
                firstPostLayoutValue = postValue
            }
            lastPreLayoutValue = preValue
            lastPostLayoutValue = postValue

            let absoluteDelta = abs(postValue - preValue)
            let relativeDelta = absoluteDelta / max(
                abs(preValue),
                abs(postValue),
                relativeDeltaDenominatorFloor
            )
            maxAbsoluteDelta = max(maxAbsoluteDelta, absoluteDelta)
            maxRelativeDelta = max(maxRelativeDelta, relativeDelta)
        }

        return PostLayoutVariableComparison(
            variableName: variableName,
            signalDomain: signalDomain(for: preLayoutWaveform.variables[preIndex]),
            unit: preLayoutWaveform.variables[preIndex].unit.rawValue,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            firstPreLayoutValue: firstPreLayoutValue,
            firstPostLayoutValue: firstPostLayoutValue,
            lastPreLayoutValue: lastPreLayoutValue,
            lastPostLayoutValue: lastPostLayoutValue
        )
    }

    private func compareVariable(
        named variableName: String,
        alignedPoints: [AlignedPoint],
        preLayoutWaveform: WaveformData,
        postLayoutWaveform: WaveformData,
        preIndex: Int,
        postIndex: Int,
        preBuffer: RealRowMajorBuffer,
        postBuffer: RealRowMajorBuffer,
        relativeDeltaDenominatorFloor: Double
    ) -> PostLayoutVariableComparison? {
        guard preIndex < preBuffer.variableCount,
              postIndex < postBuffer.variableCount else {
            return nil
        }

        var maxAbsoluteDelta = 0.0
        var maxRelativeDelta = 0.0
        var firstPreLayoutValue: Double?
        var firstPostLayoutValue: Double?
        var lastPreLayoutValue: Double?
        var lastPostLayoutValue: Double?

        for (alignedIndex, point) in alignedPoints.enumerated() {
            guard let preValue = comparableValue(buffer: preBuffer, variable: preIndex, point: point.prePoint),
                  let postValue = alignedPostValue(buffer: postBuffer, variable: postIndex, point: point) else {
                continue
            }

            if alignedIndex == 0 {
                firstPreLayoutValue = preValue
                firstPostLayoutValue = postValue
            }
            lastPreLayoutValue = preValue
            lastPostLayoutValue = postValue

            let absoluteDelta = abs(postValue - preValue)
            let relativeDelta = absoluteDelta / max(
                abs(preValue),
                abs(postValue),
                relativeDeltaDenominatorFloor
            )
            maxAbsoluteDelta = max(maxAbsoluteDelta, absoluteDelta)
            maxRelativeDelta = max(maxRelativeDelta, relativeDelta)
        }

        return PostLayoutVariableComparison(
            variableName: variableName,
            signalDomain: signalDomain(for: preLayoutWaveform.variables[preIndex]),
            unit: preLayoutWaveform.variables[preIndex].unit.rawValue,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            firstPreLayoutValue: firstPreLayoutValue,
            firstPostLayoutValue: firstPostLayoutValue,
            lastPreLayoutValue: lastPreLayoutValue,
            lastPostLayoutValue: lastPostLayoutValue
        )
    }

    private func variableDescriptor(named variableName: String, in waveform: WaveformData) -> VariableDescriptor? {
        guard let index = waveform.variableIndex(named: variableName) else {
            return nil
        }
        return waveform.variables[index]
    }

    private func signalDomain(for descriptor: VariableDescriptor?) -> PostLayoutSignalDomain {
        guard let descriptor else {
            return .other
        }
        switch descriptor.type {
        case .voltage, .sweepVoltage:
            return .voltage
        case .current, .sweepCurrent:
            return .current
        case .time:
            return .time
        case .frequency:
            return .frequency
        case .power:
            return .power
        case .phase:
            return .phase
        case .magnitude, .real, .imaginary, .noiseDensity:
            return .magnitude
        case .parameter, .temperature:
            return .parameter
        }
    }

    private static func normalizedRelativeDeltaDenominatorFloor(_ value: Double?) -> Double {
        guard let value, value.isFinite, value >= 0 else {
            return defaultRelativeDeltaDenominatorFloor
        }
        return max(value, defaultRelativeDeltaDenominatorFloor)
    }

    private func alignedPostValue(
        waveform: WaveformData,
        variable: Int,
        point: AlignedPoint
    ) -> Double? {
        if let postPoint = point.postPoint {
            return comparableValue(waveform: waveform, variable: variable, point: postPoint)
        }
        guard let lowerPostPoint = point.lowerPostPoint,
              let upperPostPoint = point.upperPostPoint,
              let lowerValue = comparableValue(waveform: waveform, variable: variable, point: lowerPostPoint),
              let upperValue = comparableValue(waveform: waveform, variable: variable, point: upperPostPoint) else {
            return nil
        }
        return lowerValue + ((upperValue - lowerValue) * point.interpolationFraction)
    }

    private func alignedPostValue(
        buffer: RealRowMajorBuffer,
        variable: Int,
        point: AlignedPoint
    ) -> Double? {
        if let postPoint = point.postPoint {
            return comparableValue(buffer: buffer, variable: variable, point: postPoint)
        }
        guard let lowerPostPoint = point.lowerPostPoint,
              let upperPostPoint = point.upperPostPoint,
              let lowerValue = comparableValue(buffer: buffer, variable: variable, point: lowerPostPoint),
              let upperValue = comparableValue(buffer: buffer, variable: variable, point: upperPostPoint) else {
            return nil
        }
        return lowerValue + ((upperValue - lowerValue) * point.interpolationFraction)
    }

    private func comparableValue(waveform: WaveformData, variable: Int, point: Int) -> Double? {
        if waveform.isComplex {
            return waveform.magnitude(variable: variable, point: point)
        }
        return waveform.realValue(variable: variable, point: point)
    }

    private func comparableValue(buffer: RealRowMajorBuffer, variable: Int, point: Int) -> Double? {
        buffer.value(point: point, variable: variable)
    }

    private func compareOscillationMetric(
        named variableName: String,
        preLayoutWaveform: WaveformData,
        postLayoutWaveform: WaveformData
    ) -> PostLayoutOscillationMetricComparison? {
        guard let preIndex = preLayoutWaveform.variableIndex(named: variableName),
              let postIndex = postLayoutWaveform.variableIndex(named: variableName),
              let preValues = realValues(waveform: preLayoutWaveform, variable: preIndex),
              let postValues = realValues(waveform: postLayoutWaveform, variable: postIndex) else {
            return nil
        }

        let combinedMin = min(preValues.min() ?? 0, postValues.min() ?? 0)
        let combinedMax = max(preValues.max() ?? 0, postValues.max() ?? 0)
        guard combinedMax > combinedMin else {
            return PostLayoutOscillationMetricComparison(
                variableName: variableName,
                threshold: combinedMin,
                preLayout: nil,
                postLayout: nil,
                frequencyRelativeDelta: nil,
                periodRelativeDelta: nil,
                dutyCycleDelta: nil,
                diagnostics: ["Waveform amplitude is zero."]
            )
        }

        let threshold = (combinedMin + combinedMax) / 2.0
        let preMetrics = oscillationMetrics(
            sweepValues: preLayoutWaveform.sweepValues,
            values: preValues,
            threshold: threshold
        )
        let postMetrics = oscillationMetrics(
            sweepValues: postLayoutWaveform.sweepValues,
            values: postValues,
            threshold: threshold
        )
        var diagnostics: [String] = []
        if preMetrics.transitionCount == 0 {
            diagnostics.append("Pre-layout waveform has no threshold transitions.")
        }
        if postMetrics.transitionCount == 0 {
            diagnostics.append("Post-layout waveform has no threshold transitions.")
        }

        return PostLayoutOscillationMetricComparison(
            variableName: variableName,
            threshold: threshold,
            preLayout: preMetrics,
            postLayout: postMetrics,
            frequencyRelativeDelta: relativeDelta(preMetrics.frequency, postMetrics.frequency),
            periodRelativeDelta: relativeDelta(preMetrics.averagePeriod, postMetrics.averagePeriod),
            dutyCycleDelta: absoluteDelta(preMetrics.dutyCycle, postMetrics.dutyCycle),
            diagnostics: diagnostics
        )
    }

    private func realValues(waveform: WaveformData, variable: Int) -> [Double]? {
        if let rowMajorValues = waveform.withRealRowMajorBuffer({ buffer -> [Double]? in
            guard variable >= 0, variable < buffer.variableCount else {
                return nil
            }
            guard let sourceBase = buffer.values.baseAddress else {
                return buffer.pointCount == 0 ? [] : nil
            }

            var values: [Double] = []
            values.reserveCapacity(buffer.pointCount)
            for point in 0..<buffer.pointCount {
                let value = sourceBase[buffer.startOffset + (point * buffer.rowStride) + variable]
                guard value.isFinite else {
                    return nil
                }
                values.append(value)
            }
            return values
        }), let rowMajorValues {
            return rowMajorValues
        }

        var values: [Double] = []
        values.reserveCapacity(waveform.pointCount)
        for point in 0..<waveform.pointCount {
            guard let value = comparableValue(waveform: waveform, variable: variable, point: point),
                  value.isFinite else {
                return nil
            }
            values.append(value)
        }
        return values
    }

    private func oscillationMetrics(
        sweepValues: [Double],
        values: [Double],
        threshold: Double
    ) -> PostLayoutOscillationMetrics {
        guard !sweepValues.isEmpty, sweepValues.count == values.count else {
            return PostLayoutOscillationMetrics(
                transitionCount: 0,
                risingEdgeCount: 0,
                fallingEdgeCount: 0,
                minValue: 0,
                maxValue: 0,
                amplitude: 0,
                averagePeriod: nil,
                frequency: nil,
                dutyCycle: nil,
                firstRisingEdgeTime: nil,
                lastRisingEdgeTime: nil
            )
        }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        var risingEdges: [Double] = []
        var fallingEdges: [Double] = []
        var highDuration = 0.0

        for index in 1..<values.count {
            let previousValue = values[index - 1]
            let currentValue = values[index]
            let previousTime = sweepValues[index - 1]
            let currentTime = sweepValues[index]
            let duration = max(0, currentTime - previousTime)
            let previousOffset = previousValue - threshold
            let currentOffset = currentValue - threshold

            if previousValue >= threshold && currentValue >= threshold {
                highDuration += duration
            } else if previousValue < threshold && currentValue < threshold {
                continue
            } else {
                let crossingFraction = previousOffset == currentOffset
                    ? 0.5
                    : max(0, min(1, -previousOffset / (currentOffset - previousOffset)))
                let crossingTime = previousTime + duration * crossingFraction
                if previousValue < threshold && currentValue >= threshold {
                    risingEdges.append(crossingTime)
                    highDuration += max(0, currentTime - crossingTime)
                } else {
                    fallingEdges.append(crossingTime)
                    highDuration += max(0, crossingTime - previousTime)
                }
            }
        }

        let periods = zip(risingEdges, risingEdges.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }
        let averagePeriod = periods.isEmpty ? nil : periods.reduce(0, +) / Double(periods.count)
        let totalDuration = max(0, (sweepValues.last ?? 0) - (sweepValues.first ?? 0))
        let dutyCycle = totalDuration > 0 ? highDuration / totalDuration : nil

        return PostLayoutOscillationMetrics(
            transitionCount: risingEdges.count + fallingEdges.count,
            risingEdgeCount: risingEdges.count,
            fallingEdgeCount: fallingEdges.count,
            minValue: minValue,
            maxValue: maxValue,
            amplitude: maxValue - minValue,
            averagePeriod: averagePeriod,
            frequency: averagePeriod.map { 1.0 / $0 },
            dutyCycle: dutyCycle,
            firstRisingEdgeTime: risingEdges.first,
            lastRisingEdgeTime: risingEdges.last
        )
    }

    private func relativeDelta(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs, lhs.isFinite, rhs.isFinite else {
            return nil
        }
        return abs(rhs - lhs) / max(abs(lhs), abs(rhs), 1.0e-30)
    }

    private func absoluteDelta(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs, lhs.isFinite, rhs.isFinite else {
            return nil
        }
        return abs(rhs - lhs)
    }

    private func missingWaveformReport(message: String) -> PostLayoutComparisonReport {
        PostLayoutComparisonReport(
            status: "not-comparable",
            preLayoutPointCount: 0,
            postLayoutPointCount: 0,
            sweepVariable: nil,
            comparedPointCount: 0,
            maxAbsoluteDelta: 0,
            maxRelativeDelta: 0,
            comparedVariables: [],
            oscillationMetrics: [],
            missingInPostLayout: [],
            addedInPostLayout: [],
            diagnostics: [message]
        )
    }
}
