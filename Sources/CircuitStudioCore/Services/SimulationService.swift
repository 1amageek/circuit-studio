import Foundation
import Synchronization
import CoreSpice
import CoreSpiceIO
import CoreSpiceWaveform

/// Events emitted during simulation.
public enum SimulationEvent: Sendable {
    case started
    case progress(Double, String)
    case waveformUpdate(WaveformData)
    case completed
    case failed(String)
    case cancelled
}

/// Protocol for the simulation service.
public protocol SimulationServiceProtocol: Sendable {
    func runSPICE(
        source: String,
        fileName: String?,
        onWaveformUpdate: (@Sendable (WaveformData) -> Void)?
    ) async throws -> SimulationResult

    func runAnalysis(
        source: String,
        fileName: String?,
        command: AnalysisCommand
    ) async throws -> SimulationResult

    func cancel(jobID: UUID)
    func events(jobID: UUID) -> AsyncStream<SimulationEvent>
}

/// CoreSpice bridge that parses, compiles, binds, and runs simulations.
public final class SimulationService: SimulationServiceProtocol, Sendable {
    private let jobs: Mutex<[UUID: SimulationJob]> = Mutex([:])
    private let continuations: Mutex<[UUID: AsyncStream<SimulationEvent>.Continuation]> = Mutex([:])
    private let _activeJobID: Mutex<UUID?> = Mutex(nil)

    /// The currently running job ID, if any. Used by UI to cancel.
    public var activeJobID: UUID? { _activeJobID.withLock { $0 } }

    public init() {}

    // MARK: - Run from SPICE source (auto-detect analysis)

    public func runSPICE(
        source: String,
        fileName: String?,
        onWaveformUpdate: (@Sendable (WaveformData) -> Void)? = nil
    ) async throws -> SimulationResult {
        let jobID = UUID()
        let experimentID = UUID()
        let token = CancellationToken()

        let job = SimulationJob(
            id: jobID,
            experimentID: experimentID,
            status: .running,
            cancellationToken: token
        )
        jobs.withLock { $0[jobID] = job }
        _activeJobID.withLock { $0 = jobID }
        emit(jobID: jobID, event: .started)

        defer { _activeJobID.withLock { $0 = nil } }

        do {
            let pipeline = try await loadPipeline(source: source, fileName: fileName)
            let command = detectAnalysis(in: pipeline.netlist) ?? .op
            let waveform = try await executeAnalysis(
                command: command,
                pipeline: pipeline,
                cancellation: token,
                jobID: jobID,
                onWaveformUpdate: onWaveformUpdate
            )

            let result = SimulationResult(
                experimentID: experimentID,
                status: .completed,
                finishedAt: Date(),
                waveform: waveform
            )

            jobs.withLock { $0[jobID]?.status = .completed }
            emit(jobID: jobID, event: .completed)
            return result
        } catch let error as StudioError where error == .cancelled {
            jobs.withLock { $0[jobID]?.status = .cancelled }
            emit(jobID: jobID, event: .cancelled)
            throw error
        } catch {
            jobs.withLock { $0[jobID]?.status = .failed }
            emit(jobID: jobID, event: .failed(error.localizedDescription))
            throw error
        }
    }

    // MARK: - Run with explicit analysis command

