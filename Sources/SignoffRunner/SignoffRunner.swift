import Foundation
import CircuitSignoff
import PEXEngine

/// `signoff` — a small, consistent CLI harness for real physical verification.
///
/// Two commands, one "design" concept:
///   signoff doctor                      check the toolchain
///   signoff check  <design> [modifiers] run DRC + LVS + PEX on the design
///
/// A design is referenced either by PDK cell name (`--cell <name>` — the layout
/// and reference schematic are derived automatically) or by files
/// (`--layout <gds> --top-cell <name> --schematic <spice>`). Modifiers:
///   --rc            extract resistance too (default: capacitance only)
///   --corner <id>   PEX corner (default tt)
///   --artifacts <d> artifact directory
///   --json          machine-readable report
///
/// Exit codes: 0 pass · 1 usage/IO · 2 toolchain unavailable · 3 checks failed.
public enum SignoffCommand {

    public static func run(
        arguments args: [String],
        output: SignoffCommandOutput = .standard,
        runtime: any SignoffCommandRuntime = LiveSignoffCommandRuntime()
    ) async -> Int32 {
        let options = SignoffCommandOptions(arguments: Array(args.dropFirst()))
        do {
            switch args.first {
            case "doctor":
                return try runtime.inspectToolchain(options: options, output: output)
            case "check":
                return try await runCheck(options, output: output, runtime: runtime)
            case "iterate":
                return try await runtime.runIteration(options: options, output: output)
            case "-h", "--help", "help", .none:
                usage(output: output)
                return args.first == nil ? 1 : 0
            case .some(let other):
                output.writeStandardErrorLine("error: unknown command '\(other)'")
                usage(output: output)
                return 1
            }
        } catch let error as CLIError {
            output.writeStandardErrorLine("error: \(error.message)")
            return error.code
        } catch let error as PDKCellLayoutService.LayoutError {
            // Materializing the cell failed (bad cell name / Magic error): a setup
            // problem, not a design that failed its checks — exit 2, never 3.
            output.writeStandardErrorLine("error: \(error.localizedDescription)")
            return 2
        } catch let error as MagicLayoutExtractor.ExtractionError {
            // The LVS-netlist extraction failed: again a tooling/setup problem, not
            // a DRC/LVS verdict — exit 2.
            output.writeStandardErrorLine("error: \(error.localizedDescription)")
            return 2
        } catch {
            output.writeStandardErrorLine("error: \(error.localizedDescription)")
            return 3
        }
    }

    // MARK: - doctor

    static func inspectLiveToolchain(
        _ options: SignoffCommandOptions,
        output: SignoffCommandOutput
    ) throws -> Int32 {
        let drc = MagicDRCSignoff.locate()
        let lvs = NetgenLVSSignoff.locate()
        let pex = MagicToolchain.locate()
        // `check --cell` also needs the PDK standard-cell SPICE deck to derive a
        // reference schematic; verify it here so Ready is not an over-promise.
        let schematics = PDKSchematicProvider.locate()?.hasLibraryDeck() ?? false
        let ok = drc != nil && lvs != nil && pex != nil && schematics
        if options.contains("--json") {
            try emitJSON([
                "magicDRC": drc != nil, "netgenLVS": lvs != nil, "magicPEX": pex != nil,
                "pdkSchematics": schematics, "ready": ok,
            ], output: output)
        } else {
            output.writeStandardOutputLine("Signoff toolchain:")
            output.writeStandardOutputLine("  Magic DRC      : \(drc != nil ? "found" : "MISSING")")
            output.writeStandardOutputLine("  Netgen LVS     : \(lvs != nil ? "found" : "MISSING")")
            output.writeStandardOutputLine("  Magic PEX      : \(pex != nil ? "found" : "MISSING")")
            output.writeStandardOutputLine("  PDK schematics : \(schematics ? "found" : "MISSING")")
            if let drc { output.writeStandardOutputLine("  PDK_ROOT       : \(drc.pdkRoot)") }
            output.writeStandardOutputLine(ok ? "Ready." : "Toolchain incomplete (see docs/TOOLCHAIN.md).")
        }
        return ok ? 0 : 2
    }

    // MARK: - check (DRC + LVS + PEX)

