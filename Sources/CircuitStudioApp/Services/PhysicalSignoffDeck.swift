import Foundation

/// Runs the full physical-signoff deck on a synthesized design and folds it into per-axis
/// verdicts + evidence claims. The deck closes the tapeout rule set DRC/LVS alone do not:
/// ERC (electrical integrity), antenna (gate-oxide plasma charge), density (CMP), IR drop and
/// EM (power integrity). Tool-independent axes (ERC, IR, EM) always run via in-process engines;
/// the Magic-gated axes (DRC, LVS, antenna, density) run only when the toolchain is located and
/// are OMITTED otherwise — never a silent fake pass. Each axis links the real artifact behind it.
public struct PhysicalSignoffDeck: Sendable {

    /// The block-level signoff policy. Density enforces the CMP CEILING here (local over-density
    /// is the block hazard); the minimum-density fill is a die-assembly step demonstrated by
    /// `MetalFillInserter`, so the floor defaults to 0 at block level. IR/EM use realistic
    /// Sky130 power-rail limits.
    public struct Policy: Sendable {
        public var densityWindow: DensityWindow
        public var irBudgetFraction: Double
        public var emLimitAmperesPerMeter: Double
        public var powerGrid: PowerGridExtractor

        public init(
            densityWindow: DensityWindow = DensityWindow(minDensity: 0.0, maxDensity: 0.70,
                                                         layers: ["LI", "MET1", "MET2", "MET3", "MET4"]),
            irBudgetFraction: Double = 0.05,
            emLimitAmperesPerMeter: Double = 1000.0,
            powerGrid: PowerGridExtractor = PowerGridExtractor()
        ) {
            self.densityWindow = densityWindow
            self.irBudgetFraction = irBudgetFraction
            self.emLimitAmperesPerMeter = emLimitAmperesPerMeter
            self.powerGrid = powerGrid
        }
    }

    public struct Outcome: Sendable {
        public let verdicts: [ConstraintVerdict]
        public let claims: [TapeoutEvidenceBundle.Claim]
        /// The axes whose tool was absent and were honestly skipped (never faked).
        public let skippedGatedAxes: [ConstraintVerdict.Axis]
    }

    public enum DeckError: Error, LocalizedError {
        case invalidDensityWindow(minDensity: Double, maxDensity: Double)
        case emptyDensityLayers
        case invalidDensityLayer(String)
        case invalidIRBudgetFraction(Double)
        case invalidEMLimit(Double)

        public var errorDescription: String? {
            switch self {
            case .invalidDensityWindow(let minDensity, let maxDensity):
                return "Invalid density window: minDensity=\(minDensity), maxDensity=\(maxDensity)."
            case .emptyDensityLayers:
                return "Density signoff requires at least one layer in the policy."
            case .invalidDensityLayer(let layer):
                return "Invalid density layer name in signoff policy: '\(layer)'."
            case .invalidIRBudgetFraction(let fraction):
                return "IR budget fraction must be finite and in the range (0, 1]: \(fraction)."
            case .invalidEMLimit(let limit):
                return "EM current-density limit must be finite and positive: \(limit)."
            }
        }
    }

    private let policy: Policy
    private let runGatedTools: Bool

    public init(policy: Policy = Policy(), runGatedTools: Bool = true) {
        self.policy = policy
        self.runGatedTools = runGatedTools
    }