    public func runAnalysis(
        source: String,
        fileName: String?,
        command: AnalysisCommand
    ) async throws -> SimulationResult {
        let jobID = UUID()
        let experimentID = UUID()
        let token = CancellationToken()

        let job = SimulationJob(
            id: jobID,
            experimentID: experimentID,
            status: .running,
            cancellationToken: token
        )
        jobs.withLock { $0[jobID] = job }
        _activeJobID.withLock { $0 = jobID }
        emit(jobID: jobID, event: .started)

        defer { _activeJobID.withLock { $0 = nil } }

        do {
            let pipeline = try await loadPipeline(source: source, fileName: fileName)
            let waveform = try await executeAnalysis(
                command: command,
                pipeline: pipeline,
                cancellation: token,
                jobID: jobID
            )

            let result = SimulationResult(
                experimentID: experimentID,
                status: .completed,
                finishedAt: Date(),
                waveform: waveform
            )

            jobs.withLock { $0[jobID]?.status = .completed }
            emit(jobID: jobID, event: .completed)
            return result
        } catch let error as StudioError where error == .cancelled {
            jobs.withLock { $0[jobID]?.status = .cancelled }
            emit(jobID: jobID, event: .cancelled)
            throw error
        } catch {
            jobs.withLock { $0[jobID]?.status = .failed }
            emit(jobID: jobID, event: .failed(error.localizedDescription))
            throw error
        }
    }

    public func cancel(jobID: UUID) {
        jobs.withLock { state in
            if let job = state[jobID] {
                job.cancellationToken.cancel()
                state[jobID]?.status = .cancelled
            }
        }
        emit(jobID: jobID, event: .cancelled)
    }

    public func events(jobID: UUID) -> AsyncStream<SimulationEvent> {
        AsyncStream { continuation in
            continuations.withLock { $0[jobID] = continuation }
            continuation.onTermination = { [weak self] _ in
                _ = self?.continuations.withLock { $0.removeValue(forKey: jobID) }
            }
        }
    }

    // MARK: - Internal Pipeline

    private struct Pipeline {
        let netlist: ParsedNetlist
        let ir: CircuitIR
        let plan: ExecutionPlan
        let devices: [any BoundDevice]
        let nodeNameMap: [String: Node]
    }

    private func loadPipeline(source: String, fileName: String?) async throws -> Pipeline {
        let parseResult = await SPICEIO.parse(source, fileName: fileName)
        let netlist: ParsedNetlist
        do {
            netlist = try parseResult.get()
        } catch {
            throw StudioError.parseFailure("\(error)")
        }

        let ir: CircuitIR
        do {
            ir = try SPICEIO.lower(netlist, configuration: .default)
        } catch {
            throw StudioError.loweringFailure("\(error)")
        }

        let compiler = StandardCompiler()
        let plan: ExecutionPlan
        do {
            plan = try compiler.compile(ir: ir)
        } catch {
            throw StudioError.compilationFailure("\(error)")
        }

        let devices: [any BoundDevice]
        do {
            devices = try Self.bindDevices(plan: plan)
        } catch {
            throw StudioError.deviceBindingFailure("\(error)")
        }

        // Build node name → Node mapping from parsed components + IR instances
        let nodeNameMap = Self.buildNodeNameMap(netlist: netlist, ir: ir)

        return Pipeline(netlist: netlist, ir: ir, plan: plan, devices: devices, nodeNameMap: nodeNameMap)
    }

    /// Builds a mapping from node name strings to Node objects.
    /// Uses the parsed netlist component nodes and the corresponding IR instances.
    private static func buildNodeNameMap(netlist: ParsedNetlist, ir: CircuitIR) -> [String: Node] {
        var map: [String: Node] = ["0": .ground, "gnd": .ground]

        // Build an instance lookup by name from the IR
        var irInstanceByName: [String: Instance] = [:]
        for instance in ir.instances {
            irInstanceByName[instance.name.lowercased()] = instance
        }

        // Match parsed components to IR instances by name
        for component in netlist.components {
            guard let irInstance = irInstanceByName[component.name.lowercased()] else {
                continue
            }
            let nodeNames = component.nodes.map(\.name)
            for (name, node) in zip(nodeNames, irInstance.nodes) {
                let normalizedName = name.lowercased()
                if map[normalizedName] == nil {
                    map[normalizedName] = node
                }
            }
        }

        return map
    }

    // MARK: - Analysis Execution