    private static func runCheck(
        _ options: SignoffCommandOptions,
        output: SignoffCommandOutput,
        runtime: any SignoffCommandRuntime
    ) async throws -> Int32 {
        // Batch: --cells a,b,c evaluates each cell consistently and aggregates.
        if let list = options.value("--cells") {
            let cells = parseCellList(list)
            guard !cells.isEmpty else { throw CLIError(code: 1, message: "--cells is empty") }
            var allPassed = true
            for (index, cell) in cells.enumerated() {
                if index > 0 { output.writeStandardOutputLine() }
                var cellOptions = options.replacing("--cell", with: cell)
                // Isolate each cell's artifacts under <dir>/<cell>/ so the per-cell
                // logs don't overwrite each other (without --artifacts each cell
                // already gets its own temp dir).
                if let base = options.value("--artifacts") {
                    cellOptions = cellOptions.replacing(
                        "--artifacts",
                        with: try batchCellArtifactDirectory(base: base, cell: cell)
                    )
                }
                let passed = try await runtime.evaluateDesign(options: cellOptions, output: output)
                allPassed = allPassed && passed
            }
            output.writeStandardOutputLine("\nOverall: \(allPassed ? "PASS" : "FAIL") across \(cells.count) cells")
            return allPassed ? 0 : 3
        }
        return try await runtime.evaluateDesign(options: options, output: output) ? 0 : 3
    }

    /// Runs DRC + LVS + PEX (+ back-annotation) on one design and returns whether
    /// the overall signoff completed cleanly. DRC/LVS remain the primary verdict,
    /// but a PEX failure on an otherwise clean design is still a failed signoff run.
    static func evaluateLiveDesign(
        _ options: SignoffCommandOptions,
        output: SignoffCommandOutput
    ) async throws -> Bool {
        let design = try await resolveDesign(options)
        let rc = options.contains("--rc")
        let corner = options.value("--corner") ?? "tt"

        guard let signoff = LiveSignoffService.locate() else {
            throw CLIError(code: 2, message: "signoff toolchain unavailable — run `signoff doctor`")
        }
        let review = try await signoff.run(
            layoutGDS: design.layoutGDS,
            topCell: design.topCell,
            schematicNetlist: design.schematic,
            artifactDirectory: design.artifacts.appending(path: "signoff")
        )

        // PEX runs AFTER the DRC/LVS verdict so a parasitic-extraction hiccup (a
        // tooling problem) never suppresses or masquerades as the physical-
        // verification verdict. A failed extraction is reported, then surfaced as
        // exit 2 — but only when the design otherwise passed; a real DRC/LVS
        // failure (exit 3) always takes precedence.
        var pex: PEXSummary?
        var pexError: String?
        do {
            pex = try await extractPEX(design: design, rc: rc, corner: corner, output: output)
        } catch let error as CLIError {
            pexError = error.message
        } catch {
            pexError = "PEX extraction failed (\(error.localizedDescription))"
        }

        report(design: design, review: review, pex: pex, pexError: pexError,
               rc: rc, corner: corner, json: options.contains("--json"), output: output)

        if let pexError, review.passed {
            throw CLIError(code: 2, message: pexError)
        }
        return review.passed
    }

    // MARK: - iterate (G4: agent edit -> signoff -> iterate)

    /// Runs the agent edit -> signoff -> iterate loop over a sequence of candidate
    /// cells: each is materialized + given its PDK schematic, then run through real
    /// DRC+LVS; the loop converges on the first candidate that passes. The candidate
    /// list is the agent's proposed fixes (in order).
    static func runLiveIteration(
        _ options: SignoffCommandOptions,
        output: SignoffCommandOutput
    ) async throws -> Int32 {
        guard let list = options.value("--cells") else {
            throw CLIError(code: 1, message: "iterate requires --cells <a,b,c> (the candidate sequence)")
        }
        let cells = parseCellList(list)
        guard !cells.isEmpty else { throw CLIError(code: 1, message: "--cells is empty") }
        let maxIterations = options.value("--max-iterations").flatMap(Int.init) ?? cells.count

        guard let loop = SignoffIterationLoop.locate(),
              let layoutService = PDKCellLayoutService.locate(),
              let provider = PDKSchematicProvider.locate() else {
            throw CLIError(code: 2, message: "signoff toolchain unavailable — run `signoff doctor`")
        }
        let artifacts = options.artifactsDirectory()
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)

