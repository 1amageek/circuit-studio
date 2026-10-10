import Foundation
import Synchronization
import CoreSpice
import CoreSpiceIO
import CoreSpiceWaveform

/// CoreSpice bridge that parses, compiles, binds, and runs simulations.
public final class SimulationService: SimulationRunning, Sendable {
    private struct State: Sendable {
        var jobs: [UUID: SimulationJob] = [:]
        var continuations: [UUID: AsyncStream<SimulationEvent>.Continuation] = [:]
        var activeJobID: UUID?
        var isClosed = false
    }

    private let state = Mutex(State())
    private let externalSimulator = ExternalSpiceSimulator()
    private let transientExecutionLimits: TransientExecutionLimits?

    /// The currently running job ID, if any. Used by UI to cancel.
    public var activeJobID: UUID? { state.withLock { $0.activeJobID } }

    /// Select caller-owned native transient limits explicitly; nil requires a complete deck policy.
    public init(transientExecutionLimits: TransientExecutionLimits?) {
        self.transientExecutionLimits = transientExecutionLimits
    }

    // MARK: - Run from SPICE source (auto-detect analysis)

    public func runSPICE(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration? = nil,
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
        try register(job)
        emit(jobID: jobID, event: .started)

        defer { clearActiveJob(jobID) }

        do {
            if externalSimulator.requiresExternalSimulation(
                source: source,
                fileName: fileName,
                processConfiguration: processConfiguration
            ) {
                let waveform = try await externalSimulator.run(
                    source: source,
                    fileName: fileName,
                    processConfiguration: processConfiguration,
                    command: nil,
                    cancellation: token
                )
                onWaveformUpdate?(waveform)

                let result = SimulationResult(
                    experimentID: experimentID,
                    status: .completed,
                    finishedAt: Date(),
                    waveform: waveform
                )

                emit(jobID: jobID, event: .completed)
                return result
            }

            let pipeline = try await loadPipeline(
                source: source,
                fileName: fileName,
                processConfiguration: processConfiguration
            )
            let command = pipeline.command ?? .op
            let transientExecution = try admitTransient(command: command, options: pipeline.options,
                initialNodeVoltages: pipeline.initialNodeVoltages, nodeVoltageGuesses: pipeline.nodeVoltageGuesses)
            let waveform = try await executeAnalysis(
                command: command,
                pipeline: pipeline,
                transientExecution: transientExecution,
                cancellation: token,
                jobID: jobID,
                onWaveformUpdate: onWaveformUpdate
            )

            let result = SimulationResult(
                experimentID: experimentID,
                status: .completed,
                finishedAt: Date(),
                waveform: waveform,
                logMessages: pipeline.options.diagnostics.map(\.message),
                transientExecutionPolicy: transientExecution?.policy
            )

            emit(jobID: jobID, event: .completed)
            return result
        } catch SPICENativeExecutionError.cancelled {
            emit(jobID: jobID, event: .cancelled)
            throw StudioError.cancelled
        } catch AnalysisError.cancelled {
            emit(jobID: jobID, event: .cancelled)
            throw StudioError.cancelled
        } catch is CancellationError {
            emit(jobID: jobID, event: .cancelled)
            throw StudioError.cancelled
        } catch let error as StudioError where error == .cancelled {
            emit(jobID: jobID, event: .cancelled)
            throw error
        } catch {
            if token.isCancelled || Task.isCancelled {
                emit(jobID: jobID, event: .cancelled)
                throw StudioError.cancelled
            }
            emit(jobID: jobID, event: .failed(error.localizedDescription))
            throw error
        }
    }

    // MARK: - Run with explicit analysis command

