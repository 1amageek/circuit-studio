import Foundation
import CircuitStudioApp

@main
struct CircuitStudioFlowRunner {
    static func main() async {
        do {
            let options = try RunnerOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                Swift.print(Self.helpText)
                return
            }

            let designFlowService = DesignFlowService()
            let result = try await designFlowService.execute(command(from: options))
            print(result: result, options: options)
        } catch {
            fputs("flow_command=failed\n", stderr)
            fputs("error=\(error.localizedDescription)\n", stderr)
            fputs("\n\(Self.helpText)\n", stderr)
            exit(1)
        }
    }

    private static func command(from options: RunnerOptions) -> DesignFlowCommand {
        DesignFlowCommand(
            kind: options.mode.commandKind,
            fixtureName: options.fixtureName,
            projectRootPath: projectRootPath(from: options),
            runID: options.runID,
            approveSignoff: options.approveSignoff,
            pexManifestPath: options.pexManifestURL?.path(percentEncoded: false),
            pexCornerID: options.pexCornerID,
            signoffDRCLogPath: options.signoffDRCLogURL?.path(percentEncoded: false),
            signoffLVSLogPath: options.signoffLVSLogURL?.path(percentEncoded: false),
            maxAbsoluteDelta: options.maxAbsoluteDelta,
            maxRelativeDelta: options.maxRelativeDelta
        )
    }

    private static func projectRootPath(from options: RunnerOptions) -> String? {
        switch options.mode {
        case .listFixtures, .generateNetlist, .simulate:
            return nil
        case .runRoundTrip:
            return options.outputURL?.path(percentEncoded: false)
        case .summarizeBottlenecks:
            return (options.outputURL ?? defaultOutputURL(fixtureName: options.fixtureName))
                .path(percentEncoded: false)
        }
    }

    private static func defaultOutputURL(fixtureName: String) -> URL {
        URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: "round-trip-runs")
            .appending(path: fixtureName)
    }

    private static func print(result: DesignFlowCommandResult, options: RunnerOptions) {
        switch result.kind {
        case .listFixtures:
            for fixtureName in result.fixtureNames {
                Swift.print("fixture=\(fixtureName)")
            }
        case .generateFixtureNetlist:
            Swift.print("netlist=generated")
            Swift.print("fixture=\(result.fixtureName ?? options.fixtureName)")
            Swift.print("netlist_begin")
            Swift.print(result.netlist ?? "")
            Swift.print("netlist_end")
        case .runFixtureSimulation:
            Swift.print("simulation=\(result.simulationStatus ?? "")")
            Swift.print("fixture=\(result.fixtureName ?? options.fixtureName)")
            Swift.print("netlist_begin")
            Swift.print(result.netlist ?? "")
            Swift.print("netlist_end")
        case .runFixtureRoundTrip:
            Swift.print("round_trip=passed")
            Swift.print("fixture=\(result.fixtureName ?? options.fixtureName)")
            Swift.print("run_id=\(result.runID ?? "")")
            Swift.print("project_root=\(result.projectRootPath ?? "")")
            Swift.print("manifest=\(result.manifestPath ?? "")")
            Swift.print("ready_for_pex=\(result.readyForPEX ?? false)")
            Swift.print("pex_corner=\(result.pexCornerID ?? "")")
            Swift.print("pex_elements=\(result.pexElementCount ?? 0)")
            Swift.print("external_signoff=\(options.usesImportedSignoff ? "imported-logs" : "mock-command")")
            Swift.print("signoff_approved=\(options.approveSignoff)")
            Swift.print("comparison_limits=\(options.usesComparisonLimits ? "configured" : "none")")
        case .summarizeBottlenecks:
            let summary = result.bottleneckHistory
            Swift.print("bottlenecks=summarized")
            Swift.print("project_root=\(result.projectRootPath ?? "")")
            Swift.print("run_count=\(summary?.runCount ?? 0)")
            Swift.print("failed_run_count=\(summary?.failedRunCount ?? 0)")
            Swift.print("most_frequent_failed_stage=\(summary?.mostFrequentFailedStageName ?? "")")
            Swift.print("most_expensive_stage=\(summary?.mostExpensiveStageName ?? "")")
            for stageSummary in summary?.stageSummaries ?? [] {
                Swift.print(
                    "stage=\(stageSummary.stageName),observed=\(stageSummary.observedCount),failed=\(stageSummary.failedCount),avg_seconds=\(stageSummary.averageDurationSeconds)"
                )
            }
            for recommendation in summary?.recommendations ?? [] {
                Swift.print("recommendation=\(recommendation)")
            }
        }
    }

    private static var helpText: String {
        """
        Usage:
          swift run circuit-studio-flow-runner [MODE] [--fixture \(DesignFlowFixtureLibrary.fixtureNames.joined(separator: "|"))] [--output PATH] [--run-id ID] [--approve-signoff] [--pex-manifest PATH] [--pex-corner ID] [--signoff-drc-log PATH --signoff-lvs-log PATH] [--max-abs-delta VALUE] [--max-rel-delta VALUE]

        The runner executes the current headless round-trip flow:
          schematic -> netlist -> pre-layout simulation -> auto layout -> DRC/LVS gate -> PEX injection -> post-layout simulation -> comparison -> manifest

        Modes:
          --list-fixtures           List fixture names through DesignFlowCommand
          --generate-netlist        Generate a fixture netlist through DesignFlowCommand
          --simulate                Run fixture schematic simulation through DesignFlowCommand
          --summarize-bottlenecks   Summarize existing flow manifests under --output through DesignFlowCommand
          default                   Run the full fixture round trip through DesignFlowCommand

        Options:
          --fixture NAME   Fixture to run. Default: voltage-divider
          --output PATH    Project/output directory. Default: ./round-trip-runs/<fixture>
          --run-id ID      Flow run identifier. Default: fixture name plus timestamp
          --pex-manifest PATH
                           Load PEX IR through a saved PEXEngine manifest instead of using the built-in synthetic IR
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
          --help           Show this help
        """
    }

}

