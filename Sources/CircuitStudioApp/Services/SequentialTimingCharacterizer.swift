import CircuitStudioCore
import CoreSpiceWaveform
import Foundation

public protocol SequentialTimingCharacterizing: Sendable {
    func characterizeFlipFlop(_ netlist: GateLevelNetlist, cellName: String) async throws -> SequentialTimingCharacterizationReport
}

public struct SequentialTimingCharacterizer: SequentialTimingCharacterizing {
    public enum CharacterizeError: Error, LocalizedError, Equatable {
        case noWaveform(cell: String, metric: String)
        case probeMissing(node: String)
        case edgeNotObserved(cell: String, metric: String)
        case setupHoldSearchFailed(metric: String)
        case invalidGrid(String)
        case unsupportedSequentialTopology(cell: String, reason: String)
        case technologyModelHashMismatch(expectedModelHash: String, actualModelHash: String?)

        public var errorDescription: String? {
            switch self {
            case .noWaveform(let cell, let metric):
                return "CoreSpice produced no waveform characterizing \(cell) \(metric)."
            case .probeMissing(let node):
                return "Sequential characterization waveform is missing probe '\(node)'."
            case .edgeNotObserved(let cell, let metric):
                return "No required edge observed for \(cell) \(metric)."
            case .setupHoldSearchFailed(let metric):
                return "Could not bracket a passing setup/hold timing point for \(metric)."
            case .invalidGrid(let detail):
                return "Invalid sequential characterization grid: \(detail)."
            case .unsupportedSequentialTopology(let cell, let reason):
                return "Sequential characterization only supports the generated DFF topology for \(cell): \(reason)."
            case .technologyModelHashMismatch(let expected, let actual):
                return "Sequential characterization technology context used device model hash \(actual ?? "nil"), expected \(expected)."
            }
        }
    }

    private struct TrialResult {
        let captured: Bool
        let deck: String
        let waveform: WaveformData
    }

    private struct Clocking {
        let firstClockStart: Double
        let secondClockStart: Double
        let clockEdgeTime: Double
        let dataEdgeTime: Double
        let clockHigh: Double
        let period: Double
        let settle: Double

        var secondClockMid: Double { secondClockStart + clockEdgeTime / 2 }
        var stop: Double { secondClockStart + clockEdgeTime + settle }
    }

    private let model: Level1DeviceModel
    private let simulation: any SimulationRunning
    private let clockSlew: Double
    private let dataSlew: Double
    private let outputLoads: [Double]
    private let setupHoldSearchWindow: Double
    private let setupHoldSearchResolution: Double
    private let maxSearchIterations: Int
    private let technologyContext: TimingTechnologyContext

    public init(
        model: Level1DeviceModel,
        technologyContext: TimingTechnologyContext? = nil,
        simulation: any SimulationRunning = SimulationService(),
        clockSlew: Double = 80e-12,
        dataSlew: Double = 80e-12,
        outputLoads: [Double] = [1e-15, 4e-15, 12e-15],
        setupHoldSearchWindow: Double = 600e-12,
        setupHoldSearchResolution: Double = 5e-12,
        maxSearchIterations: Int = 8
    ) throws {
        let resolvedTechnologyContext: TimingTechnologyContext
        if let technologyContext {
            resolvedTechnologyContext = technologyContext
        } else {
            resolvedTechnologyContext = try Level1DeviceModel.technologyContextChecked(for: model)
        }
        self.model = model
        self.technologyContext = resolvedTechnologyContext
        self.simulation = simulation
        self.clockSlew = clockSlew
        self.dataSlew = dataSlew
        self.outputLoads = outputLoads
        self.setupHoldSearchWindow = setupHoldSearchWindow
        self.setupHoldSearchResolution = setupHoldSearchResolution
        self.maxSearchIterations = maxSearchIterations
    }

    public init(
        technologyContext: TimingTechnologyContext? = nil,
        simulation: any SimulationRunning = SimulationService(),
        clockSlew: Double = 80e-12,
        dataSlew: Double = 80e-12,
        outputLoads: [Double] = [1e-15, 4e-15, 12e-15],
        setupHoldSearchWindow: Double = 600e-12,
        setupHoldSearchResolution: Double = 5e-12,
        maxSearchIterations: Int = 8
    ) throws {
        try self.init(
            model: try Level1DeviceModel.loadBundledDefault(),
            technologyContext: technologyContext,
            simulation: simulation,
            clockSlew: clockSlew,
            dataSlew: dataSlew,
            outputLoads: outputLoads,
            setupHoldSearchWindow: setupHoldSearchWindow,
            setupHoldSearchResolution: setupHoldSearchResolution,
            maxSearchIterations: maxSearchIterations
        )
    }