    public func runAnalysis(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration? = nil,
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
        try register(job)
        emit(jobID: jobID, event: .started)

        defer { clearActiveJob(jobID) }

        do {
            try validate(command: command, nativeBackend: false)
            if externalSimulator.requiresExternalSimulation(
                source: source,
                fileName: fileName,
                processConfiguration: processConfiguration
            ) {
                let waveform = try await externalSimulator.run(
                    source: source,
                    fileName: fileName,
                    processConfiguration: processConfiguration,
                    command: command,
                    cancellation: token
                )

                let result = SimulationResult(
                    experimentID: experimentID,
                    status: .completed,
                    finishedAt: Date(),
                    waveform: waveform
                )

                emit(jobID: jobID, event: .completed)
                return result
            }

            let pipeline = try await loadPipeline(
                source: source,
                fileName: fileName,
                processConfiguration: processConfiguration,
                command: command
            )
            let transientExecution = try admitTransient(command: command, options: pipeline.options,
                initialNodeVoltages: pipeline.initialNodeVoltages, nodeVoltageGuesses: pipeline.nodeVoltageGuesses)
            let waveform = try await executeAnalysis(
                command: command,
                pipeline: pipeline,
                transientExecution: transientExecution,
                cancellation: token,
                jobID: jobID
            )

            let result = SimulationResult(
                experimentID: experimentID,
                status: .completed,
                finishedAt: Date(),
                waveform: waveform,
                logMessages: pipeline.options.diagnostics.map(\.message),
                transientExecutionPolicy: transientExecution?.policy
            )

            emit(jobID: jobID, event: .completed)
            return result
        } catch SPICENativeExecutionError.cancelled {
            emit(jobID: jobID, event: .cancelled)
            throw StudioError.cancelled
        } catch AnalysisError.cancelled {
            emit(jobID: jobID, event: .cancelled)
            throw StudioError.cancelled
        } catch is CancellationError {
            emit(jobID: jobID, event: .cancelled)
            throw StudioError.cancelled
        } catch let error as StudioError where error == .cancelled {
            emit(jobID: jobID, event: .cancelled)
            throw error
        } catch {
            if token.isCancelled || Task.isCancelled {
                emit(jobID: jobID, event: .cancelled)
                throw StudioError.cancelled
            }
            emit(jobID: jobID, event: .failed(error.localizedDescription))
            throw error
        }
    }

    public func cancel(jobID: UUID) {
        let cancellation = state.withLock { state -> (
            CancellationToken?, AsyncStream<SimulationEvent>.Continuation?
        ) in
            if state.jobs[jobID] != nil {
                state.jobs[jobID]?.status = .cancelled
            }
            return (state.jobs[jobID]?.cancellationToken, state.continuations.removeValue(forKey: jobID))
        }
        cancellation.0?.cancel()
        cancellation.1?.yield(.cancelled)
        cancellation.1?.finish()
    }

    public func events(jobID: UUID) -> AsyncStream<SimulationEvent> {
        AsyncStream { continuation in
            let shouldFinish = state.withLock { state -> Bool in
                guard !state.isClosed else { return true }
                guard state.jobs[jobID]?.status.isTerminal != true else { return true }
                state.continuations[jobID] = continuation
                return false
            }
            continuation.onTermination = { [weak self] _ in
                _ = self?.state.withLock { $0.continuations.removeValue(forKey: jobID) }
            }
            if shouldFinish { continuation.finish() }
        }
    }

    public func shutdown() {
        let resources = state.withLock { state -> (
            [CancellationToken], [AsyncStream<SimulationEvent>.Continuation]
        ) in
            guard !state.isClosed else { return ([], []) }
            state.isClosed = true
            let tokens = state.jobs.values.map(\.cancellationToken)
            for jobID in state.jobs.keys {
                state.jobs[jobID]?.status = .cancelled
            }
            let continuations = Array(state.continuations.values)
            state.continuations.removeAll(keepingCapacity: false)
            state.activeJobID = nil
            return (tokens, continuations)
        }
        for token in resources.0 {
            token.cancel()
        }
        for continuation in resources.1 {
            continuation.finish()
        }
    }

    // MARK: - Internal Pipeline

    private struct Pipeline {
        let netlist: ParsedNetlist
        let options: SPICEAnalysisOptions
        let registry: DeviceRegistry
        let operatingConditions: OperatingConditions
        let ir: CircuitIR
        let lowered: LoweredCircuit
        let command: AnalysisCommand?
        let initialNodeVoltages: [Node: Double]
        let nodeVoltageGuesses: [Node: Double]
        let nodeNameMap: [String: Node]
        let nodeNamesByID: [Int: String]
    }

