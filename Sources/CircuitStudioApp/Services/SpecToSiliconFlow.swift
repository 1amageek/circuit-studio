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
    public enum FlowError: Error, LocalizedError, Equatable {
        case missingTimingArtifactRecord(String)
        case missingSequentialTimingGridPoint

        public var errorDescription: String? {
            switch self {
            case .missingTimingArtifactRecord(let id):
                return "Timing artifact manifest did not contain required artifact record '\(id)'."
            case .missingSequentialTimingGridPoint:
                return "Sequential timing report does not contain a clock slew and output load grid point."
            }
        }
    }

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
    private let timingLibraryBuilder: any TimingLibraryBuilding
    private let spiceValidator: any TimingPathValidating

    /// `runPhysical` lets a caller force-skip the gated DRC/LVS step (e.g. in tool-independent
    /// tests); by default it runs when the toolchain is reachable.
    public init(
        runPhysical: Bool = true,
        timingLibraryBuilder: any TimingLibraryBuilding = StandardTimingLibraryBuilder(),
        spiceValidator: any TimingPathValidating = STAvsSPICEValidator()
    ) {
        self.signoffAvailable = runPhysical
        self.timingLibraryBuilder = timingLibraryBuilder
        self.spiceValidator = spiceValidator
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

        // 2) TIMING — characterize, run STA at the target, and validate scoped claims against SPICE.
        let runID = intent.designName
        let timingBuild = try await timingLibraryBuilder.buildStandardLibrary(runID: runID)
        let library = timingBuild.library
        let seq = generator.sequentialNetlist()
        let report = try StaticTimingAnalyzer(library: library)
            .analyze(seq, clockPeriod: intent.targetClockPeriod, defaultInputSlew: intent.defaultInputSlew)
        let validation = try await spiceValidator.validate(path: report.criticalPath, in: seq, toleranceFraction: 0.25)
        let ffReportPoint = try sequentialTimingReportPoint(timingBuild.sequentialReport)
        let staArtifact = STAReportArtifact(
            runID: runID,
            designName: intent.designName,
            timingLibraryArtifactID: "timing-library",
            report: report,
            status: report.met ? .passed : .failed
        )
        let validationReport = timingValidationReport(
            runID: runID,
            designName: intent.designName,
            validation: validation
        )
        let timingArtifacts = try TimingArtifactWriter().write(
            runID: runID,
            runDirectory: artifactDirectory,
            technology: timingBuild.sequentialReport.technology,
            library: timingBuild.libraryArtifact,
            staReport: staArtifact,
            combinationalReport: timingBuild.combinationalReport,
            sequentialReport: timingBuild.sequentialReport,
            validationReports: [(
                id: "combinational-path-validation",
                fileName: "combinational-path-spice.json",
                report: validationReport
            )],
            claims: [
                .init(statement: "setup/hold met at target clock", passed: report.met, artifactIDs: ["sta-report", "timing-library"]),
                .init(statement: "combinational STA path agrees with SPICE", passed: validation.agrees, artifactIDs: ["combinational-path-validation"]),
                .init(statement: "flip-flop timing is SPICE-characterized", passed: timingBuild.sequentialReport.status == .passed, artifactIDs: ["sequential-dff-characterization"]),
            ]
        )
        let staURL = try artifactURL(id: "sta-report", in: timingArtifacts, runDirectory: artifactDirectory)
        let validationURL = try artifactURL(id: "combinational-path-validation", in: timingArtifacts, runDirectory: artifactDirectory)
        let sequentialURL = try artifactURL(id: "sequential-dff-characterization", in: timingArtifacts, runDirectory: artifactDirectory)
        claims.append(.init(axis: .timing,
                            statement: String(format: "setup/hold met at T=%.0f ps",
                                            intent.targetClockPeriod * 1e12),
                            passed: report.met,
                            measured: String(format: "fmax %.0f MHz, setup slack %.1f ps, hold slack %.1f ps",
                                             report.fmaxHz / 1e6, report.worstSetupSlack * 1e12, report.worstHoldSlack * 1e12),
                            artifact: staURL.path))
        claims.append(.init(axis: .timing,
                            statement: "combinational STA critical path agrees with SPICE",
                            passed: validation.agrees,
                            measured: String(format: "STA/SPICE combinational delay err %.1f%%", validation.relativeError * 100),
                            artifact: validationURL.path))
        claims.append(.init(axis: .timing,
                            statement: "flip-flop timing is SPICE-characterized",
                            passed: timingBuild.sequentialReport.status == .passed,
                            measured: String(format: "clk2q %.1f/%.1f ps, setup %.1f ps, hold %.1f ps",
                                             timingBuild.sequentialReport.timing.clkToQRise.lookup(inputSlew: ffReportPoint.clockSlew, outputLoad: ffReportPoint.outputLoad) * 1e12,
                                             timingBuild.sequentialReport.timing.clkToQFall.lookup(inputSlew: ffReportPoint.clockSlew, outputLoad: ffReportPoint.outputLoad) * 1e12,
                                             timingBuild.sequentialReport.timing.setupTime * 1e12,
                                             timingBuild.sequentialReport.timing.holdTime * 1e12),
                            artifact: sequentialURL.path))

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

    private func sequentialTimingReportPoint(
        _ report: SequentialTimingCharacterizationReport
    ) throws -> (clockSlew: Double, outputLoad: Double) {
        guard let clockSlew = report.characterizationGrid.clockSlews.first,
              let outputLoad = report.characterizationGrid.outputLoads.first else {
            throw FlowError.missingSequentialTimingGridPoint
        }
        return (clockSlew, outputLoad)
    }

    private func timingValidationReport(
        runID: String,
        designName: String,
        validation: STAvsSPICEValidator.Result
    ) -> TimingValidationReport {
        let absolute = abs(validation.spiceDelay - validation.staDelay)
        return TimingValidationReport(
            scope: .combinationalPath,
            runID: runID,
            designName: designName,
            sourceArtifacts: ["timing-library", "sta-report"],
            comparisons: [
                TimingValidationComparison(
                    id: "critical-combinational-path-delay",
                    metric: "combinationalDelay",
                    predictedSeconds: validation.staDelay,
                    measuredSeconds: validation.spiceDelay,
                    absoluteErrorSeconds: absolute,
                    relativeError: validation.relativeError,
                    tolerance: validation.tolerance,
                    passed: validation.agrees,
                    artifactIDs: ["timing-library", "sta-report"]
                ),
            ],
            status: validation.agrees ? .passed : .failed
        )
    }

    private func artifactURL(
        id: String,
        in result: TimingArtifactWriter.WriteResult,
        runDirectory: URL
    ) throws -> URL {
        guard let record = result.record(id: id) else {
            throw FlowError.missingTimingArtifactRecord(id)
        }
        return runDirectory.appending(path: record.path)
    }
}