    public func characterizeFlipFlop(
        cellName: String = "dff"
    ) async throws -> SequentialTimingCharacterizationReport {
        try await characterizeFlipFlop(try DFFGenerator().netlist(name: cellName), cellName: cellName)
    }

    public func characterizeFlipFlop(
        _ netlist: GateLevelNetlist,
        cellName: String = "dff"
    ) async throws -> SequentialTimingCharacterizationReport {
        guard !outputLoads.isEmpty else { throw CharacterizeError.invalidGrid("outputLoads must not be empty") }
        guard outputLoads.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw CharacterizeError.invalidGrid("outputLoads must be finite positive values")
        }
        guard let referenceOutputLoad = outputLoads.first else {
            throw CharacterizeError.invalidGrid("outputLoads must not be empty")
        }
        try validateSupportedDFFTopology(netlist)
        let modelHash = try TimingTopologyHasher.hashModel(model)
        let technology = try validatedTechnologyContext(modelHash: modelHash)

        var dRise = [[Double]](), dFall = [[Double]](), tRise = [[Double]](), tFall = [[Double]]()
        var clkToQMeasurements: [SequentialTimingMeasurementSummary] = []
        var qTransitionMeasurements: [SequentialTimingMeasurementSummary] = []

        var riseDelayRow: [Double] = [], fallDelayRow: [Double] = []
        var riseTransitionRow: [Double] = [], fallTransitionRow: [Double] = []
        for load in outputLoads {
            let rise = try await measureClockToQ(netlist, targetValue: true, outputLoad: load, cellName: cellName)
            riseDelayRow.append(rise.delay)
            riseTransitionRow.append(rise.transition)
            clkToQMeasurements.append(.init(
                id: measurementID(.clkToQRise, load: load),
                metric: .clkToQRise,
                clockSlew: clockSlew,
                outputLoad: load,
                valueSeconds: rise.delay,
                method: .thresholdCrossing,
                status: .passed
            ))
            qTransitionMeasurements.append(.init(
                id: measurementID(.qTransitionRise, load: load),
                metric: .qTransitionRise,
                clockSlew: clockSlew,
                outputLoad: load,
                valueSeconds: rise.transition,
                method: .thresholdCrossing,
                status: .passed
            ))

            let fall = try await measureClockToQ(netlist, targetValue: false, outputLoad: load, cellName: cellName)
            fallDelayRow.append(fall.delay)
            fallTransitionRow.append(fall.transition)
            clkToQMeasurements.append(.init(
                id: measurementID(.clkToQFall, load: load),
                metric: .clkToQFall,
                clockSlew: clockSlew,
                outputLoad: load,
                valueSeconds: fall.delay,
                method: .thresholdCrossing,
                status: .passed
            ))
            qTransitionMeasurements.append(.init(
                id: measurementID(.qTransitionFall, load: load),
                metric: .qTransitionFall,
                clockSlew: clockSlew,
                outputLoad: load,
                valueSeconds: fall.transition,
                method: .thresholdCrossing,
                status: .passed
            ))
        }
        dRise.append(riseDelayRow)
        dFall.append(fallDelayRow)
        tRise.append(riseTransitionRow)
        tFall.append(fallTransitionRow)

        let setupRise = try await searchSetup(netlist, targetValue: true, outputLoad: referenceOutputLoad, cellName: cellName)
        let setupFall = try await searchSetup(netlist, targetValue: false, outputLoad: referenceOutputLoad, cellName: cellName)
        let holdRise = try await searchHold(netlist, targetValue: true, outputLoad: referenceOutputLoad, cellName: cellName)
        let holdFall = try await searchHold(netlist, targetValue: false, outputLoad: referenceOutputLoad, cellName: cellName)

