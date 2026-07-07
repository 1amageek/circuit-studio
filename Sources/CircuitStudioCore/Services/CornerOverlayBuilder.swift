import Foundation
import CoreSpiceWaveform

/// Merges per-corner waveforms of the same analysis into one overlay
/// waveform so corner results can be compared on a single chart.
///
/// Traces are resampled onto the densest source's sweep axis with linear
/// interpolation and renamed "V(out) [corner]" so every corner stays
/// distinguishable.
public struct CornerOverlayBuilder: Sendable {
    /// One corner's contribution to the overlay.
    public struct Source: Sendable {
        public let label: String
        public let waveform: WaveformData

        public init(label: String, waveform: WaveformData) {
            self.label = label
            self.waveform = waveform
        }
    }

    public enum OverlayError: Error, LocalizedError, Equatable {
        case insufficientSources(count: Int)
        case unsupportedAnalysis(AnalysisKind)
        case mixedDomains
        case emptySweep
        case missingVariable(name: String)
        case missingRealValue(variable: Int, point: Int)
        case missingComplexValue(variable: Int, point: Int)

        public var errorDescription: String? {
            switch self {
            case .insufficientSources(let count):
                return "Corner overlay needs at least 2 waveforms, got \(count)"
            case .unsupportedAnalysis(let kind):
                return "Corner overlay does not support \(kind.rawValue) results"
            case .mixedDomains:
                return "Corner overlay requires waveforms of the same analysis type"
            case .emptySweep:
                return "Corner overlay requires non-empty sweeps in every waveform"
            case .missingVariable(let name):
                return "Corner overlay could not find waveform variable '\(name)' in its source waveform"
            case .missingRealValue(let variable, let point):
                return "Corner overlay could not read real value at variable \(variable), point \(point)"
            case .missingComplexValue(let variable, let point):
                return "Corner overlay could not read complex value at variable \(variable), point \(point)"
            }
        }
    }

    public init() {}

    public func build(sources: [Source]) throws -> WaveformData {
        guard sources.count >= 2 else {
            throw OverlayError.insufficientSources(count: sources.count)
        }

        let kinds = Set(sources.map { $0.waveform.metadata.analysisType })
        guard kinds.count == 1, let kind = kinds.first else {
            throw OverlayError.mixedDomains
        }
        // Pole-zero sweeps are index-based, not a physical axis; resampling
        // across corners would fabricate meaningless intermediate poles.
        guard kind != .poleZero else {
            throw OverlayError.unsupportedAnalysis(kind)
        }
        guard sources.allSatisfy({ !$0.waveform.sweepValues.isEmpty }) else {
            throw OverlayError.emptySweep
        }

        guard let base = sources.max(by: { $0.waveform.sweepValues.count < $1.waveform.sweepValues.count }) else {
            throw OverlayError.insufficientSources(count: sources.count)
        }
        let axis = base.waveform.sweepValues
        let isComplex = kind.producesComplexData

        var variables: [VariableDescriptor] = []
        var realColumns: [[Double]] = []
        var complexColumns: [[(real: Double, imag: Double)]] = []

        for source in sources {
            let waveform = source.waveform
            for variable in waveform.variables {
                variables.append(VariableDescriptor(
                    name: "\(variable.name) [\(source.label)]",
                    unit: variable.unit,
                    type: variable.type,
                    index: variables.count
                ))

                guard let variableIndex = waveform.variableIndex(named: variable.name) else {
                    throw OverlayError.missingVariable(name: variable.name)
                }

                if isComplex {
                    let column = try axis.map { x -> (real: Double, imag: Double) in
                        let real = try interpolate(x: x, sweep: waveform.sweepValues) { point in
                            try componentValue(waveform, variableIndex: variableIndex, point: point, imaginary: false)
                        }
                        let imag = try interpolate(x: x, sweep: waveform.sweepValues) { point in
                            try componentValue(waveform, variableIndex: variableIndex, point: point, imaginary: true)
                        }
                        return (real: real, imag: imag)
                    }
                    complexColumns.append(column)
                } else {
                    let column = try axis.map { x in
                        try interpolate(x: x, sweep: waveform.sweepValues) { point in
                            try realValue(waveform, variableIndex: variableIndex, point: point)
                        }
                    }
                    realColumns.append(column)
                }
            }
        }

        let metadata = SimulationMetadata(
            title: "Corner Overlay — \(sources.map { $0.label }.joined(separator: ", "))",
            analysisType: kind,
            pointCount: axis.count,
            variableCount: variables.count,
            isComplex: isComplex
        )
        let sweepVariable = base.waveform.sweepVariable

        if isComplex {
            // Column-major (per-variable) → point-major rows.
            let complexData = (0..<axis.count).map { point in
                complexColumns.map { $0[point] }
            }
            return WaveformData(
                metadata: metadata,
                sweepVariable: sweepVariable,
                sweepValues: axis,
                variables: variables,
                complexData: complexData
            )
        }

        let realData = (0..<axis.count).map { point in
            realColumns.map { $0[point] }
        }
        return WaveformData(
            metadata: metadata,
            sweepVariable: sweepVariable,
            sweepValues: axis,
            variables: variables,
            realData: realData
        )
    }

    // MARK: - Value Access

    private func realValue(_ waveform: WaveformData, variableIndex: Int, point: Int) throws -> Double {
        guard let value = waveform.realValue(variable: variableIndex, point: point) else {
            throw OverlayError.missingRealValue(variable: variableIndex, point: point)
        }
        return value
    }

    private func componentValue(
        _ waveform: WaveformData,
        variableIndex: Int,
        point: Int,
        imaginary: Bool
    ) throws -> Double {
        guard let value = waveform.complexValue(variable: variableIndex, point: point) else {
            throw OverlayError.missingComplexValue(variable: variableIndex, point: point)
        }
        return imaginary ? value.imag : value.real
    }

    // MARK: - Interpolation

    /// Binary-search linear interpolation over a monotonic sweep
    /// (ascending or descending), clamping outside the sweep range.
    private func interpolate(x: Double, sweep: [Double], value: (Int) throws -> Double) throws -> Double {
        guard sweep.count > 1 else { return try value(0) }
        let ascending = sweep[0] <= sweep[sweep.count - 1]
        var low = 0
        var high = sweep.count - 1
        if ascending {
            if x <= sweep[0] { return try value(0) }
            if x >= sweep[high] { return try value(high) }
            while high - low > 1 {
                let mid = (low + high) / 2
                if sweep[mid] <= x { low = mid } else { high = mid }
            }
        } else {
            if x >= sweep[0] { return try value(0) }
            if x <= sweep[high] { return try value(high) }
            while high - low > 1 {
                let mid = (low + high) / 2
                if sweep[mid] >= x { low = mid } else { high = mid }
            }
        }
        let x0 = sweep[low]
        let x1 = sweep[high]
        let y0 = try value(low)
        let y1 = try value(high)
        guard x1 != x0 else { return y0 }
        return y0 + (y1 - y0) * ((x - x0) / (x1 - x0))
    }
}
