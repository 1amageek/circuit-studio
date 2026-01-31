import Synchronization
import CoreSpice
import CoreSpiceWaveform

/// Pull-based streaming buffer for transient analysis.
///
/// The simulation thread calls `append(time:solution:)` with minimal overhead
/// (Mutex lock + array append). A separate polling timer calls `snapshot()`
/// to build `WaveformData` only when new data is available. This decouples
/// the simulation hot loop from UI-related work.
public final class TransientProgressBuffer: Sendable {

    private struct State {
        var timePoints: [Double] = []
        var solutions: [[Double]] = []
        var lastSnapshotCount: Int = 0
    }

    private let state: Mutex<State>
    private let topology: CircuitTopology
    private let variableMap: [MNAVariable: Int]

    public init(topology: CircuitTopology, variableMap: [MNAVariable: Int]) {
        self.state = Mutex(State())
        self.topology = topology
        self.variableMap = variableMap
    }

    /// Append a single accepted timestep. Called from the simulation thread.
    public func append(time: Double, solution: [Double]) {
        state.withLock { s in
            s.timePoints.append(time)
            s.solutions.append(solution)
        }
    }

    /// Build a WaveformData snapshot if new data has arrived since the last call.
    /// Returns nil if no new data is available.
    public func snapshot() -> WaveformData? {
        let (timePoints, solutions, hasNew) = state.withLock { s in
            let hasNew = s.timePoints.count > s.lastSnapshotCount
            s.lastSnapshotCount = s.timePoints.count
            return (Array(s.timePoints), Array(s.solutions), hasNew)
        }
        guard hasNew, !timePoints.isEmpty else { return nil }
        return buildWaveformData(timePoints: timePoints, solutions: solutions)
    }

    private func buildWaveformData(
        timePoints: [Double],
        solutions: [[Double]]
    ) -> WaveformData {
        let sortedVars = variableMap.sorted { $0.value < $1.value }

        var variables: [VariableDescriptor] = []
        for (idx, (mnaVar, _)) in sortedVars.enumerated() {
            let descriptor: VariableDescriptor
            switch mnaVar {
            case .nodeVoltage(let node):
                descriptor = VariableDescriptor(
                    name: "V(\(node.id))",
                    unit: .volt,
                    type: .voltage,
                    index: idx
                )
            case .branchCurrent(let branch):
                descriptor = VariableDescriptor(
                    name: "I(\(branch.id))",
                    unit: .ampere,
                    type: .current,
                    index: idx
                )
            }
            variables.append(descriptor)
        }

        var realData: [[Double]] = []
        realData.reserveCapacity(solutions.count)
        for solution in solutions {
            var point: [Double] = []
            point.reserveCapacity(sortedVars.count)
            for (_, mnaIdx) in sortedVars {
                if mnaIdx < solution.count {
                    point.append(solution[mnaIdx])
                } else {
                    point.append(0)
                }
            }
            realData.append(point)
        }

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
