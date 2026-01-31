import CoreSpice
import CoreSpiceWaveform

/// Incrementally builds `WaveformData` from drained batches.
///
/// Variable descriptors are computed once at init and reused for every
/// `buildWaveformData()` call. Each `appendBatch()` appends only the
/// new data points to the accumulated arrays.
///
/// This type is designed to be a local variable inside the polling Task,
/// so it is never shared across concurrency domains.
public struct TransientWaveformBuilder {

    private let sortedVars: [(MNAVariable, Int)]
    private let variables: [VariableDescriptor]
    private var timePoints: [Double] = []
    private var realData: [[Double]] = []

    public init(variableMap: [MNAVariable: Int]) {
        self.sortedVars = variableMap.sorted { $0.value < $1.value }
        var vars: [VariableDescriptor] = []
        vars.reserveCapacity(sortedVars.count)
        for (idx, (mnaVar, _)) in sortedVars.enumerated() {
            switch mnaVar {
            case .nodeVoltage(let node):
                vars.append(VariableDescriptor(
                    name: "V(\(node.id))",
                    unit: .volt,
                    type: .voltage,
                    index: idx
                ))
            case .branchCurrent(let branch):
                vars.append(VariableDescriptor(
                    name: "I(\(branch.id))",
                    unit: .ampere,
                    type: .current,
                    index: idx
                ))
            }
        }
        self.variables = vars
    }

    /// Append a batch of drained data to the accumulated dataset.
    public mutating func appendBatch(timePoints: [Double], solutions: [[Double]]) {
        self.timePoints.append(contentsOf: timePoints)
        self.realData.reserveCapacity(self.realData.count + solutions.count)
        for solution in solutions {
            var point: [Double] = []
            point.reserveCapacity(sortedVars.count)
            for (_, mnaIdx) in sortedVars {
                point.append(mnaIdx < solution.count ? solution[mnaIdx] : 0)
            }
            self.realData.append(point)
        }
    }

    /// Build `WaveformData` from all accumulated data.
    public func buildWaveformData() -> WaveformData {
        let metadata = SimulationMetadata(
            title: "Transient",
            analysisType: .transient,
            pointCount: timePoints.count,
            variableCount: variables.count
        )
        return WaveformData(
            metadata: metadata,
            sweepVariable: .time(),
            sweepValues: timePoints,
            variables: variables,
            realData: realData
        )
    }
}
