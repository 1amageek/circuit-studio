import Foundation

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
        for domainLimit in limits.domainLimits {
            let domainComparisons = comparedVariables.filter { $0.signalDomain == domainLimit.domain }
            guard !domainComparisons.isEmpty else {
                violations.append(
                    "Post-layout domain \(domainLimit.domain.rawValue) had no compared variables for a domain-specific limit."
                )
                continue
            }
            let maxAbsoluteDelta = domainComparisons.map(\.maxAbsoluteDelta).max() ?? 0
            if let maxAbsoluteDeltaLimit = domainLimit.maxAbsoluteDelta,
               maxAbsoluteDelta > maxAbsoluteDeltaLimit {
                violations.append(
                    "Post-layout domain \(domainLimit.domain.rawValue) absolute delta \(maxAbsoluteDelta) exceeds limit \(maxAbsoluteDeltaLimit)."
                )
            }
            let maxRelativeDelta = domainComparisons.map(\.maxRelativeDelta).max() ?? 0
            if let maxRelativeDeltaLimit = domainLimit.maxRelativeDelta,
               maxRelativeDelta > maxRelativeDeltaLimit {
                violations.append(
                    "Post-layout domain \(domainLimit.domain.rawValue) relative delta \(maxRelativeDelta) exceeds limit \(maxRelativeDeltaLimit)."
                )
            }
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
    public let domainLimits: [PostLayoutSignalDomainComparisonLimit]
    public let variableLimits: [PostLayoutVariableComparisonLimit]
    public let oscillationMetricLimits: [PostLayoutOscillationMetricLimit]

    public init(
        maxAbsoluteDelta: Double? = nil,
        maxRelativeDelta: Double? = nil,
        relativeDeltaDenominatorFloor: Double? = nil,
        domainLimits: [PostLayoutSignalDomainComparisonLimit] = [],
        variableLimits: [PostLayoutVariableComparisonLimit] = [],
        oscillationMetricLimits: [PostLayoutOscillationMetricLimit] = []
    ) {
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.relativeDeltaDenominatorFloor = relativeDeltaDenominatorFloor
        self.domainLimits = domainLimits
        self.variableLimits = variableLimits
        self.oscillationMetricLimits = oscillationMetricLimits
    }

    private enum CodingKeys: String, CodingKey {
        case maxAbsoluteDelta
        case maxRelativeDelta
        case relativeDeltaDenominatorFloor
        case domainLimits
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
        self.domainLimits = try container.decodeIfPresent(
            [PostLayoutSignalDomainComparisonLimit].self,
            forKey: .domainLimits
        ) ?? []
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
        var seenDomains = Set<PostLayoutSignalDomain>()
        for domainLimit in domainLimits {
            diagnostics.append(contentsOf: domainLimit.validationDiagnostics())
            if !seenDomains.insert(domainLimit.domain).inserted {
                diagnostics.append("Duplicate domain-specific comparison limit: \(domainLimit.domain.rawValue).")
            }
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

public enum PostLayoutSignalDomain: String, Sendable, Hashable, Codable, CaseIterable {
    case voltage
    case current
    case time
    case frequency
    case power
    case phase
    case magnitude
    case parameter
    case other
}

public struct PostLayoutSignalDomainComparisonLimit: Sendable, Hashable, Codable {
    public let domain: PostLayoutSignalDomain
    public let maxAbsoluteDelta: Double?
    public let maxRelativeDelta: Double?
    public let relativeDeltaDenominatorFloor: Double?

    public init(
        domain: PostLayoutSignalDomain,
        maxAbsoluteDelta: Double? = nil,
        maxRelativeDelta: Double? = nil,
        relativeDeltaDenominatorFloor: Double? = nil
    ) {
        self.domain = domain
        self.maxAbsoluteDelta = maxAbsoluteDelta
        self.maxRelativeDelta = maxRelativeDelta
        self.relativeDeltaDenominatorFloor = relativeDeltaDenominatorFloor
    }

    public func validationDiagnostics() -> [String] {
        var diagnostics: [String] = []
        if maxAbsoluteDelta == nil && maxRelativeDelta == nil {
            diagnostics.append("Domain-specific comparison limit for \(domain.rawValue) has no numeric limit.")
        }
        if let maxAbsoluteDelta, !Self.isValidLimit(maxAbsoluteDelta) {
            diagnostics.append("Invalid max absolute delta limit for \(domain.rawValue): \(maxAbsoluteDelta).")
        }
        if let maxRelativeDelta, !Self.isValidLimit(maxRelativeDelta) {
            diagnostics.append("Invalid max relative delta limit for \(domain.rawValue): \(maxRelativeDelta).")
        }
        if let relativeDeltaDenominatorFloor, !Self.isValidLimit(relativeDeltaDenominatorFloor) {
            diagnostics.append(
                "Invalid relative delta denominator floor for \(domain.rawValue): \(relativeDeltaDenominatorFloor)."
            )
        }
        return diagnostics
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
    public let signalDomain: PostLayoutSignalDomain?
    public let unit: String?
    public let maxAbsoluteDelta: Double
    public let maxRelativeDelta: Double
    public let firstPreLayoutValue: Double?
    public let firstPostLayoutValue: Double?
    public let lastPreLayoutValue: Double?
    public let lastPostLayoutValue: Double?

    public init(
        variableName: String,
        signalDomain: PostLayoutSignalDomain? = nil,
        unit: String? = nil,
        maxAbsoluteDelta: Double,
        maxRelativeDelta: Double,
        firstPreLayoutValue: Double?,
        firstPostLayoutValue: Double?,
        lastPreLayoutValue: Double?,
        lastPostLayoutValue: Double?
    ) {
        self.variableName = variableName
        self.signalDomain = signalDomain
        self.unit = unit
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