private enum RunnerMode: Equatable {
    case listFixtures
    case generateNetlist
    case simulate
    case runRoundTrip
    case summarizeBottlenecks

    var commandKind: DesignFlowCommand.Kind {
        switch self {
        case .listFixtures:
            return .listFixtures
        case .generateNetlist:
            return .generateFixtureNetlist
        case .simulate:
            return .runFixtureSimulation
        case .runRoundTrip:
            return .runFixtureRoundTrip
        case .summarizeBottlenecks:
            return .summarizeBottlenecks
        }
    }
}

private struct RunnerOptions {
    var mode = RunnerMode.runRoundTrip
    private var explicitMode: RunnerMode?
    var fixtureName = DesignFlowFixtureLibrary.defaultFixtureName
    var outputURL: URL?
    var runID: String?
    var pexManifestURL: URL?
    var pexCornerID = "tt_25c_1v0"
    var signoffDRCLogURL: URL?
    var signoffLVSLogURL: URL?
    var maxAbsoluteDelta: Double?
    var maxRelativeDelta: Double?
    var approveSignoff = false
    var showHelp = false

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--list-fixtures":
                try selectMode(.listFixtures)
            case "--generate-netlist":
                try selectMode(.generateNetlist)
            case "--simulate":
                try selectMode(.simulate)
            case "--summarize-bottlenecks":
                try selectMode(.summarizeBottlenecks)
            case "--fixture":
                fixtureName = try Self.value(after: argument, in: arguments, index: &index)
            case "--output":
                outputURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--run-id":
                runID = try Self.value(after: argument, in: arguments, index: &index)
            case "--pex-manifest":
                pexManifestURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--pex-corner":
                pexCornerID = try Self.value(after: argument, in: arguments, index: &index)
            case "--signoff-drc-log":
                signoffDRCLogURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--signoff-lvs-log":
                signoffLVSLogURL = URL(filePath: try Self.value(after: argument, in: arguments, index: &index))
            case "--max-abs-delta":
                maxAbsoluteDelta = try Self.doubleValue(after: argument, in: arguments, index: &index)
            case "--max-rel-delta":
                maxRelativeDelta = try Self.doubleValue(after: argument, in: arguments, index: &index)
            case "--approve-signoff":
                approveSignoff = true
            case "--help", "-h":
                showHelp = true
            default:
                throw RunnerError.invalidArgument(argument)
            }
            index += 1
        }
    }

    private mutating func selectMode(_ mode: RunnerMode) throws {
        if let explicitMode, explicitMode != mode {
            throw RunnerError.conflictingModes
        }
        explicitMode = mode
        self.mode = mode
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw RunnerError.missingValue(option)
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func doubleValue(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let rawValue = try value(after: option, in: arguments, index: &index)
        guard let value = Double(rawValue),
              value.isFinite,
              value >= 0 else {
            throw RunnerError.invalidNumericValue(option, rawValue)
        }
        return value
    }

    var usesImportedSignoff: Bool {
        signoffDRCLogURL != nil || signoffLVSLogURL != nil
    }

    var usesComparisonLimits: Bool {
        maxAbsoluteDelta != nil || maxRelativeDelta != nil
    }
}

private enum RunnerError: Error, LocalizedError {
    case invalidArgument(String)
    case missingValue(String)
    case invalidNumericValue(String, String)
    case conflictingModes

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let argument):
            return "Invalid argument: \(argument)"
        case .missingValue(let option):
            return "Missing value for \(option)"
        case .invalidNumericValue(let option, let value):
            return "Invalid numeric value for \(option): \(value)"
        case .conflictingModes:
            return "Only one runner mode can be selected."
        }
    }
}