    /// Run the deck. `gds` + `schematicNetlist` back the Magic-gated axes; `netlist` backs the
    /// tool-independent ERC / IR / EM. Writes per-axis artifacts under `artifactDirectory`.
    public func run(
        netlist: GateLevelNetlist,
        gds: URL,
        topCell: String,
        schematicNetlist: URL,
        artifactDirectory: URL
    ) async throws -> Outcome {
        try validatePolicy()
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        var verdicts: [ConstraintVerdict] = []
        var claims: [TapeoutEvidenceBundle.Claim] = []
        var skipped: [ConstraintVerdict.Axis] = []

        // --- ERC (tool-independent, always) ---
        let erc = ElectricalRuleChecker().check(netlist)
        let ercArtifact = try publishJSONArtifact(
            erc,
            id: "erc-report",
            kind: "erc-report",
            fileName: "\(topCell).erc.json",
            runDirectory: artifactDirectory
        )
        verdicts.append(MultiConstraintSignoff.erc(erc, evidence: ercArtifact.url.path))
        claims.append(.init(axis: .erc, statement: "no floating inputs, driver fights, or undriven outputs",
                            passed: erc.passed,
                            measured: erc.passed ? "ERC clean" : "\(erc.errors.count) ERC errors",
                            artifact: ercArtifact.evidence,
                            kind: .signoff))

        // --- Power integrity: IR drop + EM (tool-independent, CoreSpice in-process, always) ---
        let grid = policy.powerGrid.extract(netlist)
        let ir = try await IRDropAnalyzer().analyze(grid, budgetFraction: policy.irBudgetFraction)
        let irArtifact = try publishJSONArtifact(
            ir,
            id: "ir-report",
            kind: "ir-report",
            fileName: "\(topCell).ir.json",
            runDirectory: artifactDirectory
        )
        verdicts.append(MultiConstraintSignoff.ir(ir, evidence: irArtifact.url.path))
        claims.append(.init(axis: .ir, statement: "worst-cell IR drop within budget",
                            passed: ir.passed,
                            measured: String(format: "%.1f mV worst at %@ (budget %.1f mV)",
                                             ir.maxIRDropVolts * 1e3, ir.worstTapLabel, ir.budgetVolts * 1e3),
                            artifact: irArtifact.evidence,
                            kind: .signoff))

        let em = ElectromigrationChecker().check(grid, limitAmperesPerMeter: policy.emLimitAmperesPerMeter)
        let emArtifact = try publishJSONArtifact(
            em,
            id: "em-report",
            kind: "em-report",
            fileName: "\(topCell).em.json",
            runDirectory: artifactDirectory
        )
        verdicts.append(MultiConstraintSignoff.em(em, evidence: emArtifact.url.path))
        claims.append(.init(axis: .em, statement: "rail current density within EM limit",
                            passed: em.passed,
                            measured: String(format: "%.0f A/m worst at %@ (limit %.0f A/m)",
                                             em.worstDensity, em.worstSegment ?? "?", em.limitAmperesPerMeter),
                            artifact: emArtifact.evidence,
                            kind: .signoff))

        guard runGatedTools else {
            skipped = [.drc, .lvs, .antenna, .density]
            return Outcome(verdicts: verdicts, claims: claims, skippedGatedAxes: skipped)
        }

        // --- DRC + LVS (Magic/Netgen, gated) ---
        if let signoff = LiveSignoffService.locate() {
            let review = try await signoff.run(layoutGDS: gds, topCell: topCell,
                                               schematicNetlist: schematicNetlist, artifactDirectory: artifactDirectory)
            if let drc = review.reports.first(where: { $0.kind == .drc }) {
                verdicts.append(MultiConstraintSignoff.drc(passed: drc.passed,
                                                           violationCount: drc.diagnostics.count, evidence: drc.logPath))
                let artifact = try existingArtifact(
                    id: "magic-drc-log",
                    kind: "drc-log",
                    path: drc.logPath,
                    runDirectory: artifactDirectory
                )
                claims.append(.init(axis: .drc, statement: "Magic Sky130 DRC clean", passed: drc.passed,
                                    measured: drc.passed ? "0 violations" : "\(drc.diagnostics.count) violations",
                                    artifact: artifact,
                                    kind: .signoff))
            } else { skipped.append(.drc) }
            if let lvs = review.reports.first(where: { $0.kind == .lvs }) {
                verdicts.append(MultiConstraintSignoff.lvs(passed: lvs.passed, evidence: lvs.logPath))
                let artifact = try existingArtifact(
                    id: "netgen-lvs-log",
                    kind: "lvs-log",
                    path: lvs.logPath,
                    runDirectory: artifactDirectory
                )
                claims.append(.init(axis: .lvs, statement: "Netgen LVS matches the schematic", passed: lvs.passed,
                                    measured: lvs.passed ? "match" : "mismatch", artifact: artifact,
                                    kind: .signoff))
            } else { skipped.append(.lvs) }
        } else {
            skipped.append(contentsOf: [.drc, .lvs])
        }

        // --- Antenna (Magic antennacheck, gated) ---
        if let antenna = MagicAntennaSignoff.locate() {
            let result = try await ExternalSignoffCommandService(parser: MagicAntennaSignoff.reportParser).run(
                command: antenna.command(cell: topCell, gds: gds, artifactDirectory: artifactDirectory),
                artifactDirectory: artifactDirectory)
            let report = result.report
            verdicts.append(MultiConstraintSignoff.antenna(passed: report.passed,
                                                           violationCount: report.diagnostics.count, evidence: report.logPath))
            let artifact = try existingArtifact(
                id: "magic-antenna-log",
                kind: "antenna-log",
                path: report.logPath,
                runDirectory: artifactDirectory
            )
            claims.append(.init(axis: .antenna, statement: "no gate-oxide antenna violations", passed: report.passed,
                                measured: report.passed ? "antenna clean" : "\(report.diagnostics.count) antenna violation group(s)",
                                artifact: artifact,
                                kind: .signoff))
        } else {
            skipped.append(.antenna)
        }

        // --- Density (Magic cif coverage, gated) ---
        if let density = MagicDensitySignoff.locate() {
            let report = try await density.run(cell: topCell, gds: gds, window: policy.densityWindow,
                                               artifactDirectory: artifactDirectory)
            verdicts.append(MultiConstraintSignoff.density(report, evidence: report.logPath))
            let artifact = try existingArtifact(
                id: "magic-density-log",
                kind: "density-log",
                path: report.logPath,
                runDirectory: artifactDirectory
            )
            claims.append(.init(axis: .density, statement: "metal density within the CMP window", passed: report.passed,
                                measured: report.summary, artifact: artifact,
                                kind: .signoff))
        } else {
            skipped.append(.density)
        }

        return Outcome(verdicts: verdicts, claims: claims, skippedGatedAxes: skipped)
    }