    private func executeAnalysis(
        command: AnalysisCommand,
        pipeline: Pipeline,
        cancellation: CancellationToken,
        jobID: UUID,
        onWaveformUpdate: (@Sendable (WaveformData) -> Void)? = nil
    ) async throws -> WaveformData {
        let plan = pipeline.plan
        let devices = pipeline.devices
        let solver = SparseLUSolver()
        let topology = plan.topology.circuitTopology

        switch command {
        case .op:
            let analysis = DCAnalysis()
            let result = try await analysis.run(
                plan: plan, devices: devices, solver: solver,
                observer: nil, cancellation: cancellation
            )
            return WaveformData.from(dcResult: result, topology: topology, title: "Operating Point")

        case .tran(let spec):
            let config = TransientConfig(
                stopTime: spec.stopTime,
                maxTimeStep: spec.stepTime ?? spec.stopTime / 50.0,
                initialTimeStep: spec.stepTime ?? spec.stopTime / 50.0
            )

            // Pull-based streaming: channel + polling task (decoupled from simulation)
            let channel = TransientProgressChannel()
            let capturedJobID = jobID
            let capturedCallback = onWaveformUpdate
            let variableMap = plan.topology.variableMap

            // Polling task owns the builder (local variable, no sharing).
            // Drains the channel every 200ms and builds incremental WaveformData.
            let pollingTask = Task { [weak self] in
                var builder = TransientWaveformBuilder(variableMap: variableMap)
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .milliseconds(200))
                    } catch {
                        break
                    }
                    if let batch = channel.drain() {
                        builder.appendBatch(timePoints: batch.timePoints, solutions: batch.solutions)
                        let waveform = builder.buildWaveformData()
                        self?.emit(jobID: capturedJobID, event: .waveformUpdate(waveform))
                        capturedCallback?(waveform)
                    }
                }
                // Final drain: capture any data appended after the last poll cycle
                if let batch = channel.drain() {
                    builder.appendBatch(timePoints: batch.timePoints, solutions: batch.solutions)
                    let waveform = builder.buildWaveformData()
                    self?.emit(jobID: capturedJobID, event: .waveformUpdate(waveform))
                    capturedCallback?(waveform)
                }
            }

            let analysis = TransientAnalysis(
                config: config,
                onStepAccepted: { time, solution in
                    channel.append(time: time, solution: solution)
                }
            )

            // Run simulation. Both paths cancel + await the polling task
            // to ensure no callbacks fire after this scope exits.
            do {
                let result = try await analysis.run(
                    plan: plan, devices: devices, solver: solver,
                    observer: nil, cancellation: cancellation
                )
                pollingTask.cancel()
                await pollingTask.value
                return WaveformData.from(transientResult: result, topology: topology, title: "Transient")
            } catch {
                pollingTask.cancel()
                await pollingTask.value
                throw error
            }

        case .ac(let spec):
            let sweep: FrequencySweep
            switch spec.scaleType {
            case .decade:
                sweep = .decade(start: spec.startFrequency, stop: spec.stopFrequency, pointsPerDecade: spec.numberOfPoints)
            case .octave:
                // CoreSpice lacks a native octave sweep; approximate with decade
                sweep = .decade(start: spec.startFrequency, stop: spec.stopFrequency, pointsPerDecade: spec.numberOfPoints)
            case .linear:
                sweep = .linear(start: spec.startFrequency, stop: spec.stopFrequency, points: spec.numberOfPoints)
            }
            let analysis = ACAnalysis(sweep: sweep)
            let result = try await analysis.run(
                plan: plan, devices: devices, solver: solver,
                observer: nil, cancellation: cancellation
            )
            return WaveformData.from(acResult: result, topology: topology, title: "AC")

        case .dcSweep(let spec):
            guard spec.stepValue != 0 else {
                throw StudioError.simulationFailure("DC sweep step cannot be zero")
            }
            let values = strideInclusive(from: spec.startValue, through: spec.stopValue, by: spec.stepValue)
            var results: [DCResult] = []
            results.reserveCapacity(values.count)

            for value in values {
                let overrideDevices = try Self.bindDevices(
                    plan: plan,
                    overrideSource: (spec.source, value)
                )
                let dc = DCAnalysis()
                let result = try await dc.run(
                    plan: plan, devices: overrideDevices, solver: solver,
                    observer: nil, cancellation: cancellation
                )
                results.append(result)
            }

            let sweepResult = SweepResult(parameterName: spec.source, values: values, results: results)
            return WaveformData.from(sweepResult: sweepResult, topology: topology, title: "DC Sweep")

        case .noise(let spec):
            let outputNode = try resolveNode(name: spec.outputNode, pipeline: pipeline)
            let sweep: FrequencySweep
            switch spec.scaleType {
            case .decade:
                sweep = .decade(start: spec.startFrequency, stop: spec.stopFrequency, pointsPerDecade: spec.numberOfPoints)
            case .octave:
                // CoreSpice lacks a native octave sweep; approximate with decade
                sweep = .decade(start: spec.startFrequency, stop: spec.stopFrequency, pointsPerDecade: spec.numberOfPoints)
            case .linear:
                sweep = .linear(start: spec.startFrequency, stop: spec.stopFrequency, points: spec.numberOfPoints)
            }
            let analysis = NoiseAnalysis(
                outputNode: outputNode,
                inputSourceName: spec.inputSource,
                sweep: sweep
            )
            let result = try await analysis.run(
                plan: plan, devices: devices, solver: solver,
                observer: nil, cancellation: cancellation
            )
            return Self.waveformFromNoiseResult(result, title: "Noise")

        case .tf(let spec):
            let outputNode = try resolveNode(name: spec.output, pipeline: pipeline)
            let analysis = TransferFunctionAnalysis(
                outputNode: outputNode,
                inputSourceName: spec.input
            )
            let result = try await analysis.run(
                plan: plan, devices: devices, solver: solver,
                observer: nil, cancellation: cancellation
            )
            return WaveformData.from(transferFunctionResult: result, title: "Transfer Function")

        case .pz(let spec):
            let outputNode = try resolveNode(name: spec.outputNode, pipeline: pipeline)
            let analysis = PoleZeroAnalysis(
                outputNode: outputNode,
                inputSourceName: spec.inputNode
            )
            let result = try await analysis.run(
                plan: plan, devices: devices, solver: solver,
                observer: nil, cancellation: cancellation
            )
            return Self.waveformFromPoleZeroResult(result, title: "Pole-Zero")
        }
    }

    // MARK: - Node Name Resolution

    private func resolveNode(name: String, pipeline: Pipeline) throws -> Node {
        let normalized = name.lowercased()
        if let node = pipeline.nodeNameMap[normalized] {
            return node
        }
        throw StudioError.simulationFailure("Cannot resolve node name '\(name)' to a circuit node")
    }

    // MARK: - WaveformData Conversion for Noise/PoleZero

    private static func waveformFromNoiseResult(_ result: NoiseResult, title: String?) -> WaveformData {
        let pointCount = result.frequencies.count

        var variables: [VariableDescriptor] = []
        var realData: [[Double]] = Array(repeating: [], count: pointCount)

        // Output noise density
        variables.append(VariableDescriptor(
            name: "onoise",
            unit: .volt,
            type: .voltage,
            index: 0
        ))
        // Input-referred noise density
        variables.append(VariableDescriptor(
            name: "inoise",
            unit: .volt,
            type: .voltage,
            index: 1
        ))

        for i in 0..<pointCount {
            realData[i] = [result.outputNoiseDensity[i], result.inputReferredNoiseDensity[i]]
        }

        // Add per-device contributions
        var varIdx = 2
        for contribution in result.deviceContributions {
            variables.append(VariableDescriptor(
                name: "\(contribution.deviceName)_\(contribution.noiseName)",
                unit: .volt,
                type: .voltage,
                index: varIdx
            ))
            for i in 0..<pointCount {
                if i < contribution.spectralDensity.count {
                    realData[i].append(contribution.spectralDensity[i])
                } else {
                    realData[i].append(0)
                }
            }
            varIdx += 1
        }

        let metadata = SimulationMetadata(
            title: title,
            analysisType: .noise,
            pointCount: pointCount,
            variableCount: variables.count
        )

        return WaveformData(
            metadata: metadata,
            sweepVariable: .frequency(),
            sweepValues: result.frequencies,
            variables: variables,
            realData: realData
        )
    }

    private static func waveformFromPoleZeroResult(_ result: PoleZeroResult, title: String?) -> WaveformData {
        let totalPoints = result.poles.count + result.zeros.count
        guard totalPoints > 0 else {
            return WaveformData.empty(analysisType: .poleZero)
        }

        let variables = [
            VariableDescriptor(name: "real", unit: .hertz, type: .voltage, index: 0),
            VariableDescriptor(name: "imag", unit: .hertz, type: .voltage, index: 1),
            VariableDescriptor(name: "isPole", unit: .dimensionless, type: .parameter, index: 2),
        ]

        var sweepValues: [Double] = []
        var realData: [[Double]] = []

        for (i, pole) in result.poles.enumerated() {
            sweepValues.append(Double(i))
            realData.append([pole.real, pole.imag, 1.0])
        }
        for (i, zero) in result.zeros.enumerated() {
            sweepValues.append(Double(result.poles.count + i))
            realData.append([zero.real, zero.imag, 0.0])
        }

        let metadata = SimulationMetadata(
            title: title,
            analysisType: .poleZero,
            pointCount: totalPoints,
            variableCount: 3,
            options: ["dcGain": "\(result.dcGain)"]
        )

        return WaveformData(
            metadata: metadata,
            sweepVariable: VariableDescriptor(name: "index", unit: .dimensionless, type: .parameter, index: 0),
            sweepValues: sweepValues,
            variables: variables,
            realData: realData
        )
    }

    // MARK: - Device Binding

    private static func bindDevices(
        plan: ExecutionPlan,
        overrideSource: (String, Double)? = nil
    ) throws -> [any BoundDevice] {
        let registry = DeviceRegistry.standard()
        var context = BindingContext(
            variableMap: plan.topology.variableMap,
            matrixDimension: plan.topology.dimension
        )

        var devices: [any BoundDevice] = []
        devices.reserveCapacity(plan.ir.instances.count)

        let overrideName = overrideSource?.0.lowercased()
        let overrideValue = overrideSource?.1

        for instance in plan.ir.instances {
            let inst: Instance
            if let overrideName, let overrideValue, instance.name.lowercased() == overrideName {
                var params = instance.parameters
                switch instance.typeName {
                case "vsource":
                    params["v"] = .real(overrideValue)
                case "isource":
                    params["i"] = .real(overrideValue)
                default:
                    params["v"] = .real(overrideValue)
                }
                inst = Instance(
                    name: instance.name,
                    typeName: instance.typeName,
                    nodes: instance.nodes,
                    parameters: params
                )
            } else {
                inst = instance
            }

            guard let desc = registry.descriptor(for: inst.typeName) else {
                throw StudioError.deviceBindingFailure("No descriptor for device type: \(inst.typeName)")
            }
            devices.append(try desc.bind(instance: inst, context: &context))
        }

        return devices
    }

    // MARK: - Analysis Detection from Parsed Netlist

    private func detectAnalysis(in netlist: ParsedNetlist) -> AnalysisCommand? {
        for analysis in netlist.analyses {
            switch analysis {
            case .op:
                return .op

            case .transient(let spec):
                let stop = spec.stopTime.numericValue ?? 1e-6
                let step = spec.stepTime?.numericValue
                return .tran(TranSpec(stopTime: stop, stepTime: step))

            case .ac(let spec):
                let scale: ACScale
                switch spec.scaleType {
                case .decade: scale = .decade
                case .octave: scale = .octave
                case .linear: scale = .linear
                }
                return .ac(ACSpec(
                    scaleType: scale,
                    numberOfPoints: spec.numberOfPoints,
                    startFrequency: spec.startFrequency.numericValue ?? 1.0,
                    stopFrequency: spec.stopFrequency.numericValue ?? 1e6
                ))

            case .dc(let spec):
                let start = spec.startValue.numericValue ?? 0
                let stop = spec.stopValue.numericValue ?? 0
                let step = spec.stepValue.numericValue ?? ((stop - start) / 10.0)
                return .dcSweep(DCSweepSpec(
                    source: spec.source,
                    startValue: start,
                    stopValue: stop,
                    stepValue: step
                ))

            case .noise(let spec):
                let scale: ACScale
                switch spec.scaleType {
                case .decade: scale = .decade
                case .octave: scale = .octave
                case .linear: scale = .linear
                }
                return .noise(NoiseSpec(
                    outputNode: spec.outputNode,
                    referenceNode: spec.referenceNode,
                    inputSource: spec.inputSource,
                    scaleType: scale,
                    numberOfPoints: spec.numberOfPoints,
                    startFrequency: spec.startFrequency.numericValue ?? 1.0,
                    stopFrequency: spec.stopFrequency.numericValue ?? 1e6
                ))

            case .transferFunction(let spec):
                return .tf(TFSpec(output: spec.output, input: spec.input))

            case .poleZero(let spec):
                return .pz(PZSpec(
                    inputNode: spec.inputNode,
                    inputReference: spec.inputReference,
                    outputNode: spec.outputNode,
                    outputReference: spec.outputReference
                ))

            case .monteCarlo, .sensitivity, .fourier:
                continue
            }
        }
        return nil
    }

    // MARK: - Event Emission

    private func emit(jobID: UUID, event: SimulationEvent) {
        let cont = continuations.withLock { conts in
            conts[jobID]
        }
        cont?.yield(event)
    }
}

