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
    public let oscillationMetrics: [PostLayoutOscillationMetricComparison]
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
        oscillationMetrics: [PostLayoutOscillationMetricComparison] = [],
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
        self.oscillationMetrics = oscillationMetrics
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
        var oscillationMetricsByName: [String: PostLayoutOscillationMetricComparison] = [:]
        for metric in oscillationMetrics where oscillationMetricsByName[metric.variableName] == nil {
            oscillationMetricsByName[metric.variableName] = metric
        }
        for metricLimit in limits.oscillationMetricLimits {
            guard let metric = oscillationMetricsByName[metricLimit.variableName] else {
                violations.append(
                    "Post-layout oscillation metric for \(metricLimit.variableName) was not computed."
                )
                continue
            }
            violations.append(contentsOf: metric.limitViolations(metricLimit))
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
                oscillationMetrics: oscillationMetrics,
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
            oscillationMetrics: oscillationMetrics,
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
    public let relativeDeltaDenominatorFloor: Double?
    public let variableLimits: [PostLayoutVariableComparisonLimit]
    public let oscillationMetricLimits: [PostLayoutOscillationMetricLimit]

    public init(
        maxAbsoluteDelta: Double? = nil,
        maxRelativeDelta: Double? = nil,
        relativeDeltaDenominatorFloor: Double? = nil,
        variableLimits: [PostLayoutVariableComparisonLimit] = [],
        oscillationMetricLimits: [PostLayoutOscillationMetricLimit] = []
    ) {
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.relativeDeltaDenominatorFloor = relativeDeltaDenominatorFloor
        self.variableLimits = variableLimits
        self.oscillationMetricLimits = oscillationMetricLimits
    }

    private enum CodingKeys: String, CodingKey {
        case maxAbsoluteDelta
        case maxRelativeDelta
        case relativeDeltaDenominatorFloor
        case variableLimits
        case oscillationMetricLimits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.maxAbsoluteDelta = try container.decodeIfPresent(Double.self, forKey: .maxAbsoluteDelta)
        self.maxRelativeDelta = try container.decodeIfPresent(Double.self, forKey: .maxRelativeDelta)
        self.relativeDeltaDenominatorFloor = try container.decodeIfPresent(
            Double.self,
            forKey: .relativeDeltaDenominatorFloor
        )
        self.variableLimits = try container.decodeIfPresent(
            [PostLayoutVariableComparisonLimit].self,
            forKey: .variableLimits
        ) ?? []
        self.oscillationMetricLimits = try container.decodeIfPresent(
            [PostLayoutOscillationMetricLimit].self,
            forKey: .oscillationMetricLimits
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
        if let relativeDeltaDenominatorFloor, !Self.isValidLimit(relativeDeltaDenominatorFloor) {
            diagnostics.append(
                "Invalid relative delta denominator floor: \(relativeDeltaDenominatorFloor)."
            )
        }
        var seenVariableNames = Set<String>()
        for variableLimit in variableLimits {
            diagnostics.append(contentsOf: variableLimit.validationDiagnostics())
            if !seenVariableNames.insert(variableLimit.variableName).inserted {
                diagnostics.append("Duplicate variable-specific comparison limit: \(variableLimit.variableName).")
            }
        }
        var seenOscillationVariableNames = Set<String>()
        for metricLimit in oscillationMetricLimits {
            diagnostics.append(contentsOf: metricLimit.validationDiagnostics())
            if !seenOscillationVariableNames.insert(metricLimit.variableName).inserted {
                diagnostics.append("Duplicate oscillation metric limit: \(metricLimit.variableName).")
            }
        }
        return diagnostics
    }

    public var isValid: Bool {
        validationDiagnostics().isEmpty
    }

    public var requestedOscillationMetricVariableNames: [String] {
        var names: [String] = []
        var seen = Set<String>()
        for metricLimit in oscillationMetricLimits where seen.insert(metricLimit.variableName).inserted {
            names.append(metricLimit.variableName)
        }
        return names
    }

    private static func isValidLimit(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }
}

public struct PostLayoutVariableComparisonLimit: Sendable, Hashable, Codable {
    public let variableName: String
    public let maxAbsoluteDelta: Double?
    public let maxRelativeDelta: Double?
    public let relativeDeltaDenominatorFloor: Double?

    public init(
        variableName: String,
        maxAbsoluteDelta: Double? = nil,
        maxRelativeDelta: Double? = nil,
        relativeDeltaDenominatorFloor: Double? = nil
    ) {
        self.variableName = variableName
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.relativeDeltaDenominatorFloor = relativeDeltaDenominatorFloor
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
        if let relativeDeltaDenominatorFloor, !Self.isValidLimit(relativeDeltaDenominatorFloor) {
            diagnostics.append(
                "Invalid relative delta denominator floor for \(variableName): \(relativeDeltaDenominatorFloor)."
            )
        }
        return diagnostics
    }

    private static func isValidLimit(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }
}

public struct PostLayoutOscillationMetricLimit: Sendable, Hashable, Codable {
    public let variableName: String
    public let threshold: Double?
    public let minTransitionCount: Int?
    public let minAmplitude: Double?
    public let maxFrequencyRelativeDelta: Double?
    public let maxPeriodRelativeDelta: Double?
    public let maxDutyCycleDelta: Double?

    public init(
        variableName: String,
        threshold: Double? = nil,
        minTransitionCount: Int? = nil,
        minAmplitude: Double? = nil,
        maxFrequencyRelativeDelta: Double? = nil,
        maxPeriodRelativeDelta: Double? = nil,
        maxDutyCycleDelta: Double? = nil
    ) {
        self.variableName = variableName
        self.threshold = threshold
        self.minTransitionCount = minTransitionCount
        self.minAmplitude = minAmplitude
        self.maxFrequencyRelativeDelta = maxFrequencyRelativeDelta
        self.maxPeriodRelativeDelta = maxPeriodRelativeDelta
        self.maxDutyCycleDelta = maxDutyCycleDelta
    }

    public func validationDiagnostics() -> [String] {
        var diagnostics: [String] = []
        if variableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append("Oscillation metric limit has an empty variable name.")
        }
        if threshold.map({ !$0.isFinite }) == true {
            diagnostics.append("Invalid oscillation threshold for \(variableName): \(threshold ?? .nan).")
        }
        if let minTransitionCount, minTransitionCount < 0 {
            diagnostics.append("Invalid minimum transition count for \(variableName): \(minTransitionCount).")
        }
        if let minAmplitude, !Self.isValidNonNegativeLimit(minAmplitude) {
            diagnostics.append("Invalid minimum amplitude for \(variableName): \(minAmplitude).")
        }
        if let maxFrequencyRelativeDelta, !Self.isValidNonNegativeLimit(maxFrequencyRelativeDelta) {
            diagnostics.append("Invalid maximum frequency relative delta for \(variableName): \(maxFrequencyRelativeDelta).")
        }
        if let maxPeriodRelativeDelta, !Self.isValidNonNegativeLimit(maxPeriodRelativeDelta) {
            diagnostics.append("Invalid maximum period relative delta for \(variableName): \(maxPeriodRelativeDelta).")
        }
        if let maxDutyCycleDelta, !Self.isValidNonNegativeLimit(maxDutyCycleDelta) {
            diagnostics.append("Invalid maximum duty cycle delta for \(variableName): \(maxDutyCycleDelta).")
        }
        if minTransitionCount == nil
            && minAmplitude == nil
            && maxFrequencyRelativeDelta == nil
            && maxPeriodRelativeDelta == nil
            && maxDutyCycleDelta == nil {
            diagnostics.append("Oscillation metric limit for \(variableName) has no numeric limit.")
        }
        return diagnostics
    }

    private static func isValidNonNegativeLimit(_ value: Double) -> Bool {
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

public struct PostLayoutOscillationMetrics: Sendable, Hashable, Codable {
    public let transitionCount: Int
    public let risingEdgeCount: Int
    public let fallingEdgeCount: Int
    public let minValue: Double
    public let maxValue: Double
    public let amplitude: Double
    public let averagePeriod: Double?
    public let frequency: Double?
    public let dutyCycle: Double?
    public let firstRisingEdgeTime: Double?
    public let lastRisingEdgeTime: Double?

    public init(
        transitionCount: Int,
        risingEdgeCount: Int,
        fallingEdgeCount: Int,
        minValue: Double,
        maxValue: Double,
        amplitude: Double,
        averagePeriod: Double?,
        frequency: Double?,
        dutyCycle: Double?,
        firstRisingEdgeTime: Double?,
        lastRisingEdgeTime: Double?
    ) {
        self.transitionCount = transitionCount
        self.risingEdgeCount = risingEdgeCount
        self.fallingEdgeCount = fallingEdgeCount
        self.minValue = minValue
        self.maxValue = maxValue
        self.amplitude = amplitude
        self.averagePeriod = averagePeriod
        self.frequency = frequency
        self.dutyCycle = dutyCycle
        self.firstRisingEdgeTime = firstRisingEdgeTime
        self.lastRisingEdgeTime = lastRisingEdgeTime
    }
}

public struct PostLayoutOscillationMetricComparison: Sendable, Hashable, Codable {
    public let variableName: String
    public let threshold: Double
    public let preLayout: PostLayoutOscillationMetrics?
    public let postLayout: PostLayoutOscillationMetrics?
    public let frequencyRelativeDelta: Double?
    public let periodRelativeDelta: Double?
    public let dutyCycleDelta: Double?
    public let diagnostics: [String]

    public init(
        variableName: String,
        threshold: Double,
        preLayout: PostLayoutOscillationMetrics?,
        postLayout: PostLayoutOscillationMetrics?,
        frequencyRelativeDelta: Double?,
        periodRelativeDelta: Double?,
        dutyCycleDelta: Double?,
        diagnostics: [String]
    ) {
        self.variableName = variableName
        self.threshold = threshold
        self.preLayout = preLayout
        self.postLayout = postLayout
        self.frequencyRelativeDelta = frequencyRelativeDelta
        self.periodRelativeDelta = periodRelativeDelta
        self.dutyCycleDelta = dutyCycleDelta
        self.diagnostics = diagnostics
    }

    public func limitViolations(_ limit: PostLayoutOscillationMetricLimit) -> [String] {
        var violations: [String] = []
        if !diagnostics.isEmpty {
            violations.append(
                "Post-layout oscillation metric for \(variableName) is not comparable: \(diagnostics.joined(separator: "; "))."
            )
        }
        guard let preLayout, let postLayout else {
            violations.append("Post-layout oscillation metric for \(variableName) is missing pre or post data.")
            return violations
        }
        if let minTransitionCount = limit.minTransitionCount {
            if preLayout.transitionCount < minTransitionCount {
                violations.append(
                    "Pre-layout oscillation transition count \(preLayout.transitionCount) for \(variableName) is below limit \(minTransitionCount)."
                )
            }
            if postLayout.transitionCount < minTransitionCount {
                violations.append(
                    "Post-layout oscillation transition count \(postLayout.transitionCount) for \(variableName) is below limit \(minTransitionCount)."
                )
            }
        }
        if let minAmplitude = limit.minAmplitude {
            if preLayout.amplitude < minAmplitude {
                violations.append(
                    "Pre-layout oscillation amplitude \(preLayout.amplitude) for \(variableName) is below limit \(minAmplitude)."
                )
            }
            if postLayout.amplitude < minAmplitude {
                violations.append(
                    "Post-layout oscillation amplitude \(postLayout.amplitude) for \(variableName) is below limit \(minAmplitude)."
                )
            }
        }
        if let maxFrequencyRelativeDelta = limit.maxFrequencyRelativeDelta {
            guard let frequencyRelativeDelta else {
                violations.append("Post-layout oscillation frequency delta for \(variableName) is unavailable.")
                return violations
            }
            if frequencyRelativeDelta > maxFrequencyRelativeDelta {
                violations.append(
                    "Post-layout oscillation frequency relative delta \(frequencyRelativeDelta) for \(variableName) exceeds limit \(maxFrequencyRelativeDelta)."
                )
            }
        }
        if let maxPeriodRelativeDelta = limit.maxPeriodRelativeDelta {
            guard let periodRelativeDelta else {
                violations.append("Post-layout oscillation period delta for \(variableName) is unavailable.")
                return violations
            }
            if periodRelativeDelta > maxPeriodRelativeDelta {
                violations.append(
                    "Post-layout oscillation period relative delta \(periodRelativeDelta) for \(variableName) exceeds limit \(maxPeriodRelativeDelta)."
                )
            }
        }
        if let maxDutyCycleDelta = limit.maxDutyCycleDelta {
            guard let dutyCycleDelta else {
                violations.append("Post-layout oscillation duty-cycle delta for \(variableName) is unavailable.")
                return violations
            }
            if dutyCycleDelta > maxDutyCycleDelta {
                violations.append(
                    "Post-layout oscillation duty-cycle delta \(dutyCycleDelta) for \(variableName) exceeds limit \(maxDutyCycleDelta)."
                )
            }
        }
        return violations
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
            variableRelativeDeltaDenominatorFloors: [:]
        )
    }

    private func compare(
        preLayoutResult: SimulationResult,
        postLayoutResult: SimulationResult,
        oscillationMetricVariableNames: [String],
        relativeDeltaDenominatorFloor: Double,
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
            compareVariable(
                named: variableName,
                alignedPoints: alignment.points,
                preLayoutWaveform: preLayoutWaveform,
                postLayoutWaveform: postLayoutWaveform,
                relativeDeltaDenominatorFloor: variableRelativeDeltaDenominatorFloors[variableName]
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
            maxAbsoluteDelta: maxAbsoluteDelta,
            maxRelativeDelta: maxRelativeDelta,
            firstPreLayoutValue: firstPreLayoutValue,
            firstPostLayoutValue: firstPostLayoutValue,
            lastPreLayoutValue: lastPreLayoutValue,
            lastPostLayoutValue: lastPostLayoutValue
        )
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

    private func comparableValue(waveform: WaveformData, variable: Int, point: Int) -> Double? {
        if waveform.isComplex {
            return waveform.magnitude(variable: variable, point: point)
        }
        return waveform.realValue(variable: variable, point: point)
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