    private func publishJSONArtifact<T: Encodable>(
        _ value: T,
        id: String,
        kind: String,
        fileName: String,
        runDirectory: URL
    ) throws -> (url: URL, evidence: TapeoutEvidenceArtifact) {
        let record = try ArtifactPublisher(runDirectory: runDirectory).publishJSON(
            value,
            id: id,
            kind: kind,
            relativePath: fileName
        )
        return (runDirectory.appending(path: record.path), TapeoutEvidenceArtifact(publicationRecord: record))
    }

    private func existingArtifact(
        id: String,
        kind: String,
        path: String,
        runDirectory: URL
    ) throws -> TapeoutEvidenceArtifact {
        try TapeoutEvidenceArtifact(
            id: id,
            kind: kind,
            url: URL(fileURLWithPath: path),
            runDirectory: runDirectory
        )
    }

    private func validatePolicy() throws {
        guard policy.irBudgetFraction.isFinite,
              policy.irBudgetFraction > 0,
              policy.irBudgetFraction <= 1 else {
            throw DeckError.invalidIRBudgetFraction(policy.irBudgetFraction)
        }
        guard policy.emLimitAmperesPerMeter.isFinite,
              policy.emLimitAmperesPerMeter > 0 else {
            throw DeckError.invalidEMLimit(policy.emLimitAmperesPerMeter)
        }
        let minDensity = policy.densityWindow.minDensity
        let maxDensity = policy.densityWindow.maxDensity
        guard minDensity.isFinite,
              maxDensity.isFinite,
              minDensity >= 0,
              maxDensity <= 1,
              minDensity <= maxDensity else {
            throw DeckError.invalidDensityWindow(minDensity: minDensity, maxDensity: maxDensity)
        }
        guard !policy.densityWindow.layers.isEmpty else {
            throw DeckError.emptyDensityLayers
        }
        for layer in policy.densityWindow.layers {
            let trimmed = layer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed == layer,
                  !layer.contains(",") else {
                throw DeckError.invalidDensityLayer(layer)
            }
        }
    }
}