        let setupTime = max(setupRise.value, setupFall.value)
        let holdTime = max(holdRise.value, holdFall.value)
        let setupMeasurements = [
            boundarySummary(.setupTime, targetValue: true, result: setupRise),
            boundarySummary(.setupTime, targetValue: false, result: setupFall),
        ]
        let holdMeasurements = [
            boundarySummary(.holdTime, targetValue: true, result: holdRise),
            boundarySummary(.holdTime, targetValue: false, result: holdFall),
        ]

        let timing = SequentialTiming(
            clkToQRise: try TimingLUT(inputSlews: [clockSlew], outputLoads: outputLoads, values: dRise),
            clkToQFall: try TimingLUT(inputSlews: [clockSlew], outputLoads: outputLoads, values: dFall),
            qTransitionRise: try TimingLUT(inputSlews: [clockSlew], outputLoads: outputLoads, values: tRise),
            qTransitionFall: try TimingLUT(inputSlews: [clockSlew], outputLoads: outputLoads, values: tFall),
            setupTime: setupTime,
            holdTime: holdTime,
            dataCapacitance: inputCapacitance(of: netlist, pin: netlist.inputs.first ?? "D"),
            clockCapacitance: inputCapacitance(of: netlist, pin: netlist.inputs.dropFirst().first ?? "CLK")
        )

        let grid = SequentialTimingCharacterizationGrid(
            clockSlews: [clockSlew],
            dataSlews: [dataSlew],
            outputLoads: outputLoads,
            setupHoldSearchResolution: setupHoldSearchResolution,
            setupHoldSearchWindow: setupHoldSearchWindow
        )

