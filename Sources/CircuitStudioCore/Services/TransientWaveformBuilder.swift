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
    private var realRowMajorData: [Double] = []

    public init(variableMap: [MNAVariable: Int], nodeNamesByID: [Int: String] = [:]) {
        self.sortedVars = variableMap.sorted { $0.value < $1.value }
        var vars: [VariableDescriptor] = []
        vars.reserveCapacity(sortedVars.count)
        for (idx, (mnaVar, _)) in sortedVars.enumerated() {
            switch mnaVar {
            case .nodeVoltage(let node):
                vars.append(VariableDescriptor(
                    name: "V(\(nodeNamesByID[node.id] ?? String(node.id)))",
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

    /// Append a batch of drained row-major source data to the accumulated dataset.
    public mutating func appendBatch(
        timePoints: [Double],
        rowMajorSolutions: [Double],
        sourceVariableCount: Int
    ) {
        self.timePoints.append(contentsOf: timePoints)
        self.realRowMajorData.reserveCapacity(
            self.realRowMajorData.count + (timePoints.count * sortedVars.count)
        )
        guard sourceVariableCount > 0 else {
            self.realRowMajorData.append(
                contentsOf: Array(repeating: 0, count: timePoints.count * sortedVars.count)
            )
            return
        }

        for point in 0..<timePoints.count {
            let sourceOffset = point * sourceVariableCount
            for (_, mnaIdx) in sortedVars {
                let valueOffset = sourceOffset + mnaIdx
                realRowMajorData.append(valueOffset < rowMajorSolutions.count ? rowMajorSolutions[valueOffset] : 0)
            }
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
            realRowMajorData: realRowMajorData,
            pointCount: timePoints.count,
            variableCount: variables.count
        )
    }
}
