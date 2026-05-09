import Foundation
import CoreSpiceWaveform

public struct PostLayoutComparisonReport: Sendable, Hashable, Codable {
    public let status: String
    public let preLayoutPointCount: Int
    public let postLayoutPointCount: Int
    public let sweepVariable: String?
    public let comparedPointCount: Int
    public let maxAbsoluteDelta: Double
    public let maxRelativeDelta: Double
    public let comparedVariables: [PostLayoutVariableComparison]
    public let missingInPostLayout: [String]
    public let addedInPostLayout: [String]
    public let diagnostics: [String]
    public let comparisonLimits: PostLayoutComparisonLimits?
    public let gateStatus: String
    public let gateViolations: [String]

    public init(
        status: String,
        preLayoutPointCount: Int,
        postLayoutPointCount: Int,
        sweepVariable: String?,
        comparedPointCount: Int,
        maxAbsoluteDelta: Double,
        maxRelativeDelta: Double,
        comparedVariables: [PostLayoutVariableComparison],
        missingInPostLayout: [String],
        addedInPostLayout: [String],
        diagnostics: [String],
        comparisonLimits: PostLayoutComparisonLimits? = nil,
        gateStatus: String = "not-evaluated",
        gateViolations: [String] = []
    ) {
        self.status = status
        self.preLayoutPointCount = preLayoutPointCount
        self.postLayoutPointCount = postLayoutPointCount
        self.sweepVariable = sweepVariable
        self.comparedPointCount = comparedPointCount
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.comparedVariables = comparedVariables
        self.missingInPostLayout = missingInPostLayout
        self.addedInPostLayout = addedInPostLayout
        self.diagnostics = diagnostics
        self.comparisonLimits = comparisonLimits
        self.gateStatus = gateStatus
        self.gateViolations = gateViolations
    }

    public func limitViolations(_ limits: PostLayoutComparisonLimits) -> [String] {
        let limitDiagnostics = limits.validationDiagnostics()
        guard limitDiagnostics.isEmpty else {
            return limitDiagnostics
        }
        guard status == "compared" else {
            let detail = diagnostics.isEmpty ? status : diagnostics.joined(separator: "; ")
            return ["Post-layout comparison is not comparable: \(detail)"]
        }

        var violations: [String] = []
        if let maxAbsoluteDeltaLimit = limits.maxAbsoluteDelta,
           maxAbsoluteDelta > maxAbsoluteDeltaLimit {
            violations.append(
                "Post-layout maximum absolute delta \(maxAbsoluteDelta) exceeds limit \(maxAbsoluteDeltaLimit)."
            )
        }
        if let maxRelativeDeltaLimit = limits.maxRelativeDelta,
           maxRelativeDelta > maxRelativeDeltaLimit {
            violations.append(
                "Post-layout maximum relative delta \(maxRelativeDelta) exceeds limit \(maxRelativeDeltaLimit)."
            )
        }
        var comparisonsByName: [String: PostLayoutVariableComparison] = [:]
        for comparison in comparedVariables where comparisonsByName[comparison.variableName] == nil {
            comparisonsByName[comparison.variableName] = comparison
        }
        for variableLimit in limits.variableLimits {
            guard let comparison = comparisonsByName[variableLimit.variableName] else {
                violations.append(
                    "Post-layout variable \(variableLimit.variableName) was not compared for a variable-specific limit."
                )
                continue
            }
            if let maxAbsoluteDeltaLimit = variableLimit.maxAbsoluteDelta,
               comparison.maxAbsoluteDelta > maxAbsoluteDeltaLimit {
                violations.append(
                    "Post-layout variable \(variableLimit.variableName) absolute delta \(comparison.maxAbsoluteDelta) exceeds limit \(maxAbsoluteDeltaLimit)."
                )
            }
            if let maxRelativeDeltaLimit = variableLimit.maxRelativeDelta,
               comparison.maxRelativeDelta > maxRelativeDeltaLimit {
                violations.append(
                    "Post-layout variable \(variableLimit.variableName) relative delta \(comparison.maxRelativeDelta) exceeds limit \(maxRelativeDeltaLimit)."
                )
            }
        }
        return violations
    }