        return SequentialTimingCharacterizationReport(
            cellName: cellName,
            topologyHash: try TimingTopologyHasher.hash(netlist),
            activeClockEdge: .rising,
            technology: technology,
            characterizationGrid: grid,
            timing: timing,
            clkToQMeasurements: clkToQMeasurements.sorted { $0.id < $1.id },
            qTransitionMeasurements: qTransitionMeasurements.sorted { $0.id < $1.id },
            setupMeasurements: setupMeasurements,
            holdMeasurements: holdMeasurements,
            status: .passed
        )
    }

    private func validatedTechnologyContext(modelHash: String) throws -> TimingTechnologyContext {
        guard technologyContext.deviceModelHash == modelHash else {
            throw CharacterizeError.technologyModelHashMismatch(
                expectedModelHash: modelHash,
                actualModelHash: technologyContext.deviceModelHash
            )
        }
        return technologyContext
    }

    private func measureClockToQ(
        _ netlist: GateLevelNetlist,
        targetValue: Bool,
        outputLoad: Double,
        cellName: String
    ) async throws -> (delay: Double, transition: Double) {
        let clocking = clocking()
        let setupLead = setupHoldSearchWindow
        let output = try netlist.requirePrimaryOutput()
        let deck = buildCaptureDeck(
            netlist,
            output: output,
            targetValue: targetValue,
            dataLead: setupLead,
            holdOffset: nil,
            outputLoad: outputLoad,
            clocking: clocking
        )
        let result = try await simulation.runAnalysis(
            source: deck,
            fileName: "char-\(cellName)-clktoq-\(targetValue ? "rise" : "fall").cir",
            processConfiguration: nil,
            command: .tran(TranSpec(stopTime: clocking.stop, stepTime: transientStep(), useInitialConditions: true))
        )
        guard let wave = result.waveform else {
            throw CharacterizeError.noWaveform(cell: cellName, metric: targetValue ? "clkToQRise" : "clkToQFall")
        }
        guard let clk = probe(netlist.inputs.dropFirst().first ?? "CLK", in: wave) else {
            throw CharacterizeError.probeMissing(node: netlist.inputs.dropFirst().first ?? "CLK")
        }
        guard let q = probe(output, in: wave) else {
            throw CharacterizeError.probeMissing(node: output)
        }

        let outputDirection: WaveformTiming.Direction = targetValue ? .rising : .falling
        guard let delay = WaveformTiming.propagationDelay(
            inputTimes: clk.sweepValues,
            inputValues: clk.values,
            outputTimes: q.sweepValues,
            outputValues: q.values,
            mid: model.supplyVoltage / 2,
            inputDirection: .rising,
            outputDirection: outputDirection,
            after: clocking.secondClockStart - clocking.clockEdgeTime
        ),
              let transition = WaveformTiming.transition(
                times: q.sweepValues,
                values: q.values,
                lower: 0.2 * model.supplyVoltage,
                upper: 0.8 * model.supplyVoltage,
                direction: outputDirection,
                after: clocking.secondClockStart - clocking.clockEdgeTime
              ) else {
            throw CharacterizeError.edgeNotObserved(cell: cellName, metric: targetValue ? "clkToQRise" : "clkToQFall")
        }
        return (delay, transition)
    }

    private struct BoundaryResult {
        let value: Double
        let passing: Double
        let failing: Double
    }

    private func searchSetup(
        _ netlist: GateLevelNetlist,
        targetValue: Bool,
        outputLoad: Double,
        cellName: String
    ) async throws -> BoundaryResult {
        var low = 0.0
        var high = setupHoldSearchWindow
        if try await setupPasses(netlist, targetValue: targetValue, lead: low, outputLoad: outputLoad) {
            return BoundaryResult(value: 0, passing: 0, failing: 0)
        }
        guard try await setupPasses(netlist, targetValue: targetValue, lead: high, outputLoad: outputLoad) else {
            throw CharacterizeError.setupHoldSearchFailed(metric: "\(cellName).setup")
        }
        for _ in 0..<maxSearchIterations where high - low > setupHoldSearchResolution {
            let mid = (low + high) / 2
            if try await setupPasses(netlist, targetValue: targetValue, lead: mid, outputLoad: outputLoad) {
                high = mid
            } else {
                low = mid
            }
        }
        return BoundaryResult(value: high, passing: high, failing: low)
    }

    private func searchHold(
        _ netlist: GateLevelNetlist,
        targetValue: Bool,
        outputLoad: Double,
        cellName: String
    ) async throws -> BoundaryResult {
        var low = 0.0
        var high = setupHoldSearchWindow
        if try await holdPasses(netlist, targetValue: targetValue, hold: low, outputLoad: outputLoad) {
            return BoundaryResult(value: 0, passing: 0, failing: 0)
        }
        guard try await holdPasses(netlist, targetValue: targetValue, hold: high, outputLoad: outputLoad) else {
            throw CharacterizeError.setupHoldSearchFailed(metric: "\(cellName).hold")
        }
        for _ in 0..<maxSearchIterations where high - low > setupHoldSearchResolution {
            let mid = (low + high) / 2
            if try await holdPasses(netlist, targetValue: targetValue, hold: mid, outputLoad: outputLoad) {
                high = mid
            } else {
                low = mid
            }
        }
        return BoundaryResult(value: high, passing: high, failing: low)
    }

    private func setupPasses(
        _ netlist: GateLevelNetlist,
        targetValue: Bool,
        lead: Double,
        outputLoad: Double
    ) async throws -> Bool {
        let clocking = clocking()
        let output = try netlist.requirePrimaryOutput()
        let deck = buildCaptureDeck(
            netlist,
            output: output,
            targetValue: targetValue,
            dataLead: lead,
            holdOffset: nil,
            outputLoad: outputLoad,
            clocking: clocking
        )
        return try await runBoundaryTrial(
            deck: deck,
            netlist: netlist,
            output: output,
            targetValue: targetValue,
            stop: clocking.stop
        ).captured
    }

    private func holdPasses(
        _ netlist: GateLevelNetlist,
        targetValue: Bool,
        hold: Double,
        outputLoad: Double
    ) async throws -> Bool {
        let clocking = clocking()
        let setupLead = setupHoldSearchWindow
        let output = try netlist.requirePrimaryOutput()
        let deck = buildCaptureDeck(
            netlist,
            output: output,
            targetValue: targetValue,
            dataLead: setupLead,
            holdOffset: hold,
            outputLoad: outputLoad,
            clocking: clocking
        )
        return try await runBoundaryTrial(
            deck: deck,
            netlist: netlist,
            output: output,
            targetValue: targetValue,
            stop: clocking.stop
        ).captured
    }

    private func runBoundaryTrial(
        deck: String,
        netlist: GateLevelNetlist,
        output: String,
        targetValue: Bool,
        stop: Double
    ) async throws -> TrialResult {
        let result = try await simulation.runAnalysis(
            source: deck,
            fileName: "char-dff-boundary.cir",
            processConfiguration: nil,
            command: .tran(TranSpec(stopTime: stop, stepTime: transientStep(), useInitialConditions: true))
        )
        guard let wave = result.waveform else {
            throw CharacterizeError.noWaveform(cell: netlist.name, metric: "setupHold")
        }
        guard let q = probe(output, in: wave) else {
            throw CharacterizeError.probeMissing(node: output)
        }
        let final = q.values.last ?? 0
        return TrialResult(captured: (final >= model.supplyVoltage / 2) == targetValue, deck: deck, waveform: wave)
    }

    private func boundarySummary(
        _ metric: SequentialTimingMetric,
        targetValue: Bool,
        result: BoundaryResult
    ) -> SequentialTimingMeasurementSummary {
        SequentialTimingMeasurementSummary(
            id: "\(metric.rawValue)-\(targetValue ? "rise" : "fall")",
            metric: metric,
            clockSlew: clockSlew,
            dataSlew: dataSlew,
            outputLoad: outputLoads.first,
            valueSeconds: result.value,
            method: .binarySearch,
            status: .passed,
            passingOffsetSeconds: result.passing,
            failingOffsetSeconds: result.failing,
            capturedValue: targetValue,
            expectedValue: targetValue
        )
    }

    private func buildCaptureDeck(
        _ netlist: GateLevelNetlist,
        output: String,
        targetValue: Bool,
        dataLead: Double,
        holdOffset: Double?,
        outputLoad: Double,
        clocking: Clocking
    ) -> String {
        let dataPin = netlist.inputs.first ?? "D"
        let clockPin = netlist.inputs.dropFirst().first ?? "CLK"
        let oldValue = !targetValue
        let vdd = model.supplyVoltage
        let dataRiseStart = clocking.secondClockMid - dataLead - clocking.dataEdgeTime / 2
        let dataHighWidth: Double
        if let holdOffset {
            let dataFallMid = clocking.secondClockMid + holdOffset
            dataHighWidth = max(1e-15, dataFallMid - clocking.dataEdgeTime / 2 - (dataRiseStart + clocking.dataEdgeTime))
        } else {
            dataHighWidth = clocking.stop
        }

        var lines = ["* characterize sequential \(netlist.name)"]
        lines.append("VDD vdd 0 dc \(eng(vdd))")
        lines.append("VCLK \(clockPin) 0 PULSE(0 \(eng(vdd)) \(eng(clocking.firstClockStart)) \(eng(clocking.clockEdgeTime)) \(eng(clocking.clockEdgeTime)) \(eng(clocking.clockHigh)) \(eng(clocking.period)))")
        lines.append("VD \(dataPin) 0 PULSE(\(eng(oldValue ? vdd : 0)) \(eng(targetValue ? vdd : 0)) \(eng(dataRiseStart)) \(eng(clocking.dataEdgeTime)) \(eng(clocking.dataEdgeTime)) \(eng(dataHighWidth)) \(eng(clocking.stop * 2)))")
        lines += emitDevices(netlist)
        lines.append("CL \(output) 0 \(eng(outputLoad))")
        lines += initialStateLines(netlist, output: output, oldValue: oldValue)
        lines.append(model.nmosCard)
        lines.append(model.pmosCard)
        return lines.joined(separator: "\n") + "\n"
    }

    private func emitDevices(_ netlist: GateLevelNetlist) -> [String] {
        var lines: [String] = []
        for inst in netlist.instances {
            for (index, device) in inst.cell.devices.enumerated() {
                let modelName = device.kind == .nmos ? model.nmosModelName : model.pmosModelName
                let bulk = device.kind == .nmos ? "0" : "vdd"
                lines.append("M\(inst.name)_\(index) \(resolve(device.drain, in: inst, netlist: netlist)) \(resolve(device.gate, in: inst, netlist: netlist)) \(resolve(device.source, in: inst, netlist: netlist)) \(bulk) \(modelName) W=\(eng(device.width))u L=\(eng(device.length))u")
            }
        }
        return lines
    }

    private func resolve(_ local: String, in instance: GateLevelNetlist.Instance, netlist: GateLevelNetlist) -> String {
        if local == instance.cell.vpwr { return "vdd" }
        if local == instance.cell.vgnd { return "0" }
        if let mapped = instance.netMap[local] { return mapped }
        return "\(instance.name)_\(local)"
    }

    private func validateSupportedDFFTopology(_ netlist: GateLevelNetlist) throws {
        guard netlist.inputs.count >= 2 else {
            throw CharacterizeError.unsupportedSequentialTopology(
                cell: netlist.name,
                reason: "expected D and CLK inputs plus one Q output"
            )
        }
        let output = try netlist.requirePrimaryOutput()
        let prefix = netlist.name
        let requiredDrivenNets: Set<String> = [
            "\(prefix)_clkb",
            "\(prefix)_m",
            "\(prefix)_m_db",
            "\(prefix)_m_nd",
            "\(prefix)_m_ndb",
            "\(prefix)_m_qb",
            "\(prefix)_s_db",
            "\(prefix)_s_nd",
            "\(prefix)_s_ndb",
            "\(prefix)_s_qb",
            output,
        ]
        let missing = requiredDrivenNets.subtracting(netlist.drivenNets)
        guard missing.isEmpty else {
            throw CharacterizeError.unsupportedSequentialTopology(
                cell: netlist.name,
                reason: "missing generated internal nets \(missing.sorted().joined(separator: ", "))"
            )
        }
    }

    private func inputCapacitance(of netlist: GateLevelNetlist, pin: String) -> Double {
        var total = 0.0
        for inst in netlist.instances {
            for device in inst.cell.devices where resolve(device.gate, in: inst, netlist: netlist) == pin {
                total += model.inputCapacitance(
                    of: CMOSGateNetlist(
                        name: "\(inst.name)_\(device.name)",
                        devices: [device],
                        output: inst.cell.output
                    ),
                    pin: device.gate
                )
            }
        }
        return total
    }

    private func initialStateLines(_ netlist: GateLevelNetlist, output: String, oldValue: Bool) -> [String] {
        let vdd = model.supplyVoltage
        let old = oldValue ? vdd : 0
        let inverted = oldValue ? 0 : vdd
        let high = vdd
        let prefix = netlist.name
        let values: [(String, Double)] = [
            ("\(prefix)_clkb", high),
            ("\(prefix)_m", old),
            ("\(prefix)_m_db", inverted),
            ("\(prefix)_m_nd", inverted),
            ("\(prefix)_m_ndb", old),
            ("\(prefix)_m_qb", inverted),
            ("\(prefix)_s_db", inverted),
            ("\(prefix)_s_nd", high),
            ("\(prefix)_s_ndb", high),
            ("\(prefix)_s_qb", inverted),
            (output, old),
        ]
        return values.flatMap { net, value -> [String] in
            let biasNode = value >= vdd / 2 ? "vdd" : "0"
            return [
                ".nodeset \(net)=\(eng(value))",
                ".ic \(net)=\(eng(value))",
                "CINIT_\(sanitized(net)) \(net) 0 1e-17 ic=\(eng(value))",
                "RINIT_\(sanitized(net)) \(net) \(biasNode) 1e12",
            ]
        }
    }

    private func sanitized(_ net: String) -> String {
        net.map { character in
            character.isLetter || character.isNumber ? character : "_"
        }.map(String.init).joined()
    }

    private func clocking() -> Clocking {
        let clockEdgeTime = max(clockSlew, 5e-12) / 0.6
        let dataEdgeTime = max(dataSlew, 5e-12) / 0.6
        let clockHigh = 1.0e-9
        let period = 4.0e-9
        let firstClockStart = 1.0e-9
        return Clocking(
            firstClockStart: firstClockStart,
            secondClockStart: firstClockStart + period,
            clockEdgeTime: clockEdgeTime,
            dataEdgeTime: dataEdgeTime,
            clockHigh: clockHigh,
            period: period,
            settle: 2.0e-9
        )
    }

    private func transientStep() -> Double {
        max(0.5e-12, min(clockSlew, dataSlew) / 80)
    }

    private func measurementID(_ metric: SequentialTimingMetric, load: Double) -> String {
        "\(metric.rawValue)-load-\(String(format: "%.3e", load))"
    }

    private func probe(_ node: String, in wave: WaveformData) -> RealWaveform? {
        for candidate in [node, "V(\(node))", "v(\(node))", node.lowercased(), node.uppercased()] {
            if let w = wave.realWaveform(named: candidate) { return w }
        }
        let targets: Set<String> = [node.lowercased(), "v(\(node.lowercased()))"]
        if let match = wave.variables.first(where: { targets.contains($0.name.lowercased()) }) {
            return wave.realWaveform(named: match.name)
        }
        return nil
    }

    private func eng(_ value: Double) -> String {
        String(format: "%.6g", value)
    }
}