        // Materialize each candidate lazily — only when the loop actually reaches it.
        // Converging on candidate 0 never builds the rest, and a later candidate that
        // fails to materialize cannot abort the earlier ones before they are tried.
        let result = try await loop.run(
            maxIterations: maxIterations,
            artifactDirectory: artifacts.appending(path: "iterate")
        ) { index, _ in
            guard index < cells.count else { return nil }
            let cell = cells[index]
            let base = try artifacts.appending(path: artifactPathSegment(forCell: cell))
            let gds = try await layoutService.materialize(cell: cell, into: base.appending(path: "layout"))
            let schematic = try provider.schematic(forCell: cell, into: base.appending(path: "schematic"))
            return SignoffIterationLoop.Candidate(layoutGDS: gds, topCell: cell, schematicNetlist: schematic)
        }

        output.writeStandardOutputLine("iterate (\(cells.count) candidates, max \(maxIterations) iterations)")
        for outcome in result.iterations {
            let verdict = outcome.passed ? "PASS" : "FAIL"
            output.writeStandardOutputLine(
                "  iter \(outcome.index): \(outcome.candidate.topCell) [\(verdict)]"
            )
        }
        if result.converged, let last = result.iterations.last {
            output.writeStandardOutputLine("Converged: \(last.candidate.topCell) passed at iteration \(last.index)")
            return 0
        }
        output.writeStandardOutputLine("Did not converge within \(maxIterations) iterations")
        return 3
    }

    // MARK: - resolution

    private struct Design {
        let topCell: String
        let layoutGDS: URL
        let schematic: URL
        let artifacts: URL
        let materializedByName: Bool
    }

    private static func resolveDesign(_ options: SignoffCommandOptions) async throws -> Design {
        let artifacts = options.artifactsDirectory()
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)

        if let cell = options.value("--cell") {
            guard let layoutService = PDKCellLayoutService.locate() else {
                throw CLIError(code: 2, message: "layout toolchain unavailable — run `signoff doctor`")
            }
            let gds = try await layoutService.materialize(cell: cell, into: artifacts.appending(path: "layout"))
            let schematic: URL
            if let supplied = options.value("--schematic") {
                schematic = URL(filePath: supplied)
            } else {
                guard let provider = PDKSchematicProvider.locate() else {
                    throw CLIError(code: 2, message: "PDK not found to derive a schematic — pass --schematic")
                }
                do {
                    schematic = try provider.schematic(forCell: cell, into: artifacts.appending(path: "schematic"))
                } catch let error as PDKSchematicProvider.SchematicError {
                    // Map a derivation failure to the honest exit code instead of
                    // collapsing every case to the generic exit 3.
                    switch error {
                    case .unrecognizedCellName:
                        throw CLIError(code: 1, message: error.localizedDescription)   // usage
                    case .standardCellLibraryMissing,
                         .standardCellDeckRequirementMissing,
                         .libraryDeckMissing,
                         .subcircuitNotFound:
                        throw CLIError(code: 2, message: error.localizedDescription)   // PDK/setup
                    }
                }
            }
            return Design(topCell: cell, layoutGDS: gds, schematic: schematic,
                          artifacts: artifacts, materializedByName: true)
        }

        // File-referenced design (LVS needs a schematic, so it is required here).
        let layout = try options.fileURL("--layout")
        let topCell = try options.require("--top-cell")
        let schematic = try options.fileURL("--schematic")
        return Design(topCell: topCell, layoutGDS: layout, schematic: schematic,
                      artifacts: artifacts, materializedByName: false)
    }

    // MARK: - PEX

    private struct PEXSummary {
        let elementCount: Int
        let netCount: Int
        let groundCapF: Double
        let couplingCapF: Double
        let resistorCount: Int
        let totalResistanceOhm: Double
        let backAnnotation: ParasiticBackAnnotationService.Result?
    }

    static func overallPassed(reviewPassed: Bool, pexError: String?) -> Bool {
        reviewPassed && pexError == nil
    }

    private static func extractPEX(
        design: Design,
        rc: Bool,
        corner: String,
        output: SignoffCommandOutput
    ) async throws -> PEXSummary {
        guard MagicToolchain.locate() != nil else {
            throw CLIError(code: 2, message: "PEX toolchain unavailable — run `signoff doctor`")
        }
        let pexDir = design.artifacts.appending(path: "pex")
        try FileManager.default.createDirectory(at: pexDir, withIntermediateDirectories: true)
        let netlist = try stagePEXSourceNetlist(from: design.schematic, into: pexDir)
        let tech = TechnologyIR(
            processName: "sky130A", stack: [], logicalToPhysicalLayerMap: [:],
            vias: [], defaultExtractionRules: .default, backendHints: [:]
        )
        let request = PEXRunRequest(
            layoutURL: design.layoutGDS, layoutFormat: .gds,
            sourceNetlistURL: netlist, sourceNetlistFormat: .spice,
            topCell: design.topCell, corners: [PEXCorner(id: corner)],
            technology: .inline(tech),
            backendSelection: PEXBackendSelection(backendID: "magic"),
            options: PEXRunOptions(
                extractMode: rc ? .rc : .cOnly, includeCouplingCaps: true,
                minCapacitanceF: nil, minResistanceOhm: nil, maxParallelJobs: 1,
                emitRawArtifacts: true, emitIRJSON: true, strictValidation: false
            ),
            workingDirectory: pexDir.appending(path: "run")
        )
        let result = try await DefaultPEXEngine.withDefaults().run(request)
        guard result.status == .success, let ir = result.cornerResults.first?.ir else {
            // An extraction failure is a tooling/setup condition (exit 2), not a
            // design defect (exit 3).
            throw CLIError(code: 2, message: "PEX extraction failed (status \(result.status.rawValue))")
        }
        // Back-annotate the extracted capacitance into a CoreSpice RC step and
        // verify the time constant — proving the parasitics simulate correctly.
        // Informational (does not gate DRC/LVS): a sim hiccup is reported on stderr
        // instead of being silently ignored, and is not fatal.
        let backAnnotation: ParasiticBackAnnotationService.Result?
        do {
            backAnnotation = try await ParasiticBackAnnotationService().backAnnotate(ir: ir)
        } catch {
            output.writeStandardErrorLine(
                "warning: back-annotation skipped (\(error.localizedDescription))"
            )
            backAnnotation = nil
        }
        return PEXSummary(
            elementCount: ir.elements.count,
            netCount: ir.nets.count,
            groundCapF: ir.nets.map(\.totalGroundCapF).reduce(0, +),
            couplingCapF: ir.nets.map(\.totalCouplingCapF).reduce(0, +),
            resistorCount: ir.elements.filter { $0.kind == .resistor }.count,
            totalResistanceOhm: ir.nets.map(\.totalResistanceOhm).reduce(0, +),
            backAnnotation: backAnnotation
        )
    }

    static func stagePEXSourceNetlist(from schematic: URL, into pexDirectory: URL) throws -> URL {
        let netlist = pexDirectory.appending(path: "pex-source.cir")
        let data: Data
        do {
            data = try Data(contentsOf: schematic)
        } catch {
            throw CLIError(code: 1, message: "Could not read schematic netlist for PEX: \(error.localizedDescription)")
        }
        try data.write(to: netlist, options: .atomic)
        return netlist
    }

    // MARK: - report

    private static func report(
        design: Design,
        review: ExternalSignoffReview,
        pex: PEXSummary?,
        pexError: String?,
        rc: Bool,
        corner: String,
        json: Bool,
        output: SignoffCommandOutput
    ) {
        let drc = review.reports.first { $0.kind == .drc }?.passed ?? false
        let lvs = review.reports.first { $0.kind == .lvs }?.passed ?? false
        let overall = overallPassed(reviewPassed: review.passed, pexError: pexError)
        if json {
            var obj: [String: Any] = [
                "cell": design.topCell, "drc": drc, "lvs": lvs, "passed": overall,
            ]
            if let pex {
                var pexObj: [String: Any] = [
                    "corner": corner, "mode": rc ? "RC" : "C",
                    "elements": pex.elementCount, "nets": pex.netCount,
                    "groundCapFF": pex.groundCapF * 1e15, "couplingCapFF": pex.couplingCapF * 1e15,
                ]
                if rc { pexObj["resistors"] = pex.resistorCount; pexObj["totalResistanceOhm"] = pex.totalResistanceOhm }
                if let ba = pex.backAnnotation {
                    pexObj["backAnnotation"] = [
                        "expectedTauS": ba.expectedTauS, "measuredTauS": ba.measuredTauS,
                        "relativeError": ba.relativeError, "consistent": ba.consistent,
                    ]
                }
                obj["pex"] = pexObj
            } else {
                obj["pex"] = ["error": pexError ?? "extraction failed"]
            }
            do {
                try emitJSON(obj, output: output)
            } catch {
                output.writeStandardErrorLine(
                    "error: failed to emit JSON (\(error.localizedDescription))"
                )
            }
            return
        }
        output.writeStandardOutputLine(
            "check \(design.topCell)\(design.materializedByName ? " (materialized + PDK schematic)" : "")"
        )
        output.writeStandardOutputLine("  DRC  [\(drc ? "PASS" : "FAIL")]")
        for d in review.reports.first(where: { $0.kind == .drc })?.diagnostics.filter({ $0.severity == .error }) ?? [] {
            output.writeStandardOutputLine("       - \(d.ruleID ?? "?"): \(d.message)")
        }
        output.writeStandardOutputLine("  LVS  [\(lvs ? "PASS" : "FAIL")]")
        for d in review.reports.first(where: { $0.kind == .lvs })?.diagnostics.filter({ $0.severity == .error }) ?? [] {
            output.writeStandardOutputLine("       - \(d.ruleID ?? "?"): \(d.message)")
        }
        if let pex {
            var pexLine = String(format: "  PEX  %d elements, %d nets, ground %.3f fF, coupling %.3f fF",
                                 pex.elementCount, pex.netCount, pex.groundCapF * 1e15, pex.couplingCapF * 1e15)
            if rc {
                pexLine += String(
                    format: ", %d resistors (Σ %.1f Ω)",
                    pex.resistorCount,
                    pex.totalResistanceOhm
                )
            }
            output.writeStandardOutputLine(pexLine)
            if let ba = pex.backAnnotation {
                output.writeStandardOutputLine(
                    String(
                        format: "  RC   back-annotated τ: R·C %.3f ns vs sim %.3f ns [%@]",
                        ba.expectedTauS * 1e9,
                        ba.measuredTauS * 1e9,
                        ba.consistent ? "consistent" : "INCONSISTENT"
                    )
                )
            }
        } else {
            output.writeStandardOutputLine("  PEX  FAILED: \(pexError ?? "extraction failed")")
        }
        output.writeStandardOutputLine("Result: \(overall ? "PASS" : "FAIL")")
    }

    // MARK: - helpers

    static func parseCellList(_ list: String) -> [String] {
        list.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func batchCellArtifactDirectory(base: String, cell: String) throws -> String {
        try URL(filePath: base)
            .appending(path: artifactPathSegment(forCell: cell))
            .path(percentEncoded: false)
    }

    static func artifactPathSegment(forCell cell: String) throws -> String {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = trimmed.isEmpty
            || trimmed == "."
            || trimmed == ".."
            || trimmed.contains("/")
            || trimmed.contains("\\")
            || trimmed.rangeOfCharacter(from: .controlCharacters) != nil
        guard !invalid else {
            throw CLIError(code: 1, message: "invalid cell name for artifact directory: \(cell)")
        }
        return trimmed
    }

    private static func emitJSON(
        _ object: [String: Any],
        output: SignoffCommandOutput
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        output.writeStandardOutputLine(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func usage(output: SignoffCommandOutput) {
        output.writeStandardOutputLine("""
        signoff — real physical-verification harness (Magic DRC · Netgen LVS · Magic PEX)

        Usage:
          signoff doctor [--json]
          signoff check  --cell <name> [--rc] [--corner <id>] [--artifacts <dir>] [--json]
          signoff check  --cells <a,b,c> [--rc] [...]     (batch: evaluate each cell)
          signoff check  --layout <gds> --top-cell <name> --schematic <spice> [--rc] [...]
          signoff iterate --cells <a,b,c> [--max-iterations N] [--artifacts <dir>]

        --cell derives the layout (materialized) and the reference schematic from the PDK.
        check always runs DRC + LVS + PEX.  --rc extracts resistance too.
        iterate runs the candidate cells through DRC+LVS in order and converges on
        the first that passes (the agent edit -> signoff -> iterate loop).

        Exit codes: 0 pass · 1 usage/IO · 2 toolchain unavailable · 3 checks failed
        """)
    }

    public struct CLIError: Error {
        public let code: Int32
        public let message: String

        public init(code: Int32, message: String) {
            self.code = code
            self.message = message
        }
    }
}