    public func applyingLimits(_ limits: PostLayoutComparisonLimits?) -> PostLayoutComparisonReport {
        guard let limits else {
            return PostLayoutComparisonReport(
                status: status,
                preLayoutPointCount: preLayoutPointCount,
                postLayoutPointCount: postLayoutPointCount,
                sweepVariable: sweepVariable,
                comparedPointCount: comparedPointCount,
                maxAbsoluteDelta: maxAbsoluteDelta,
                maxRelativeDelta: maxRelativeDelta,
                comparedVariables: comparedVariables,
                missingInPostLayout: missingInPostLayout,
                addedInPostLayout: addedInPostLayout,
                diagnostics: diagnostics,
                comparisonLimits: nil,
                gateStatus: "not-evaluated",
                gateViolations: []
            )
        }

        let violations = limitViolations(limits)
        return PostLayoutComparisonReport(
            status: status,
            preLayoutPointCount: preLayoutPointCount,
            postLayoutPointCount: postLayoutPointCount,
            sweepVariable: sweepVariable,
            comparedPointCount: comparedPointCount,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            comparedVariables: comparedVariables,
            missingInPostLayout: missingInPostLayout,
            addedInPostLayout: addedInPostLayout,
            diagnostics: diagnostics,
            comparisonLimits: limits,
            gateStatus: violations.isEmpty ? "passed" : "failed",
            gateViolations: violations
        )
    }
}

public struct PostLayoutComparisonLimits: Sendable, Hashable, Codable {
    public let maxAbsoluteDelta: Double?
    public let maxRelativeDelta: Double?
    public let variableLimits: [PostLayoutVariableComparisonLimit]

    public init(
        maxAbsoluteDelta: Double? = nil,
        maxRelativeDelta: Double? = nil,
        variableLimits: [PostLayoutVariableComparisonLimit] = []
    ) {
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.variableLimits = variableLimits
    }

    private enum CodingKeys: String, CodingKey {
        case maxAbsoluteDelta
        case maxRelativeDelta
        case variableLimits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.maxAbsoluteDelta = try container.decodeIfPresent(Double.self, forKey: .maxAbsoluteDelta)
        self.maxRelativeDelta = try container.decodeIfPresent(Double.self, forKey: .maxRelativeDelta)
        self.variableLimits = try container.decodeIfPresent(
            [PostLayoutVariableComparisonLimit].self,
            forKey: .variableLimits
        ) ?? []
    }

    public func validationDiagnostics() -> [String] {
        var diagnostics: [String] = []
        if let maxAbsoluteDelta, !Self.isValidLimit(maxAbsoluteDelta) {
            diagnostics.append("Invalid max absolute delta limit: \(maxAbsoluteDelta).")
        }
        if let maxRelativeDelta, !Self.isValidLimit(maxRelativeDelta) {
            diagnostics.append("Invalid max relative delta limit: \(maxRelativeDelta).")
        }
        var seenVariableNames = Set<String>()
        for variableLimit in variableLimits {
            diagnostics.append(contentsOf: variableLimit.validationDiagnostics())
            if !seenVariableNames.insert(variableLimit.variableName).inserted {
                diagnostics.append("Duplicate variable-specific comparison limit: \(variableLimit.variableName).")
            }
        }
        return diagnostics
    }

    public var isValid: Bool {
        validationDiagnostics().isEmpty
    }

    private static func isValidLimit(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }
}

public struct PostLayoutVariableComparisonLimit: Sendable, Hashable, Codable {
    public let variableName: String
    public let maxAbsoluteDelta: Double?
    public let maxRelativeDelta: Double?

    public init(
        variableName: String,
        maxAbsoluteDelta: Double? = nil,
        maxRelativeDelta: Double? = nil
    ) {
        self.variableName = variableName
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
    }