    private func loadPipeline(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?,
        command: AnalysisCommand? = nil
    ) async throws -> Pipeline {
        let parseResult = await parseNetlist(
            source: source,
            fileName: fileName,
            processConfiguration: processConfiguration
        )
        let netlist: ParsedNetlist
        do {
            netlist = try parseResult.get()
        } catch {
            throw StudioError.parseFailure("\(error)")
        }

        let limits = try StudioNativeExecutionPolicy.resolutionLimits()
        let overrides = processConfiguration?.effectiveParameters() ?? [:]
        let compiled = try NetlistLowering.compile(netlist, additionalOverrideNames: overrides.keys.sorted(), limits: limits)
        var session = try NetlistLowering.beginEvaluation(compiled, profile: StudioNativeExecutionPolicy.profile,
            limits: limits, seed: StudioNativeExecutionPolicy.seed, parameterOverrides: overrides)
        var options = try SPICEAnalysisOptions.resolve(from: compiled, session: &session)
        if let processConfiguration {
            options.temperatureCelsius = processConfiguration.effectiveTemperature(
                defaultValue: options.temperatureCelsius ?? 27)
        }
        let selectedCommand: AnalysisCommand?
        if let command { selectedCommand = command }
        else { selectedCommand = try detectAnalyses(in: compiled, session: &session, firstOnly: true).first }
        if case .noise? = selectedCommand { options.bsim4NoisePreparationRequested = true }
        let registry = options.deviceRegistry()
        let operatingConditions = try options.operatingConditions()
        try session.lower(geometryScale: options.geometryScale)
        guard let emitted = session.circuit else { throw StudioError.simulationFailure("Missing lowered circuit") }
        let resolver = SPICENodeVoltageResolver()
        let initial = try resolver.resolve(.initialConditions, compiled: compiled, session: &session, circuit: emitted)
        let guesses = try resolver.resolve(.nodeSets, compiled: compiled, session: &session, circuit: emitted)
        switch selectedCommand ?? .op {
        case .tran(let spec):
            guard initial.isEmpty || spec.useInitialConditions else {
                throw StudioError.simulationFailure("IC requires transient UIC")
            }
            guard !spec.useInitialConditions || guesses.isEmpty else {
                throw SPICESimulationPreparationError.unsupportedCapability("Nodeset with UIC skips its DC application")
            }
        case .op, .dcSweep:
            guard initial.isEmpty else { throw StudioError.simulationFailure("IC requires transient UIC") }
        default:
            guard initial.isEmpty, guesses.isEmpty else {
                throw StudioError.simulationFailure("Source node voltages are unsupported for this analysis")
            }
        }
        let lowered = try session.finish()
        let ir = lowered.circuit

        // Build node name provenance from parsed components + IR instances.
        let nodeNameMaps = Self.buildNodeNameMaps(netlist: netlist, ir: ir)

        return Pipeline(
            netlist: netlist,
            options: options,
            registry: registry,
            operatingConditions: operatingConditions,
            ir: ir,
            lowered: lowered,
            command: selectedCommand,
            initialNodeVoltages: initial,
            nodeVoltageGuesses: guesses,
            nodeNameMap: nodeNameMaps.nodeByName,
            nodeNamesByID: nodeNameMaps.nameByNodeID
        )
    }

    private func parseNetlist(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration?
    ) async -> ParseResult {
        var parserConfig = ParserConfiguration.default
        let includePaths = processConfiguration?.effectiveIncludePaths() ?? []
        let hasLibraries = (processConfiguration?.technology?.libraries.contains { $0.isEnabled }) == true
        let resolveIncludes = processConfiguration?.resolveIncludes == true
            || hasLibraries
            || !includePaths.isEmpty

        parserConfig.resolveIncludes = resolveIncludes
        parserConfig.includePaths = includePaths
        if let processConfiguration {
            parserConfig.defaultTemperature = processConfiguration.effectiveTemperature(
                defaultValue: parserConfig.defaultTemperature
            )
        }

        let resolver = LocalFileResolver(
            searchPaths: parserConfig.includePaths,
            maxDepth: parserConfig.maxIncludeDepth
        )
        let parser = SPICEParser()
        return await parser.parse(
            source: source,
            fileName: fileName,
            configuration: parserConfig,
            fileResolver: resolver
        )
    }