// MARK: - StudioError Equatable

extension StudioError: Equatable {
    public static func == (lhs: StudioError, rhs: StudioError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled): return true
        case (.parseFailure(let a), .parseFailure(let b)): return a == b
        case (.loweringFailure(let a), .loweringFailure(let b)): return a == b
        case (.compilationFailure(let a), .compilationFailure(let b)): return a == b
        case (.deviceBindingFailure(let a), .deviceBindingFailure(let b)): return a == b
        case (.simulationFailure(let a), .simulationFailure(let b)): return a == b
        case (.convergenceFailure(let a), .convergenceFailure(let b)): return a == b
        case (.designNotFound(let a), .designNotFound(let b)): return a == b
        case (.testbenchNotFound(let a), .testbenchNotFound(let b)): return a == b
        case (.experimentNotFound(let a), .experimentNotFound(let b)): return a == b
        case (.invalidDesign(let a), .invalidDesign(let b)): return a == b
        case (.fileNotFound(let a), .fileNotFound(let b)): return a == b
        case (.fileReadError(let a), .fileReadError(let b)): return a == b
        case (.exportFailure(let a), .exportFailure(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - ParsedParameterValue Helpers

private extension ParsedParameterValue {
    var numericValue: Double? {
        switch self {
        case .numeric(let n): return n
        case .expression(let expr):
            if case .literal(let n) = expr { return n }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Utilities

private func strideInclusive(from start: Double, through stop: Double, by step: Double) -> [Double] {
    guard step != 0 else { return [] }
    var values: [Double] = []
    var current = start
    if step > 0 {
        while current <= stop + step * 0.5 {
            values.append(current)
            current += step
        }
    } else {
        while current >= stop + step * 0.5 {
            values.append(current)
            current += step
        }
    }
    return values
}