    public func validationDiagnostics() -> [String] {
        var diagnostics: [String] = []
        if variableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append("Variable-specific comparison limit has an empty variable name.")
        }
        if maxAbsoluteDelta == nil && maxRelativeDelta == nil {
            diagnostics.append("Variable-specific comparison limit for \(variableName) has no numeric limit.")
        }
        if let maxAbsoluteDelta, !Self.isValidLimit(maxAbsoluteDelta) {
            diagnostics.append("Invalid max absolute delta limit for \(variableName): \(maxAbsoluteDelta).")
        }
        if let maxRelativeDelta, !Self.isValidLimit(maxRelativeDelta) {
            diagnostics.append("Invalid max relative delta limit for \(variableName): \(maxRelativeDelta).")
        }
        return diagnostics
    }

    private static func isValidLimit(_ value: Double) -> Bool {
        value.isFinite && value >= 0
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

public struct PostLayoutCornerComparisonReport: Sendable, Hashable, Codable {
    public let cornerID: String
    public let report: PostLayoutComparisonReport

    public init(cornerID: String, report: PostLayoutComparisonReport) {
        self.cornerID = cornerID
        self.report = report
    }
}

public struct PostLayoutMultiCornerComparisonReport: Sendable, Hashable, Codable {
    public let status: String
    public let cornerReports: [PostLayoutCornerComparisonReport]
    public let maxAbsoluteDelta: Double
    public let maxRelativeDelta: Double
    public let worstAbsoluteCornerID: String?
    public let worstRelativeCornerID: String?
    public let gateStatus: String
    public let gateViolations: [String]

    public init(cornerReports: [PostLayoutCornerComparisonReport]) {
        self.cornerReports = cornerReports
        self.maxAbsoluteDelta = cornerReports.map(\.report.maxAbsoluteDelta).max() ?? 0
        self.maxRelativeDelta = cornerReports.map(\.report.maxRelativeDelta).max() ?? 0
        self.worstAbsoluteCornerID = cornerReports.max {
            $0.report.maxAbsoluteDelta < $1.report.maxAbsoluteDelta
        }?.cornerID
        self.worstRelativeCornerID = cornerReports.max {
            $0.report.maxRelativeDelta < $1.report.maxRelativeDelta
        }?.cornerID
        let violations = cornerReports.flatMap { cornerReport in
            cornerReport.report.gateViolations.map { "[\(cornerReport.cornerID)] \($0)" }
        }
        if cornerReports.isEmpty {
            self.status = "not-comparable"
            self.gateStatus = "failed"
            self.gateViolations = ["No corner reports were provided."]
        } else if cornerReports.contains(where: { $0.report.status != "compared" }) {
            self.status = "not-comparable"
            self.gateStatus = violations.isEmpty ? "not-evaluated" : "failed"
            self.gateViolations = violations
        } else {
            self.status = "compared"
            self.gateStatus = violations.isEmpty ? "passed" : "failed"
            self.gateViolations = violations
        }
    }
}

public struct PostLayoutComparisonService: Sendable {
    private let sweepTolerance: Double

    public init(sweepTolerance: Double = 1.0e-12) {
        self.sweepTolerance = sweepTolerance
    }

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
            compareVariable(
                named: variableName,
                alignedPoints: alignment.points,
                preLayoutWaveform: preLayoutWaveform,
                postLayoutWaveform: postLayoutWaveform
            )
        }

        if comparisons.isEmpty {
            comparisonDiagnostics.append("No common waveform variables were available for comparison.")
        }

        let maxAbsoluteDelta = comparisons.map(\.maxAbsoluteDelta).max() ?? 0
        let maxRelativeDelta = comparisons.map(\.maxRelativeDelta).max() ?? 0

        return PostLayoutComparisonReport(
            status: comparisons.isEmpty ? "not-comparable" : "compared",
            preLayoutPointCount: preLayoutWaveform.pointCount,
            postLayoutPointCount: postLayoutWaveform.pointCount,
            sweepVariable: preLayoutWaveform.sweepVariable.name,
            comparedPointCount: comparedPointCount,
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            comparedVariables: comparisons,
            missingInPostLayout: preVariableNames.filter { !postNameSet.contains($0) },
            addedInPostLayout: postVariableNames.filter { !preNameSet.contains($0) },
            diagnostics: comparisonDiagnostics
        )
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

    private func compareVariable(
        named variableName: String,
        alignedPoints: [AlignedPoint],
        preLayoutWaveform: WaveformData,
        postLayoutWaveform: WaveformData
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
            let relativeDelta = absoluteDelta / max(abs(preValue), abs(postValue), 1.0e-30)
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
            maxAbsoluteDelta: 0,
            maxRelativeDelta: 0,
            comparedVariables: [],
            missingInPostLayout: [],
            addedInPostLayout: [],
            diagnostics: [message]
        )
    }
}
