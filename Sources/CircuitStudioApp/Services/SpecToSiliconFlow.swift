import Foundation
import LayoutCore
import LayoutTech
import LayoutIO

/// The autonomous spec-to-silicon loop in one call: given an intent (an ACC-4 program +
/// target clock), it closes the functional, timing and physical axes and emits a
/// tapeout-ready GDS plus a machine-checkable `TapeoutEvidenceBundle` — no human in the
/// loop. Functional and timing close with in-process engines (logic sim, CoreSpice STA), so
/// they always run; DRC/LVS close with the real Magic/Netgen toolchain when present, and are
/// recorded honestly (the bundle simply lacks those axes when the tools are absent — never a
/// silent pass). Each claim links the real artifact that backs it.
public struct SpecToSiliconFlow: Sendable {

    public struct Intent: Sendable {
        public let designName: String
        public let program: [ACC4Instruction]
        public let cycles: Int
        public let targetClockPeriod: Double
        public let defaultInputSlew: Double

        public init(designName: String, program: [ACC4Instruction], cycles: Int,
                    targetClockPeriod: Double, defaultInputSlew: Double = 50e-12) {
            self.designName = designName; self.program = program; self.cycles = cycles
            self.targetClockPeriod = targetClockPeriod; self.defaultInputSlew = defaultInputSlew
        }
    }

    public struct Result: Sendable {
        public let bundle: TapeoutEvidenceBundle
        public let gdsPath: URL?
    }

    private let generator = ACC4CPUGenerator()
    private let signoffAvailable: Bool

    /// `runPhysical` lets a caller force-skip the gated DRC/LVS step (e.g. in tool-independent
    /// tests); by default it runs when the toolchain is reachable.
    public init(runPhysical: Bool = true) {
        self.signoffAvailable = runPhysical
    }

    public func run(_ intent: Intent, artifactDirectory: URL) async throws -> Result {
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        var claims: [TapeoutEvidenceBundle.Claim] = []

        // 1) FUNCTIONAL — the gate-level core must match the reference running the program.
        let golden = ACC4Reference().run(intent.program, cycles: intent.cycles)
        let actual = try ACC4Machine().run(intent.program, cycles: intent.cycles)
        let functionalPass = actual == golden.trace
        let traceURL = artifactDirectory.appending(path: "\(intent.designName).trace.json")
        try Data(golden.trace.map { "\($0.pc),\($0.acc)" }.joined(separator: "\n").utf8).write(to: traceURL)
        claims.append(.init(axis: .functional,
                            statement: "gate-level core matches the reference over \(intent.cycles) cycles",
                            passed: functionalPass,
                            measured: functionalPass ? "trace match" : "trace diverged",
                            artifact: traceURL.path))

        // 2) TIMING — characterize, run STA at the target, and validate against full SPICE.
        let library = try await characterize()
        let seq = generator.sequentialNetlist()
        let report = try StaticTimingAnalyzer(library: library)
            .analyze(seq, clockPeriod: intent.targetClockPeriod, defaultInputSlew: intent.defaultInputSlew)
        let validation = try await STAvsSPICEValidator().validate(path: report.criticalPath, in: seq, toleranceFraction: 0.25)
        let timingPass = report.met && validation.agrees
        let reportURL = artifactDirectory.appending(path: "\(intent.designName).timing.json")
        let timingEncoder = JSONEncoder()
        timingEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try timingEncoder.encode(report).write(to: reportURL)
        claims.append(.init(axis: .timing,
                            statement: String(format: "setup/hold met at T=%.0f ps; STA vs SPICE within tolerance",
                                              intent.targetClockPeriod * 1e12),
                            passed: timingPass,
                            measured: String(format: "fmax %.0f MHz, slack %.1f ps, STA/SPICE err %.1f%%",
                                             report.fmaxHz / 1e6, report.worstSetupSlack * 1e12, validation.relativeError * 100),
                            artifact: reportURL.path))

        // 3) PHYSICAL — synthesize the core and sign it off with the real toolchain (gated).
        var gdsURL: URL? = nil
        if signoffAvailable, let signoff = LiveSignoffService.locate() {
            let netlist = generator.gateLevelNetlist(name: intent.designName)
            let synth = Sky130CircuitSynthesizer()
            let doc = try synth.synthesize(netlist)
            let gds = artifactDirectory.appending(path: "\(intent.designName).gds")
            try MaskDataFormatConverter(tech: Sky130LayoutTech.tech()).exportDocument(doc, to: gds, format: .gds)
            let spiceURL = artifactDirectory.appending(path: "\(intent.designName).spice")
            try synth.referenceSPICE(netlist).write(to: spiceURL, atomically: true, encoding: .utf8)
            let review = try await signoff.run(layoutGDS: gds, topCell: intent.designName,
                                               schematicNetlist: spiceURL, artifactDirectory: artifactDirectory)
            gdsURL = gds
            if let drc = review.reports.first(where: { $0.kind == .drc }) {
                claims.append(.init(axis: .drc, statement: "Magic Sky130 DRC clean", passed: drc.passed,
                                    measured: drc.passed ? "0 violations" : "\(drc.diagnostics.count) violations",
                                    artifact: drc.logPath))
            }
            if let lvs = review.reports.first(where: { $0.kind == .lvs }) {
                claims.append(.init(axis: .lvs, statement: "Netgen LVS matches the schematic", passed: lvs.passed,
                                    measured: lvs.passed ? "match" : "mismatch", artifact: lvs.logPath))
            }
        }

        let bundle = TapeoutEvidenceBundle(designName: intent.designName,
                                           targetClockPeriod: intent.targetClockPeriod,
                                           claims: claims, gdsPath: gdsURL?.path)
        let manifestURL = artifactDirectory.appending(path: "\(intent.designName).evidence.json")
        try Data((try bundle.jsonManifest()).utf8).write(to: manifestURL)
        return Result(bundle: bundle, gdsPath: gdsURL)
    }

    private func characterize() async throws -> TimingLibrary {
        let char = CellTimingCharacterizer(inputSlews: [40e-12, 200e-12], outputLoads: [1e-15, 4e-15, 12e-15])
        var lib = TimingLibrary()
        lib.add(try await char.characterize(.inverter(name: "inv")))
        lib.add(try await char.characterize(.nand(name: "nand2", inputs: ["A", "B"])))
        lib.add(try await char.characterize(.nor(name: "nor2", inputs: ["A", "B"])))
        lib.flipFlop = SequentialTiming(
            clkToQRise: .constant(120e-12), clkToQFall: .constant(120e-12),
            qTransitionRise: .constant(40e-12), qTransitionFall: .constant(40e-12),
            setupTime: 30e-12, holdTime: 10e-12,
            dataCapacitance: lib.cells["nand2"]?.inputCapacitance["A"] ?? 1e-15, clockCapacitance: 2e-15)
        return lib
    }
}
