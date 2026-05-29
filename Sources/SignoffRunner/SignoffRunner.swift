import Foundation
import CircuitStudioApp
import PEXEngine

/// `signoff` — a CLI harness that runs the REAL physical-verification flow
/// (Magic DRC, Netgen LVS, Magic PEX) on a layout, with explicit exit codes.
///
/// Subcommands:
///   signoff doctor
///   signoff drc-lvs --layout <gds> --top-cell <name> --schematic <spice> [--artifacts <dir>]
///   signoff pex     --layout <gds> --top-cell <name> [--artifacts <dir>] [--corner <id>]
///   signoff full    --layout <gds> --top-cell <name> --schematic <spice> [--artifacts <dir>]
///
/// Exit codes: 0 ok · 1 usage/IO error · 2 toolchain unavailable ·
///             3 signoff did not pass (DRC/LVS violations or PEX failure).
@main
struct SignoffRunner {

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let subcommand = args.first else {
            usage()
            exit(1)
        }
        let options = Options(args: Array(args.dropFirst()))
        do {
            switch subcommand {
            case "doctor":
                exit(try runDoctor())
            case "drc-lvs":
                exit(try runDRCLVS(options))
            case "pex":
                exit(try await runPEX(options))
            case "full":
                let signoffCode = try runDRCLVS(options)
                guard signoffCode == 0 else { exit(signoffCode) }
                exit(try await runPEX(options))
            case "-h", "--help", "help":
                usage()
                exit(0)
            default:
                FileHandle.standardError.write(Data("error: unknown subcommand '\(subcommand)'\n".utf8))
                usage()
                exit(1)
            }
        } catch let error as CLIError {
            FileHandle.standardError.write(Data("error: \(error.message)\n".utf8))
            exit(error.code)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(3)
        }
    }

    // MARK: - Subcommands

    private static func runDoctor() throws -> Int32 {
        let drc = MagicDRCSignoff.locate()
        let lvs = NetgenLVSSignoff.locate()
        let pex = MagicToolchain.locate()
        func mark(_ present: Bool) -> String { present ? "found" : "MISSING" }
        print("Signoff toolchain:")
        print("  Magic DRC      : \(mark(drc != nil))")
        print("  Netgen LVS     : \(mark(lvs != nil))")
        print("  Magic PEX      : \(mark(pex != nil))")
        if let drc { print("  magic          : \(drc.magicExecutableURL.path(percentEncoded: false))") }
        if let drc { print("  PDK_ROOT       : \(drc.pdkRoot)") }
        let ok = drc != nil && lvs != nil && pex != nil
        print(ok ? "All tools available." : "Toolchain incomplete (see TOOLCHAIN.md).")
        return ok ? 0 : 2
    }

    private static func runDRCLVS(_ options: Options) throws -> Int32 {
        let layout = try options.fileURL("--layout")
        let topCell = try options.require("--top-cell")
        let schematic = try options.fileURL("--schematic")
        let artifacts = options.artifactsDirectory()

        let review: ExternalSignoffReview
        do {
            review = try DesignFlowService().runLiveSignoff(
                layoutGDS: layout, topCell: topCell, schematicNetlist: schematic, artifactDirectory: artifacts
            )
        } catch DesignFlowCommandError.signoffToolchainUnavailable {
            throw CLIError(code: 2, message: "signoff toolchain unavailable — run `signoff doctor`")
        }

        print("DRC/LVS signoff for \(topCell):")
        for report in review.reports {
            print("  \(report.kind.rawValue.uppercased()) [\(report.passed ? "PASS" : "FAIL")] via \(report.toolName)")
            for d in report.diagnostics where d.severity == .error {
                print("    - \(d.ruleID ?? "?"): \(d.message)")
            }
        }
        print(review.passed ? "Result: PASS" : "Result: FAIL")
        return review.passed ? 0 : 3
    }

    private static func runPEX(_ options: Options) async throws -> Int32 {
        let layout = try options.fileURL("--layout")
        let topCell = try options.require("--top-cell")
        let corner = options.value("--corner") ?? "tt"
        let artifacts = options.artifactsDirectory()

        guard MagicToolchain.locate() != nil else {
            throw CLIError(code: 2, message: "PEX toolchain unavailable — run `signoff doctor`")
        }
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        let netlist = artifacts.appending(path: "pex-source.cir")
        try Data("* placeholder\n.end\n".utf8).write(to: netlist)
        let tech = TechnologyIR(
            processName: "sky130A", stack: [], logicalToPhysicalLayerMap: [:],
            vias: [], defaultExtractionRules: .default, backendHints: [:]
        )
        let request = PEXRunRequest(
            layoutURL: layout, layoutFormat: .gds,
            sourceNetlistURL: netlist, sourceNetlistFormat: .spice,
            topCell: topCell, corners: [PEXCorner(id: corner)],
            technology: .inline(tech),
            backendSelection: PEXBackendSelection(backendID: "magic"),
            options: PEXRunOptions(
                extractMode: .cOnly, includeCouplingCaps: true,
                minCapacitanceF: nil, minResistanceOhm: nil, maxParallelJobs: 1,
                emitRawArtifacts: true, emitIRJSON: true, strictValidation: false
            ),
            workingDirectory: artifacts.appending(path: "pex")
        )
        let result = try await DefaultPEXEngine.withDefaults().run(request)
        guard result.status == .success, let ir = result.cornerResults.first?.ir else {
            throw CLIError(code: 3, message: "PEX extraction failed (status \(result.status.rawValue))")
        }
        let groundCap = ir.nets.map(\.totalGroundCapF).reduce(0, +)
        let couplingCap = ir.nets.map(\.totalCouplingCapF).reduce(0, +)
        print("PEX (\(corner)) for \(topCell):")
        print("  elements   : \(ir.elements.count)")
        print("  nets       : \(ir.nets.count)")
        print(String(format: "  ground cap : %.3f fF", groundCap * 1e15))
        print(String(format: "  coupling   : %.3f fF", couplingCap * 1e15))
        print("Result: PASS")
        return 0
    }

    // MARK: - Helpers

    private static func usage() {
        print("""
        signoff — real physical-verification harness (Magic DRC / Netgen LVS / Magic PEX)

        Usage:
          signoff doctor
          signoff drc-lvs --layout <gds> --top-cell <name> --schematic <spice> [--artifacts <dir>]
          signoff pex     --layout <gds> --top-cell <name> [--corner <id>] [--artifacts <dir>]
          signoff full    --layout <gds> --top-cell <name> --schematic <spice> [--artifacts <dir>]

        Exit codes: 0 ok · 1 usage/IO · 2 toolchain unavailable · 3 signoff failed
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
    }
}
