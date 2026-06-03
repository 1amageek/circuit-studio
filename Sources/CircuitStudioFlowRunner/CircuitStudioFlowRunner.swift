import Foundation
import CircuitStudioApp

@main
struct CircuitStudioFlowRunner {
    static func main() async {
        let options: FlowRunnerCommandOptions
        do {
            options = try FlowRunnerCommandOptions(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            printUsageFailure(error)
            exit(1)
        }

        if options.showHelp {
            Swift.print(Self.helpText)
            return
        }

        do {
            let designFlowService = DesignFlowService()
            let result = try await designFlowService.execute(options.makeCommand())
            print(result: result, options: options)
        } catch {
            printRuntimeFailure(error, options: options)
            exit(1)
        }
    }

    private static func print(result: DesignFlowCommandResult, options: FlowRunnerCommandOptions) {
        let context = FlowRunnerOutputContext(
            fixtureName: options.fixtureName,
            usesImportedSignoff: options.usesImportedSignoff,
            approveSignoff: options.approveSignoff
        )
        for line in FlowRunnerKeyValueFormatter.lines(for: result, context: context) {
            Swift.print(line)
        }
    }

    private static func printUsageFailure(_ error: Error) {
        fputs("flow_command=failed\n", stderr)
        fputs("error_kind=usage\n", stderr)
        fputs("error_type=\(errorType(error))\n", stderr)
        fputs("error=\(error.localizedDescription)\n", stderr)
        fputs("help_hint=swift run circuit-studio-flow-runner --help\n", stderr)
    }

    private static func printRuntimeFailure(_ error: Error, options: FlowRunnerCommandOptions) {
        let manifestURL = candidateManifestURL(from: options)
        fputs("flow_command=failed\n", stderr)
        fputs("error_kind=\(runtimeErrorKind(error))\n", stderr)
        fputs("error_type=\(errorType(error))\n", stderr)
        fputs("error=\(error.localizedDescription)\n", stderr)
        if let runID = options.runID {
            fputs("run_id=\(runID)\n", stderr)
        }
        if let projectRoot = options.projectRootPath {
            fputs("project_root=\(projectRoot)\n", stderr)
        }
        if let manifestURL {
            fputs("manifest=\(manifestURL.path(percentEncoded: false))\n", stderr)
            if let failedStage = failedStageName(from: manifestURL) {
                fputs("stage=\(failedStage)\n", stderr)
            }
        }
        fputs("recommendation=\(recommendation(for: error, manifestURL: manifestURL))\n", stderr)
    }

    private static func runtimeErrorKind(_ error: Error) -> String {
        if error is DesignFlowCommandError {
            return "command_validation"
        }
        return "runtime"
    }

    private static func errorType(_ error: Error) -> String {
        String(describing: type(of: error))
    }

    private static func candidateManifestURL(from options: FlowRunnerCommandOptions) -> URL? {
        if let reviewManifestURL = options.reviewManifestURL {
            return reviewManifestURL
        }
        guard let runID = options.runID,
              let projectRoot = options.projectRootPath else {
            return nil
        }
        let manifestURL = URL(filePath: projectRoot)
            .appending(path: ".xcircuite")
            .appending(path: "flow-runs")
            .appending(path: runID)
            .appending(path: "round-trip-manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            return nil
        }
        return manifestURL
    }

    private static func failedStageName(from manifestURL: URL) -> String? {
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(HeadlessRoundTripService.Manifest.self, from: data)
            return manifest.stages.first { $0.status == .failed }?.name
        } catch {
            return nil
        }
    }

    private static func recommendation(for error: Error, manifestURL: URL?) -> String {
        let description = error.localizedDescription
        if description.contains("Post-layout comparison exceeded configured limits") {
            return "Inspect post-layout-comparison.json and adjust the design or comparison limits."
        }
        if error is DesignFlowCommandError {
            return "Fix the command inputs and rerun. Use --help only when you need the option reference."
        }
        if manifestURL != nil {
            return "Inspect the manifest and stage artifacts for the structured failure evidence."
        }
        return "Rerun with an explicit --output and --run-id to preserve inspectable run artifacts."
    }

