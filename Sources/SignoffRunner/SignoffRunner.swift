import Foundation
import CircuitStudioApp
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
@main
struct SignoffRunner {

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let options = Options(args: Array(args.dropFirst()))
        do {
            switch args.first {
            case "doctor":
                exit(try runDoctor(options))
            case "check":
                exit(try await runCheck(options))
            case "iterate":
                exit(try await runIterate(options))
            case "-h", "--help", "help", .none:
                usage()
                exit(args.first == nil ? 1 : 0)
            case .some(let other):
                FileHandle.standardError.write(Data("error: unknown command '\(other)'\n".utf8))
                usage()
                exit(1)
            }
        } catch let error as CLIError {
            FileHandle.standardError.write(Data("error: \(error.message)\n".utf8))
            exit(error.code)
        } catch let error as PDKCellLayoutService.LayoutError {
            // Materializing the cell failed (bad cell name / Magic error): a setup
            // problem, not a design that failed its checks — exit 2, never 3.
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(2)
        } catch let error as MagicLayoutExtractor.ExtractionError {
            // The LVS-netlist extraction failed: again a tooling/setup problem, not
            // a DRC/LVS verdict — exit 2.
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(3)
        }
    }

    // MARK: - doctor

    private static func runDoctor(_ options: Options) throws -> Int32 {
        let drc = MagicDRCSignoff.locate()
        let lvs = NetgenLVSSignoff.locate()
        let pex = MagicToolchain.locate()
        // `check --cell` also needs the PDK standard-cell SPICE deck to derive a
        // reference schematic; verify it here so Ready is not an over-promise.
        let schematics = PDKSchematicProvider.locate()?.hasLibraryDeck() ?? false
        let ok = drc != nil && lvs != nil && pex != nil && schematics
        if options.flag("--json") {
            try emitJSON([
                "magicDRC": drc != nil, "netgenLVS": lvs != nil, "magicPEX": pex != nil,
                "pdkSchematics": schematics, "ready": ok,
            ])
        } else {
            print("Signoff toolchain:")
            print("  Magic DRC      : \(drc != nil ? "found" : "MISSING")")
            print("  Netgen LVS     : \(lvs != nil ? "found" : "MISSING")")
            print("  Magic PEX      : \(pex != nil ? "found" : "MISSING")")
            print("  PDK schematics : \(schematics ? "found" : "MISSING")")
            if let drc { print("  PDK_ROOT       : \(drc.pdkRoot)") }
            print(ok ? "Ready." : "Toolchain incomplete (see docs/TOOLCHAIN.md).")
        }
        return ok ? 0 : 2
    }

    // MARK: - check (DRC + LVS + PEX)

    private static func runCheck(_ options: Options) async throws -> Int32 {
        // Batch: --cells a,b,c evaluates each cell consistently and aggregates.
        if let list = options.value("--cells") {
            let cells = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !cells.isEmpty else { throw CLIError(code: 1, message: "--cells is empty") }
            var allPassed = true
            for (index, cell) in cells.enumerated() {
                if index > 0 { print("") }
                var cellOptions = options.with(key: "--cell", value: cell)
                // Isolate each cell's artifacts under <dir>/<cell>/ so the per-cell
                // logs don't overwrite each other (without --artifacts each cell
                // already gets its own temp dir).
                if let base = options.value("--artifacts") {
                    cellOptions = cellOptions.with(
                        key: "--artifacts",
                        value: URL(filePath: base).appending(path: cell).path(percentEncoded: false)
                    )
                }
                let passed = try await evaluate(cellOptions)
                allPassed = allPassed && passed
            }
            print("\nOverall: \(allPassed ? "PASS" : "FAIL") across \(cells.count) cells")
            return allPassed ? 0 : 3
        }
        return try await evaluate(options) ? 0 : 3
    }

    /// Runs DRC + LVS + PEX (+ back-annotation) on one design and returns whether
    /// the signoff review passed (the single source of truth — `review.passed`).
    private static func evaluate(_ options: Options) async throws -> Bool {
        let design = try resolveDesign(options)
        let rc = options.flag("--rc")
        let corner = options.value("--corner") ?? "tt"

        let review: ExternalSignoffReview
        do {
            review = try await DesignFlowService().runLiveSignoff(
                layoutGDS: design.layoutGDS, topCell: design.topCell,
                schematicNetlist: design.schematic, artifactDirectory: design.artifacts.appending(path: "signoff")
            )
        } catch DesignFlowCommandError.signoffToolchainUnavailable {
            throw CLIError(code: 2, message: "signoff toolchain unavailable — run `signoff doctor`")
        }

        // PEX runs AFTER the DRC/LVS verdict so a parasitic-extraction hiccup (a
        // tooling problem) never suppresses or masquerades as the physical-
        // verification verdict. A failed extraction is reported, then surfaced as
        // exit 2 — but only when the design otherwise passed; a real DRC/LVS
        // failure (exit 3) always takes precedence.
        var pex: PEXSummary?
        var pexError: String?
        do {
            pex = try await extractPEX(design: design, rc: rc, corner: corner)
        } catch let error as CLIError {
            pexError = error.message
        } catch {
            pexError = "PEX extraction failed (\(error.localizedDescription))"
        }

        report(design: design, review: review, pex: pex, pexError: pexError,
               rc: rc, corner: corner, json: options.flag("--json"))

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
    private static func runIterate(_ options: Options) async throws -> Int32 {
        guard let list = options.value("--cells") else {
            throw CLIError(code: 1, message: "iterate requires --cells <a,b,c> (the candidate sequence)")
        }
        let cells = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
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
            let base = artifacts.appending(path: cell)
            let gds = try layoutService.materialize(cell: cell, into: base.appending(path: "layout"))
            let schematic = try provider.schematic(forCell: cell, into: base.appending(path: "schematic"))
            return SignoffIterationLoop.Candidate(layoutGDS: gds, topCell: cell, schematicNetlist: schematic)
        }

        print("iterate (\(cells.count) candidates, max \(maxIterations) iterations)")
        for outcome in result.iterations {
            print("  iter \(outcome.index): \(outcome.candidate.topCell) [\(outcome.passed ? "PASS" : "FAIL")]")
        }
        if result.converged, let last = result.iterations.last {
            print("Converged: \(last.candidate.topCell) passed at iteration \(last.index)")
            return 0
        }
        print("Did not converge within \(maxIterations) iterations")
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

    private static func resolveDesign(_ options: Options) throws -> Design {
        let artifacts = options.artifactsDirectory()
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)

        if let cell = options.value("--cell") {
            guard let layoutService = PDKCellLayoutService.locate() else {
                throw CLIError(code: 2, message: "layout toolchain unavailable — run `signoff doctor`")
            }
            let gds = try layoutService.materialize(cell: cell, into: artifacts.appending(path: "layout"))
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
                    case .libraryDeckMissing, .subcircuitNotFound:
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

    private static func extractPEX(design: Design, rc: Bool, corner: String) async throws -> PEXSummary {
        guard MagicToolchain.locate() != nil else {
            throw CLIError(code: 2, message: "PEX toolchain unavailable — run `signoff doctor`")
        }
        let pexDir = design.artifacts.appending(path: "pex")
        try FileManager.default.createDirectory(at: pexDir, withIntermediateDirectories: true)
        let netlist = pexDir.appending(path: "pex-source.cir")
        try Data("* placeholder\n.end\n".utf8).write(to: netlist)
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
            FileHandle.standardError.write(
                Data("warning: back-annotation skipped (\(error.localizedDescription))\n".utf8))
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

    // MARK: - report

    private static func report(design: Design, review: ExternalSignoffReview, pex: PEXSummary?,
                               pexError: String?, rc: Bool, corner: String, json: Bool) {
        let drc = review.reports.first { $0.kind == .drc }?.passed ?? false
        let lvs = review.reports.first { $0.kind == .lvs }?.passed ?? false
        let overall = review.passed
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
                try emitJSON(obj)
            } catch {
                FileHandle.standardError.write(
                    Data("error: failed to emit JSON (\(error.localizedDescription))\n".utf8))
            }
            return
        }
        print("check \(design.topCell)\(design.materializedByName ? " (materialized + PDK schematic)" : "")")
        print("  DRC  [\(drc ? "PASS" : "FAIL")]")
        for d in review.reports.first(where: { $0.kind == .drc })?.diagnostics.filter({ $0.severity == .error }) ?? [] {
            print("       - \(d.ruleID ?? "?"): \(d.message)")
        }
        print("  LVS  [\(lvs ? "PASS" : "FAIL")]")
        for d in review.reports.first(where: { $0.kind == .lvs })?.diagnostics.filter({ $0.severity == .error }) ?? [] {
            print("       - \(d.ruleID ?? "?"): \(d.message)")
        }
        if let pex {
            var pexLine = String(format: "  PEX  %d elements, %d nets, ground %.3f fF, coupling %.3f fF",
                                 pex.elementCount, pex.netCount, pex.groundCapF * 1e15, pex.couplingCapF * 1e15)
            if rc { pexLine += String(format: ", %d resistors (Σ %.1f Ω)", pex.resistorCount, pex.totalResistanceOhm) }
            print(pexLine)
            if let ba = pex.backAnnotation {
                print(String(format: "  RC   back-annotated τ: R·C %.3f ns vs sim %.3f ns [%@]",
                             ba.expectedTauS * 1e9, ba.measuredTauS * 1e9, ba.consistent ? "consistent" : "INCONSISTENT"))
            }
        } else {
            print("  PEX  FAILED: \(pexError ?? "extraction failed")")
        }
        print("Result: \(overall ? "PASS" : "FAIL")")
    }

    // MARK: - helpers

    private static func emitJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func usage() {
        print("""
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

    struct CLIError: Error { let code: Int32; let message: String }

    struct Options {
        private var values: [String: String] = [:]
        init(args: [String]) {
            var i = 0
            while i < args.count {
                let a = args[i]
                if a.hasPrefix("--"), i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                    values[a] = args[i + 1]; i += 2
                } else { values[a] = ""; i += 1 }
            }
        }
        func value(_ key: String) -> String? { values[key].flatMap { $0.isEmpty ? nil : $0 } }
        func flag(_ key: String) -> Bool { values[key] != nil }
        func require(_ key: String) throws -> String {
            guard let v = value(key) else { throw CLIError(code: 1, message: "missing required \(key)") }
            return v
        }
        func fileURL(_ key: String) throws -> URL {
            let path = try require(key)
            guard FileManager.default.fileExists(atPath: path) else {
                throw CLIError(code: 1, message: "\(key) file not found: \(path)")
            }
            return URL(filePath: path)
        }
        func artifactsDirectory() -> URL {
            if let dir = value("--artifacts") { return URL(filePath: dir) }
            return FileManager.default.temporaryDirectory.appending(path: "signoff-\(UUID().uuidString)")
        }
        func with(key: String, value: String) -> Options {
            var copy = self
            copy.values[key] = value
            return copy
        }
    }
}