    /// Builds node-name provenance from parsed netlist nodes and matching IR instances.
    private static func buildNodeNameMaps(
        netlist: ParsedNetlist,
        ir: CircuitIR
    ) -> (nodeByName: [String: Node], nameByNodeID: [Int: String]) {
        var nodeByName: [String: Node] = ["0": .ground, "gnd": .ground]
        var nameByNodeID: [Int: String] = [Node.ground.id: "0"]

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
                if nodeByName[normalizedName] == nil {
                    nodeByName[normalizedName] = node
                }
                if nameByNodeID[node.id] == nil {
                    nameByNodeID[node.id] = name
                }
            }
        }

        return (nodeByName, nameByNodeID)
    }

    private struct TransientExecution {
        let config: TransientConfig
        let convergenceConfig: ConvergenceConfig
        let policy: SimulationTransientExecutionPolicy
    }

    private func admitTransient(command: AnalysisCommand, options: SPICEAnalysisOptions,
        initialNodeVoltages: [Node: Double], nodeVoltageGuesses: [Node: Double]) throws -> TransientExecution? {
        guard case .tran(let spec) = command else { return nil }
        let limits: TransientExecutionLimits
        let source: SimulationTransientExecutionPolicy.Source
        if let deckLimits = options.executionLimits {
            limits = deckLimits
            source = .deckOptions
        } else {
            guard !options.executionLimitOptionsPresent, let callerLimits = transientExecutionLimits else {
                throw TransientExecutionError.missingExecutionLimits
            }
            limits = callerLimits
            source = .caller
        }
        let config = try options.transientConfig(
            executionLimits: limits, stopTime: spec.stopTime, stepTime: spec.stepTime,
            startTime: spec.startTime, maxStep: spec.maxStep,
            useInitialConditions: spec.useInitialConditions,
            initialNodeVoltages: initialNodeVoltages, nodeVoltageGuesses: nodeVoltageGuesses
        )
        return TransientExecution(
            config: config, convergenceConfig: options.convergence,
            policy: SimulationTransientExecutionPolicy(source: source, limits: limits)
        )
    }

    // MARK: - Analysis Execution

    private func validate(command: AnalysisCommand, nativeBackend: Bool) throws {
        switch command {
        case .op, .tf, .pz:
            return

        case .tran(let spec):
            try Self.requirePositiveFinite(spec.stopTime, name: "tran.stopTime")
            if let stepTime = spec.stepTime {
                try Self.requirePositiveFinite(stepTime, name: "tran.stepTime")
            }
            if let maxStep = spec.maxStep {
                try Self.requirePositiveFinite(maxStep, name: "tran.maxStep")
            }
            if let startTime = spec.startTime {
                try Self.requireNonNegativeFinite(startTime, name: "tran.startTime")
                if nativeBackend && startTime != 0 {
                    throw StudioError.simulationFailure(
                        "Native transient analysis does not support a non-zero start time"
                    )
                }
            }

        case .ac(let spec):
            try Self.validateFrequencySweep(
                scaleType: spec.scaleType,
                numberOfPoints: spec.numberOfPoints,
                startFrequency: spec.startFrequency,
                stopFrequency: spec.stopFrequency,
                analysisName: "ac"
            )

        case .dcSweep(let spec):
            try Self.requireFinite(spec.startValue, name: "dc.startValue")
            try Self.requireFinite(spec.stopValue, name: "dc.stopValue")
            try Self.requireFinite(spec.stepValue, name: "dc.stepValue")
            guard spec.stepValue != 0 else {
                throw StudioError.simulationFailure("DC sweep step cannot be zero")
            }
            guard (spec.stopValue - spec.startValue) * spec.stepValue >= 0 else {
                throw StudioError.simulationFailure(
                    "DC sweep step direction must move from startValue toward stopValue"
                )
            }

        case .noise(let spec):
            try Self.validateFrequencySweep(
                scaleType: spec.scaleType,
                numberOfPoints: spec.numberOfPoints,
                startFrequency: spec.startFrequency,
                stopFrequency: spec.stopFrequency,
                analysisName: "noise"
            )
        }
    }

    private static func validateFrequencySweep(
        scaleType: ACScale,
        numberOfPoints: Int,
        startFrequency: Double,
        stopFrequency: Double,
        analysisName: String
    ) throws {
        guard numberOfPoints > 0 else {
            throw StudioError.simulationFailure("\(analysisName) sweep requires at least one point")
        }
        try requirePositiveFinite(startFrequency, name: "\(analysisName).startFrequency")
        try requirePositiveFinite(stopFrequency, name: "\(analysisName).stopFrequency")
        guard stopFrequency >= startFrequency else {
            throw StudioError.simulationFailure(
                "\(analysisName) sweep stopFrequency must be greater than or equal to startFrequency"
            )
        }
    }

    private static func requirePositiveFinite(_ value: Double, name: String) throws {
        guard value > 0, value.isFinite else {
            throw StudioError.simulationFailure("\(name) must be positive and finite")
        }
    }

    private static func requireNonNegativeFinite(_ value: Double, name: String) throws {
        guard value >= 0, value.isFinite else {
            throw StudioError.simulationFailure("\(name) must be non-negative and finite")
        }
    }

    private static func requireFinite(_ value: Double, name: String) throws {
        guard value.isFinite else {
            throw StudioError.simulationFailure("\(name) must be finite")
        }
    }

    private func executeAnalysis(
        command: AnalysisCommand,
        pipeline: Pipeline,
        transientExecution: TransientExecution?,
        cancellation: CancellationToken,
        jobID: UUID,
        onWaveformUpdate: (@Sendable (WaveformData) -> Void)? = nil
    ) async throws -> WaveformData {
        var capabilities: MOSAnalysisCapabilities = [.dc]
        switch command {
        case .ac, .pz: capabilities.insert(.ac)
        case .noise: capabilities.formUnion([.ac, .noise])
        case .tran: capabilities.insert(.transient)
        default: break
        }
        let numerical = try transientExecution?.config.requiredExecutionLimits()
            ?? pipeline.options.executionLimits ?? StudioNativeExecutionPolicy.numericalLimits
        if pipeline.options.bsim4PreparationPolicy == nil,
           let instance = pipeline.lowered.circuit.instances.first(where: { if case .resolved(let resolved) = $0.mos { return resolved.release == .bsim4_4_8_3 }; return false }),
           case .resolved(let resolved) = instance.mos {
            throw BSIM4DeviceError.missingPreparationPolicy(resolved.symbolNames[Int(resolved.selectedName.rawValue)])
        }
        let circuit = try NativeCircuitPreparer().prepare(ir: pipeline.lowered.circuit,
            registry: pipeline.registry, operatingConditions: pipeline.operatingConditions,
            limits: StudioNativeExecutionPolicy.nativeLimits(options: pipeline.options, capabilities: capabilities),
            numericalLimits: numerical, resources: StudioNativeExecutionPolicy.resources())
        let plan = circuit.plan
        let solver = SparseLUSolver()
        let topology = plan.topology.circuitTopology
        let nodeNamesByID = pipeline.nodeNamesByID
        try validate(command: command, nativeBackend: true)
        let convergenceConfig = pipeline.options.convergence

        switch command {
        case .op:
            let analysis = DCAnalysis(config: convergenceConfig, nodeInitialGuess: pipeline.nodeVoltageGuesses)
            let completedRun = try await analysis.run(
                circuit: consume circuit, solver: solver,
                observer: nil, cancellation: cancellation
            )
            defer { withExtendedLifetime(completedRun) {} }
            let result = completedRun.result
            return Self.applyingNodeNames(
                WaveformData.from(dcResult: result, topology: topology, title: "Operating Point"),
                nodeNamesByID: nodeNamesByID
            )

        case .tran:
            guard let transientExecution else {
                throw TransientExecutionError.missingExecutionLimits
            }
            let config = transientExecution.config

            // Pull-based streaming: channel + polling task (decoupled from simulation)
            let channel = TransientProgressChannel()
            let capturedJobID = jobID
            let capturedCallback = onWaveformUpdate
            let variableMap = plan.topology.variableMap

            // Polling task owns the builder (local variable, no sharing).
            // Drains the channel every 200ms and builds incremental WaveformData.
            let pollingTask = Task { [weak self] in
                var builder = TransientWaveformBuilder(
                    variableMap: variableMap,
                    nodeNamesByID: nodeNamesByID
                )
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .milliseconds(200))
                    } catch {
                        break
                    }
                    if let batch = channel.drain() {
                        builder.appendBatch(
                            timePoints: batch.timePoints,
                            rowMajorSolutions: batch.rowMajorSolutions,
                            sourceVariableCount: batch.sourceVariableCount
                        )
                        let waveform = builder.buildWaveformData()
                        self?.emit(jobID: capturedJobID, event: .waveformUpdate(waveform))
                        capturedCallback?(waveform)
                    }
                }
                // Final drain: capture any data appended after the last poll cycle
                if let batch = channel.drain() {
                    builder.appendBatch(
                        timePoints: batch.timePoints,
                        rowMajorSolutions: batch.rowMajorSolutions,
                        sourceVariableCount: batch.sourceVariableCount
                    )
                    let waveform = builder.buildWaveformData()
                    self?.emit(jobID: capturedJobID, event: .waveformUpdate(waveform))
                    capturedCallback?(waveform)
                }
            }

            let analysis = TransientAnalysis(
                config: config,
                convergenceConfig: transientExecution.convergenceConfig,
                onStepAccepted: { time, solution in
                    channel.append(time: time, solution: solution)
                }
            )

            // Run simulation. Both paths cancel + await the polling task
            // to ensure no callbacks fire after this scope exits.
            do {
                let completedRun = try await analysis.run(
                    circuit: consume circuit, solver: solver,
                    observer: nil, cancellation: cancellation
                )
                defer { withExtendedLifetime(completedRun) {} }
                let result = completedRun.result
                pollingTask.cancel()
                await pollingTask.value
                if let progressFailure = channel.takeFailure() {
                    throw progressFailure
                }
                return Self.applyingNodeNames(
                    try WaveformData.from(transientResult: result, topology: topology, title: "Transient"),
                    nodeNamesByID: nodeNamesByID
                )
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
                sweep = .octave(start: spec.startFrequency, stop: spec.stopFrequency, pointsPerOctave: spec.numberOfPoints)
            case .linear:
                sweep = .linear(start: spec.startFrequency, stop: spec.stopFrequency, points: spec.numberOfPoints)
            }
            let analysis = ACAnalysis(sweep: sweep, dcConfig: convergenceConfig)
            let completedRun = try await analysis.run(
                circuit: consume circuit, solver: solver,
                observer: nil, cancellation: cancellation
            )
            defer { withExtendedLifetime(completedRun) {} }
            let result = completedRun.result
            return Self.applyingNodeNames(
                WaveformData.from(acResult: result, topology: topology, title: "AC"),
                nodeNamesByID: nodeNamesByID
            )

        case .dcSweep(let spec):
            guard spec.stepValue != 0 else {
                throw StudioError.simulationFailure("DC sweep step cannot be zero")
            }
            let values = strideInclusive(from: spec.startValue, through: spec.stopValue, by: spec.stepValue)
            let completedSweep = try await DCAnalysis(config: convergenceConfig, nodeInitialGuess: pipeline.nodeVoltageGuesses).runSweep(
                circuit: consume circuit, source: spec.source, values: values,
                solver: solver, observer: nil, cancellation: cancellation)
            defer { withExtendedLifetime(completedSweep) {} }
            let sweepResult = completedSweep.result
            return Self.applyingNodeNames(
                WaveformData.from(sweepResult: sweepResult, topology: topology, title: "DC Sweep"),
                nodeNamesByID: nodeNamesByID
            )

        case .noise(let spec):
            let outputNode = try resolveNode(name: spec.outputNode, pipeline: pipeline)
            let sweep: FrequencySweep
            switch spec.scaleType {
            case .decade:
                sweep = .decade(start: spec.startFrequency, stop: spec.stopFrequency, pointsPerDecade: spec.numberOfPoints)
            case .octave:
                sweep = .octave(start: spec.startFrequency, stop: spec.stopFrequency, pointsPerOctave: spec.numberOfPoints)
            case .linear:
                sweep = .linear(start: spec.startFrequency, stop: spec.stopFrequency, points: spec.numberOfPoints)
            }
            let analysis = NoiseAnalysis(
                outputNode: outputNode,
                inputSourceName: spec.inputSource,
                sweep: sweep,
                dcConfig: convergenceConfig
            )
            let completedRun = try await analysis.run(
                circuit: consume circuit, solver: solver,
                observer: nil, cancellation: cancellation
            )
            defer { withExtendedLifetime(completedRun) {} }
            let result = completedRun.result
            return Self.applyingNodeNames(
                Self.waveformFromNoiseResult(result, title: "Noise"),
                nodeNamesByID: nodeNamesByID
            )

        case .tf(let spec):
            let outputNode = try resolveNode(name: spec.output, pipeline: pipeline)
            let analysis = TransferFunctionAnalysis(
                outputNode: outputNode,
                inputSourceName: spec.input,
                dcConfig: convergenceConfig
            )
            let completedRun = try await analysis.run(
                circuit: consume circuit, solver: solver,
                observer: nil, cancellation: cancellation
            )
            defer { withExtendedLifetime(completedRun) {} }
            let result = completedRun.result
            return Self.applyingNodeNames(
                WaveformData.from(transferFunctionResult: result, title: "Transfer Function"),
                nodeNamesByID: nodeNamesByID
            )

        case .pz(let spec):
            let outputNode = try resolveNode(name: spec.outputNode, pipeline: pipeline)
            let analysis = PoleZeroAnalysis(
                outputNode: outputNode,
                inputSourceName: spec.inputNode,
                dcConfig: convergenceConfig
            )
            let completedRun = try await analysis.run(
                circuit: consume circuit, solver: solver,
                observer: nil, cancellation: cancellation
            )
            defer { withExtendedLifetime(completedRun) {} }
            let result = completedRun.result
            return Self.applyingNodeNames(
                Self.waveformFromPoleZeroResult(result, title: "Pole-Zero"),
                nodeNamesByID: nodeNamesByID
            )
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

    private static func applyingNodeNames(
        _ waveform: WaveformData,
        nodeNamesByID: [Int: String]
    ) -> WaveformData {
        guard !nodeNamesByID.isEmpty else {
            return waveform
        }

        let variables = waveform.variables.map { descriptor in
            guard descriptor.type == .voltage,
                  let nodeID = nodeID(fromVoltageVariableName: descriptor.name),
                  let nodeName = nodeNamesByID[nodeID] else {
                return descriptor
            }
            return VariableDescriptor(
                name: "V(\(nodeName))",
                unit: descriptor.unit,
                type: descriptor.type,
                index: descriptor.index
            )
        }

        guard variables != waveform.variables else {
            return waveform
        }

        if waveform.isComplex {
            var complexData: [[(real: Double, imag: Double)]] = []
            complexData.reserveCapacity(waveform.pointCount)
            for point in 0..<waveform.pointCount {
                var row: [(real: Double, imag: Double)] = []
                row.reserveCapacity(waveform.variableCount)
                for variable in 0..<waveform.variableCount {
                    row.append(waveform.complexValue(variable: variable, point: point) ?? (real: 0, imag: 0))
                }
                complexData.append(row)
            }
            return WaveformData(
                metadata: waveform.metadata,
                sweepVariable: waveform.sweepVariable,
                sweepValues: waveform.sweepValues,
                variables: variables,
                complexData: complexData
            )
        }

        if let rowMajorValues = waveform.realRowMajorValues {
            return WaveformData(
                metadata: waveform.metadata,
                sweepVariable: waveform.sweepVariable,
                sweepValues: waveform.sweepValues,
                variables: variables,
                realRowMajorData: rowMajorValues.values,
                pointCount: rowMajorValues.pointCount,
                variableCount: rowMajorValues.variableCount
            )
        }

        return WaveformData(
            metadata: waveform.metadata,
            sweepVariable: waveform.sweepVariable,
            sweepValues: waveform.sweepValues,
            variables: variables,
            realData: waveform.allRealData ?? []
        )
    }

    private static func nodeID(fromVoltageVariableName name: String) -> Int? {
        guard name.hasPrefix("V("), name.hasSuffix(")") else {
            return nil
        }
        let start = name.index(name.startIndex, offsetBy: 2)
        let end = name.index(before: name.endIndex)
        return Int(name[start..<end])
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

    // MARK: - Analysis Detection from Parsed Netlist

    /// Parses the source and returns every analysis command the netlist
    /// declares, in declaration order. Analyses CoreSpice cannot map
    /// (Monte Carlo, sensitivity, Fourier) are skipped.
    public func detectAnalyses(
        source: String,
        fileName: String?,
        processConfiguration: ProcessConfiguration? = nil
    ) async throws -> [AnalysisCommand] {
        let parseResult = await parseNetlist(
            source: source,
            fileName: fileName,
            processConfiguration: processConfiguration
        )
        let netlist: ParsedNetlist
        do {
            netlist = try parseResult.get()
        } catch {
            throw StudioError.parseFailure("\(error)")
        }
        let limits = try StudioNativeExecutionPolicy.resolutionLimits()
        let overrides = processConfiguration?.effectiveParameters() ?? [:]
        let compiled = try NetlistLowering.compile(netlist, additionalOverrideNames: overrides.keys.sorted(), limits: limits)
        var session = try NetlistLowering.beginEvaluation(compiled, profile: StudioNativeExecutionPolicy.profile,
            limits: limits, seed: StudioNativeExecutionPolicy.seed, parameterOverrides: overrides)
        _ = try SPICEAnalysisOptions.resolve(from: compiled, session: &session)
        return try detectAnalyses(in: compiled, session: &session)
    }

    private func detectAnalyses(in compiled: CompiledNetlist, session: inout NetlistLoweringSession,
                               firstOnly: Bool = false) throws -> [AnalysisCommand] {
        let resolver = AnalysisValueValidator()
        var commands: [AnalysisCommand] = []
        for (index, original) in compiled.source.analyses.enumerated() {
            switch original {
            case .monteCarlo, .sensitivity, .fourier: continue
            default: break
            }
            let analysis = try SPICEAnalysisCommands.resolve(original, at: index, from: compiled, session: &session)
            switch analysis {
            case .op:
                commands.append(.op)

            case .transient(let spec):
                let command = try AnalysisCommand.tran(TranSpec(
                    stopTime: resolver.positiveFinite(spec.stopTime, name: "tran.stopTime"),
                    stepTime: resolver.optionalPositiveFinite(spec.stepTime, name: "tran.stepTime"),
                    startTime: resolver.optionalNonNegativeFinite(spec.startTime, name: "tran.startTime"),
                    maxStep: resolver.optionalPositiveFinite(spec.maxStep, name: "tran.maxStep"),
                    useInitialConditions: spec.useInitialConditions
                ))
                try validate(command: command, nativeBackend: true)
                commands.append(command)

            case .ac(let spec):
                let scale: ACScale
                switch spec.scaleType {
                case .decade: scale = .decade
                case .octave: scale = .octave
                case .linear: scale = .linear
                }
                let command = try AnalysisCommand.ac(ACSpec(
                    scaleType: scale,
                    numberOfPoints: spec.numberOfPoints,
                    startFrequency: resolver.positiveFinite(spec.startFrequency, name: "ac.startFrequency"),
                    stopFrequency: resolver.positiveFinite(spec.stopFrequency, name: "ac.stopFrequency")
                ))
                try validate(command: command, nativeBackend: true)
                commands.append(command)

            case .dc(let spec):
                let command = try AnalysisCommand.dcSweep(DCSweepSpec(
                    source: spec.source,
                    startValue: resolver.finite(spec.startValue, name: "dc.startValue"),
                    stopValue: resolver.finite(spec.stopValue, name: "dc.stopValue"),
                    stepValue: resolver.finite(spec.stepValue, name: "dc.stepValue")
                ))
                try validate(command: command, nativeBackend: true)
                commands.append(command)

            case .noise(let spec):
                let scale: ACScale
                switch spec.scaleType {
                case .decade: scale = .decade
                case .octave: scale = .octave
                case .linear: scale = .linear
                }
                let command = try AnalysisCommand.noise(NoiseSpec(
                    outputNode: spec.outputNode,
                    referenceNode: spec.referenceNode,
                    inputSource: spec.inputSource,
                    scaleType: scale,
                    numberOfPoints: spec.numberOfPoints,
                    startFrequency: resolver.positiveFinite(spec.startFrequency, name: "noise.startFrequency"),
                    stopFrequency: resolver.positiveFinite(spec.stopFrequency, name: "noise.stopFrequency")
                ))
                try validate(command: command, nativeBackend: true)
                commands.append(command)

            case .transferFunction(let spec):
                commands.append(.tf(TFSpec(output: spec.output, input: spec.input)))

            case .poleZero(let spec):
                commands.append(.pz(PZSpec(
                    inputNode: spec.inputNode,
                    inputReference: spec.inputReference,
                    outputNode: spec.outputNode,
                    outputReference: spec.outputReference
                )))

            case .monteCarlo, .sensitivity, .fourier:
                continue
            }
            if firstOnly && !commands.isEmpty { break }
        }
        return commands
    }

    // MARK: - Event Emission

    private func register(_ job: SimulationJob) throws {
        try state.withLock { state in
            guard !state.isClosed else { throw StudioError.simulationServiceClosed }
            guard state.activeJobID == nil else {
                throw StudioError.simulationAlreadyRunning
            }
            state.jobs[job.id] = job
            state.activeJobID = job.id
        }
    }

    private func clearActiveJob(_ jobID: UUID) {
        state.withLock { state in
            if state.activeJobID == jobID {
                state.activeJobID = nil
            }
        }
    }

    private func emit(jobID: UUID, event: SimulationEvent) {
        let continuation = state.withLock { state -> AsyncStream<SimulationEvent>.Continuation? in
            guard !state.isClosed else { return nil }
            if event.isTerminal {
                switch event {
                case .completed:
                    state.jobs[jobID]?.status = .completed
                case .failed:
                    state.jobs[jobID]?.status = .failed
                case .cancelled:
                    state.jobs[jobID]?.status = .cancelled
                case .started, .progress, .waveformUpdate:
                    break
                }
                return state.continuations.removeValue(forKey: jobID)
            }
            return state.continuations[jobID]
        }
        continuation?.yield(event)

        if event.isTerminal {
            continuation?.finish()
        }
    }
}

