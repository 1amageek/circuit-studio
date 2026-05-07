import Foundation
import CoreSpiceWaveform

public struct PostLayoutComparisonReport: Sendable, Hashable, Codable {
    public let status: String
    public let preLayoutPointCount: Int
    public let postLayoutPointCount: Int
    public let sweepVariable: String?
    public let comparedPointCount: Int
    public let comparedVariables: [PostLayoutVariableComparison]
    public let missingInPostLayout: [String]
    public let addedInPostLayout: [String]
    public let diagnostics: [String]

    public init(
        status: String,
        preLayoutPointCount: Int,
        postLayoutPointCount: Int,
        sweepVariable: String?,
        comparedPointCount: Int,
        comparedVariables: [PostLayoutVariableComparison],
        missingInPostLayout: [String],
        addedInPostLayout: [String],
        diagnostics: [String]
    ) {
        self.status = status
        self.preLayoutPointCount = preLayoutPointCount
        self.postLayoutPointCount = postLayoutPointCount
        self.sweepVariable = sweepVariable
        self.comparedPointCount = comparedPointCount
        self.comparedVariables = comparedVariables
        self.missingInPostLayout = missingInPostLayout
        self.addedInPostLayout = addedInPostLayout
        self.diagnostics = diagnostics
    }
}

public struct PostLayoutVariableComparison: Sendable, Hashable, Codable {
    public let variableName: String
    public let maxAbsoluteDelta: Double
    public let maxRelativeDelta: Double
    public let firstPreLayoutValue: Double?
    public let firstPostLayoutValue: Double?
    public let lastPreLayoutValue: Double?
    public let lastPostLayoutValue: Double?

    public init(
        variableName: String,
        maxAbsoluteDelta: Double,
        maxRelativeDelta: Double,
        firstPreLayoutValue: Double?,
        firstPostLayoutValue: Double?,
        lastPreLayoutValue: Double?,
        lastPostLayoutValue: Double?
    ) {
        self.variableName = variableName
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.firstPreLayoutValue = firstPreLayoutValue
        self.firstPostLayoutValue = firstPostLayoutValue
        self.lastPreLayoutValue = lastPreLayoutValue
        self.lastPostLayoutValue = lastPostLayoutValue
    }
}

public struct PostLayoutComparisonService: Sendable {
    public init() {}

    public func compare(
        preLayoutResult: SimulationResult,
        postLayoutResult: SimulationResult
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
        let comparedPointCount = min(preLayoutWaveform.pointCount, postLayoutWaveform.pointCount)
        let comparisons = commonVariableNames.compactMap { variableName in
            compareVariable(
                named: variableName,
                pointCount: comparedPointCount,
                preLayoutWaveform: preLayoutWaveform,
                postLayoutWaveform: postLayoutWaveform
            )
        }

        var diagnostics: [String] = []
        if preLayoutWaveform.sweepVariable.name != postLayoutWaveform.sweepVariable.name {
            diagnostics.append(
                "Sweep variable mismatch: \(preLayoutWaveform.sweepVariable.name) vs \(postLayoutWaveform.sweepVariable.name)."
            )
        }
        if preLayoutWaveform.pointCount != postLayoutWaveform.pointCount {
            diagnostics.append(
                "Point count mismatch: \(preLayoutWaveform.pointCount) vs \(postLayoutWaveform.pointCount)."
            )
        }
        if comparisons.isEmpty {
            diagnostics.append("No common waveform variables were available for comparison.")
        }

        return PostLayoutComparisonReport(
            status: comparisons.isEmpty ? "not-comparable" : "compared",
            preLayoutPointCount: preLayoutWaveform.pointCount,
            postLayoutPointCount: postLayoutWaveform.pointCount,
            sweepVariable: preLayoutWaveform.sweepVariable.name,
            comparedPointCount: comparedPointCount,
            comparedVariables: comparisons,
            missingInPostLayout: preVariableNames.filter { !postNameSet.contains($0) },
            addedInPostLayout: postVariableNames.filter { !preNameSet.contains($0) },
            diagnostics: diagnostics
        )
    }

    private func compareVariable(
        named variableName: String,
        pointCount: Int,
        preLayoutWaveform: WaveformData,
        postLayoutWaveform: WaveformData
    ) -> PostLayoutVariableComparison? {
        guard let preIndex = preLayoutWaveform.variableIndex(named: variableName),
              let postIndex = postLayoutWaveform.variableIndex(named: variableName),
              pointCount > 0 else {
            return nil
        }

        var maxAbsoluteDelta = 0.0
        var maxRelativeDelta = 0.0
        var firstPreLayoutValue: Double?
        var firstPostLayoutValue: Double?
        var lastPreLayoutValue: Double?
        var lastPostLayoutValue: Double?

        for point in 0..<pointCount {
            guard let preValue = comparableValue(
                waveform: preLayoutWaveform,
                variable: preIndex,
                point: point
            ), let postValue = comparableValue(
                waveform: postLayoutWaveform,
                variable: postIndex,
                point: point
            ) else {
                continue
            }

            if point == 0 {
                firstPreLayoutValue = preValue
                firstPostLayoutValue = postValue
            }
            lastPreLayoutValue = preValue
            lastPostLayoutValue = postValue

            let absoluteDelta = abs(postValue - preValue)
            let relativeDelta = absoluteDelta / max(abs(preValue), 1.0e-30)
            maxAbsoluteDelta = max(maxAbsoluteDelta, absoluteDelta)
            maxRelativeDelta = max(maxRelativeDelta, relativeDelta)
        }

        return PostLayoutVariableComparison(
            variableName: variableName,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            firstPreLayoutValue: firstPreLayoutValue,
            firstPostLayoutValue: firstPostLayoutValue,
            lastPreLayoutValue: lastPreLayoutValue,
            lastPostLayoutValue: lastPostLayoutValue
        )
    }

    private func comparableValue(waveform: WaveformData, variable: Int, point: Int) -> Double? {
        if waveform.isComplex {
            return waveform.magnitude(variable: variable, point: point)
        }
        return waveform.realValue(variable: variable, point: point)
    }

    private func missingWaveformReport(message: String) -> PostLayoutComparisonReport {
        PostLayoutComparisonReport(
            status: "not-comparable",
            preLayoutPointCount: 0,
            postLayoutPointCount: 0,
            sweepVariable: nil,
            comparedPointCount: 0,
            comparedVariables: [],
            missingInPostLayout: [],
            addedInPostLayout: [],
            diagnostics: [message]
        )
    }
}