    private static var helpText: String {
        """
        Usage:
          swift run circuit-studio-flow-runner [MODE] [--fixture \(DesignFlowFixtureLibrary.fixtureNames.joined(separator: "|"))] [--design-spec PATH] [--technology-package PATH] [--output PATH] [--run-id ID] [--approve-signoff] [--pex-manifest PATH] [--pex-config PATH] [--pex-executable PATH] [--pex-corner ID] [--signoff-drc-log PATH --signoff-lvs-log PATH] [--max-abs-delta VALUE] [--max-rel-delta VALUE] [--relative-delta-floor VALUE] [--domain-limit SPEC] [--variable-limit SPEC] [--oscillation-limit SPEC] [--edit-script PATH --output-design-spec PATH]

        The runner executes the current headless round-trip flow:
          schematic -> netlist -> pre-layout simulation -> auto layout -> DRC/LVS gate -> PEX injection -> post-layout simulation -> comparison -> manifest

        Modes:
          --list-fixtures           List fixture names through DesignFlowCommand
          --generate-netlist        Generate a fixture netlist through DesignFlowCommand
          --simulate                Run fixture schematic simulation through DesignFlowCommand
          --summarize-bottlenecks   Summarize existing flow manifests under --output through DesignFlowCommand
          --load-technology-package Load and validate a technology package manifest through DesignFlowCommand
          --run-pex-extraction     Run pexengine extract through DesignFlowCommand
          --apply-design-edit      Apply a design edit script through DesignFlowCommand
          --apply-layout-edit      Apply a layout edit script through DesignFlowCommand
          --run-layout-trust      Run ownership + net-aware topology evaluation for a layout document
          --run-verification       Run DRC/LVS/pre-PEX verification without a full round trip
          --approve-gate           Write a typed gate approval record for human-in-the-loop review
          --review-round-trip      Load a round-trip review summary from manifest artifacts
          default                   Run the full fixture round trip through DesignFlowCommand

        Options:
          --fixture NAME   Fixture to run. Default: voltage-divider
          --design-spec PATH
                           Load a structured design spec JSON instead of a built-in fixture
          --edit-script PATH
                           JSON design edit script for --apply-design-edit
          --output-design-spec PATH
                           Edited design spec path for --apply-design-edit
          --layout-document PATH
                           Layout document JSON path for --apply-layout-edit or --run-verification
          --output-layout-document PATH
                           Edited layout document JSON path for --apply-layout-edit
          --design-unit PATH
                           Optional DesignUnit JSON path for --run-verification
          --manifest PATH Round-trip manifest path for --review-round-trip
          --approval-gate ID
                           Gate ID for --approve-gate. Values: external-signoff, pre-pex-verification, post-layout-comparison, physical-verification
          --approval-target PATH
                           Explicit target artifact path for --approve-gate
          --reviewer NAME Reviewer identity for --approve-gate
          --approval-decision VALUE
                           Approval decision. Values: approved, rejected. Default: approved
          --approval-policy TEXT
                           Policy text or policy ID recorded in the approval artifact
          --approval-note TEXT
                           Free-form note recorded in the approval artifact
          --waiver ID      Waiver ID recorded in the approval artifact. Can be repeated
          --technology-package PATH
                           Inject one technology package manifest into netlist, simulation, layout, signoff, and PEX inputs when supported
          --output PATH    Project/output directory. Default: ./round-trip-runs/<fixture-or-design-spec-name>
          --run-id ID      Flow run identifier. Default: fixture name plus timestamp
          --pex-manifest PATH
                           Load PEX IR through a saved PEXEngine manifest instead of using the built-in synthetic IR
          --pex-config PATH
                           PEX project config for --run-pex-extraction
          --pex-executable PATH
                           Explicit pexengine executable path for --run-pex-extraction
          --pex-corner ID  PEX corner to load from --pex-manifest. Default: tt_25c_1v0
          --signoff-drc-log PATH
                           Load an existing clean DRC log instead of running the mock DRC command
          --signoff-lvs-log PATH
                           Load an existing clean LVS log instead of running the mock LVS command
          --approve-signoff
                           Explicitly approve passing signoff reports for the PEX gate
          --max-abs-delta VALUE
                           Fail the post-layout comparison gate when the maximum absolute delta exceeds VALUE
          --max-rel-delta VALUE
                           Fail the post-layout comparison gate when the maximum relative delta exceeds VALUE
          --relative-delta-floor VALUE
                           Floor the relative-delta denominator for global post-layout comparison gates
          --domain-limit SPEC
                           Add a domain-specific post-layout comparison gate. Format: DOMAIN:abs=VALUE,rel=VALUE,floor=VALUE
                           Domains: voltage,current,time,frequency,power,phase,magnitude,parameter,other
          --variable-limit SPEC
                           Add a variable-specific post-layout comparison gate. Format: VARIABLE:abs=VALUE,rel=VALUE,floor=VALUE
          --oscillation-limit SPEC
                           Add an oscillator metric gate. Format: VARIABLE:minTransitions=COUNT,minAmplitude=VALUE,freqRel=VALUE,periodRel=VALUE,duty=VALUE,threshold=VALUE
          --help           Show this help
        """
    }

}