private extension SimulationEvent {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .started, .progress, .waveformUpdate:
            return false
        }
    }
}

private extension RunStatus {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .pending, .running:
            return false
        }
    }
}

private struct AnalysisValueValidator {
    func finite(_ value: ParsedParameterValue, name: String) throws -> Double {
        let result = try evaluate(value, name: name)
        guard result.isFinite else {
            throw StudioError.simulationFailure("\(name) must be finite")
        }
        return result
    }

    func positiveFinite(_ value: ParsedParameterValue, name: String) throws -> Double {
        let result = try finite(value, name: name)
        guard result > 0 else {
            throw StudioError.simulationFailure("\(name) must be positive and finite")
        }
        return result
    }

    func optionalPositiveFinite(_ value: ParsedParameterValue?, name: String) throws -> Double? {
        guard let value else { return nil }
        return try positiveFinite(value, name: name)
    }

    func optionalNonNegativeFinite(_ value: ParsedParameterValue?, name: String) throws -> Double? {
        guard let value else { return nil }
        let result = try finite(value, name: name)
        guard result >= 0 else {
            throw StudioError.simulationFailure("\(name) must be non-negative and finite")
        }
        return result
    }

    private func evaluate(_ value: ParsedParameterValue, name: String) throws -> Double {
        guard case .numeric(let number) = value else {
            throw StudioError.simulationFailure("Unresolved static analysis value '\(name)'")
        }
        return number
    }
}

// MARK: - StudioError Equatable

extension StudioError: Equatable {
    public static func == (lhs: StudioError, rhs: StudioError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled): return true
        case (.simulationAlreadyRunning, .simulationAlreadyRunning): return true
        case (.simulationServiceClosed, .simulationServiceClosed): return true
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
