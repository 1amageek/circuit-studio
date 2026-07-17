import Foundation
import STAEngine
import TimingEngine

/// Runs failure-driven cell sizing against TimingEngine's canonical STA contract.
public struct TimingDrivenClosureLoop: Sendable {
    public enum ClosureError: Error, LocalizedError, Equatable {
        case nonPositiveBudget
        case analysisDidNotComplete(status: String, diagnostics: [String])
        case missingCriticalPath

        public var errorDescription: String? {
            switch self {
            case .nonPositiveBudget:
                return "Timing closure requires maxIterations >= 1."
            case .analysisDidNotComplete(let status, let diagnostics):
                return "Timing analysis ended with status \(status): \(diagnostics.joined(separator: "; "))"
            case .missingCriticalPath:
                return "Timing analysis reported a setup violation without a critical path."
            }
        }
    }

    public struct Iteration: Sendable, Hashable {
        public let index: Int
        public let worstSetupSlack: Double
        public let met: Bool
        public let upsizedInstance: String?
        public let upsizedTo: String?
    }

    public struct Outcome: Sendable {
        public let converged: Bool
        public let iterations: [Iteration]
        public let netlist: SequentialNetlist
        public let result: STAExecutionResult
    }

    private let engine: any STAExecuting
    private let requestBuilder: any STARequestBuilding

    public init(
        engine: any STAExecuting = TimingEngineAPI.makeSTAEngine(),
        requestBuilder: any STARequestBuilding
    ) {
        self.engine = engine
        self.requestBuilder = requestBuilder
    }

    public func close(
        _ netlist: SequentialNetlist,
        maxIterations: Int
    ) async throws -> Outcome {
        guard maxIterations >= 1 else { throw ClosureError.nonPositiveBudget }
        var current = netlist
        var iterations: [Iteration] = []

        for index in 0..<maxIterations {
            let request = try await requestBuilder.makeRequest(for: current, iteration: index)
            let result = try await engine.execute(request)
            try requireCompleted(result)
            let slack = result.payload.worstSetupSlack ?? -.infinity
            if slack >= 0 {
                iterations.append(Iteration(
                    index: index,
                    worstSetupSlack: slack,
                    met: true,
                    upsizedInstance: nil,
                    upsizedTo: nil
                ))
                return Outcome(
                    converged: true,
                    iterations: iterations,
                    netlist: current,
                    result: result
                )
            }

            guard let path = result.payload.criticalPaths.min(by: { $0.slack < $1.slack }) else {
                throw ClosureError.missingCriticalPath
            }
            let candidate = path.stages
                .compactMap { stage -> (stage: STAPathStage, next: (name: String, relativeFactor: Double))? in
                    CellSizing.nextLarger(of: stage.cell).map { (stage, $0) }
                }
                .max(by: { $0.stage.delay < $1.stage.delay })

            guard let candidate else {
                iterations.append(Iteration(
                    index: index,
                    worstSetupSlack: slack,
                    met: false,
                    upsizedInstance: nil,
                    upsizedTo: nil
                ))
                return Outcome(
                    converged: false,
                    iterations: iterations,
                    netlist: current,
                    result: result
                )
            }
            iterations.append(Iteration(
                index: index,
                worstSetupSlack: slack,
                met: false,
                upsizedInstance: candidate.stage.instance,
                upsizedTo: candidate.next.name
            ))
            current = upsize(
                current,
                instance: candidate.stage.instance,
                relativeFactor: candidate.next.relativeFactor,
                newName: candidate.next.name
            )
        }

        let finalRequest = try await requestBuilder.makeRequest(
            for: current,
            iteration: maxIterations
        )
        let finalResult = try await engine.execute(finalRequest)
        try requireCompleted(finalResult)
        return Outcome(
            converged: (finalResult.payload.worstSetupSlack ?? -.infinity) >= 0,
            iterations: iterations,
            netlist: current,
            result: finalResult
        )
    }

    private func requireCompleted(_ result: STAExecutionResult) throws {
        guard result.status == .completed else {
            throw ClosureError.analysisDidNotComplete(
                status: result.status.rawValue,
                diagnostics: result.diagnostics.map(\.summary)
            )
        }
    }

    private func upsize(
        _ netlist: SequentialNetlist,
        instance: String,
        relativeFactor: Double,
        newName: String
    ) -> SequentialNetlist {
        let resized = netlist.combinational.map { instanceRecord -> GateLevelNetlist.Instance in
            guard instanceRecord.name == instance else { return instanceRecord }
            let largerCell = instanceRecord.cell.scaled(
                widthFactor: relativeFactor,
                name: newName
            )
            return GateLevelNetlist.Instance(
                name: instanceRecord.name,
                cell: largerCell,
                netMap: instanceRecord.netMap
            )
        }
        return SequentialNetlist(
            name: netlist.name,
            combinational: resized,
            dffs: netlist.dffs,
            inputs: netlist.inputs,
            outputs: netlist.outputs,
            clock: netlist.clock,
            vpwr: netlist.vpwr,
            vgnd: netlist.vgnd
        )
    }
}
