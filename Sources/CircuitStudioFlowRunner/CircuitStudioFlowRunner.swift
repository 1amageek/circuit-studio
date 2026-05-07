import Foundation
import CircuitStudioApp
import CircuitStudioCore
import SchematicEditor

@main
struct CircuitStudioFlowRunner {
    static func main() async {
        do {
            let options = try RunnerOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                print(Self.helpText)
                return
            }

            let fixture = try FlowFixture(name: options.fixtureName)
            let pexInput = try options.loadPEXInput() ?? PEXInput(ir: fixture.pexIR, artifactPaths: [])
            let externalSignoffReview = try options.loadExternalSignoffReview()
            let projectRoot = options.outputURL ?? defaultOutputURL(fixtureName: fixture.name)
            try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
            let signoffCommands: [ExternalSignoffCommand]
            if externalSignoffReview == nil {
                signoffCommands = try makeMockSignoffCommands(in: projectRoot)
            } else {
                signoffCommands = []
            }
            let configuration = HeadlessRoundTripService.Configuration(
                projectRoot: projectRoot,
                runID: options.runID ?? "\(fixture.name)-\(Self.timestamp())",
                title: fixture.title,
                testbench: fixture.testbench,
                postLayoutCommand: fixture.postLayoutCommand,
                pexIR: pexInput.ir,
                pexArtifactPaths: pexInput.artifactPaths,
                externalSignoffCommands: signoffCommands,
                externalSignoffReview: externalSignoffReview,
                approvedBy: options.approveSignoff ? "headless-runner" : nil,
                approvedAt: options.approveSignoff ? Date() : nil,
                createdAt: Date()
            )

            let result = try await HeadlessRoundTripService().run(
                schematic: fixture.schematic,
                configuration: configuration
            )

            print("round_trip=passed")
            print("fixture=\(fixture.name)")
            print("project_root=\(projectRoot.path(percentEncoded: false))")
            print("manifest=\(result.manifestURL.path(percentEncoded: false))")
            print("ready_for_pex=\(result.manifest.isReadyForPEX)")
            print("pex_corner=\(pexInput.ir.cornerID)")
            print("pex_elements=\(pexInput.ir.elements.count)")
            print("external_signoff=\(externalSignoffReview == nil ? "mock-command" : "imported-logs")")
            print("signoff_approved=\(options.approveSignoff)")
        } catch {
            fputs("round_trip=failed\n", stderr)
            fputs("error=\(error.localizedDescription)\n", stderr)
            fputs("\n\(Self.helpText)\n", stderr)
            exit(1)
        }
    }

    private static var helpText: String {
        """
        Usage:
          swift run circuit-studio-flow-runner [--fixture cmos-inverter|voltage-divider] [--output PATH] [--run-id ID] [--approve-signoff] [--pex-manifest PATH] [--pex-corner ID] [--signoff-drc-log PATH --signoff-lvs-log PATH]

        The runner executes the current headless round-trip flow:
          schematic -> netlist -> pre-layout simulation -> auto layout -> DRC/LVS gate -> PEX injection -> post-layout simulation -> manifest

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
          --help           Show this help
        """
    }

    private static func defaultOutputURL(fixtureName: String) -> URL {
        URL(filePath: FileManager.default.currentDirectoryPath)
            .appending(path: "round-trip-runs")
            .appending(path: fixtureName)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "")
    }
}

private struct RunnerOptions {
    var fixtureName = "voltage-divider"
    var outputURL: URL?
    var runID: String?
    var pexManifestURL: URL?
    var pexCornerID = "tt_25c_1v0"
    var signoffDRCLogURL: URL?
    var signoffLVSLogURL: URL?
    var approveSignoff = false
    var showHelp = false

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
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

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw RunnerError.missingValue(option)
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    func loadPEXInput() throws -> PEXInput? {
        guard let pexManifestURL else {
            return nil
        }
        let service = PEXArtifactService()
        let artifacts = try service.loadArtifacts(manifestURL: pexManifestURL)
        let ir = try service.loadIR(for: pexCornerID, artifacts: artifacts)
        var artifactPaths = [pexManifestURL.path(percentEncoded: false)]
        if let corner = artifacts.corner(id: pexCornerID) {
            artifactPaths.append(contentsOf: corner.rawFileURLs.map { $0.path(percentEncoded: false) })
            if let irURL = corner.irURL {
                artifactPaths.append(irURL.path(percentEncoded: false))
            }
            if let logURL = corner.logURL {
                artifactPaths.append(logURL.path(percentEncoded: false))
            }
        }
        return PEXInput(ir: ir, artifactPaths: artifactPaths)
    }

    func loadExternalSignoffReview() throws -> ExternalSignoffReview? {
        switch (signoffDRCLogURL, signoffLVSLogURL) {
        case (nil, nil):
            return nil
        case (.some(let drcLogURL), .some(let lvsLogURL)):
            return try ExternalSignoffArtifactService().load(logs: [
                ExternalSignoffLogArtifact(
                    kind: .drc,
                    toolName: "imported-drc",
                    logURL: drcLogURL,
                    success: true
                ),
                ExternalSignoffLogArtifact(
                    kind: .lvs,
                    toolName: "imported-lvs",
                    logURL: lvsLogURL,
                    success: true
                ),
            ])
        case (.some, nil):
            throw RunnerError.missingCompanionOption("--signoff-lvs-log")
        case (nil, .some):
            throw RunnerError.missingCompanionOption("--signoff-drc-log")
        }
    }
}

private struct PEXInput {
    let ir: PEXParasiticIR
    let artifactPaths: [String]
}

@MainActor
private struct FlowFixture {
    let name: String
    let title: String
    let schematic: SchematicDocument
    let testbench: Testbench
    let postLayoutCommand: AnalysisCommand
    let pexIR: PEXParasiticIR

    init(name: String) throws {
        switch name {
        case "cmos-inverter":
            self.name = name
            self.title = "CMOS inverter headless round trip"
            self.schematic = SchematicPreview.cmosInverterViewModel().document
            self.testbench = Testbench(
                name: "Transient",
                analysisCommands: [.tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9))]
            )
            self.postLayoutCommand = .tran(TranSpec(stopTime: 100e-9, stepTime: 0.1e-9))
            self.pexIR = PEXParasiticIR(
                version: "1.0",
                cornerID: "tt_25c_1v0",
                elements: [
                    PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 1.0),
                    PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 2e-15),
                ]
            )
        case "voltage-divider":
            self.name = name
            self.title = "Voltage divider headless round trip"
            self.schematic = SchematicPreview.voltageDividerViewModel().document
            self.testbench = Testbench(name: "Operating Point", analysisCommands: [.op])
            self.postLayoutCommand = .op
            self.pexIR = PEXParasiticIR(
                version: "1.0",
                cornerID: "tt_25c_1v0",
                elements: [
                    PEXParasiticElement(id: "r_out", kind: .resistor, nodeA: "out", nodeB: "out_pex", value: 0.5),
                    PEXParasiticElement(id: "c_out", kind: .capacitor, nodeA: "out_pex", nodeB: nil, value: 1e-15),
                ]
            )
        default:
            throw RunnerError.unknownFixture(name)
        }
    }
}

private enum RunnerError: Error, LocalizedError {
    case invalidArgument(String)
    case missingValue(String)
    case unknownFixture(String)
    case missingCompanionOption(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let argument):
            return "Invalid argument: \(argument)"
        case .missingValue(let option):
            return "Missing value for \(option)"
        case .unknownFixture(let name):
            return "Unknown fixture: \(name)"
        case .missingCompanionOption(let option):
            return "Missing required companion option: \(option)"
        }
    }
}

private func makeMockSignoffCommands(in projectRoot: URL) throws -> [ExternalSignoffCommand] {
    let toolDirectory = projectRoot
        .appending(path: ".xcircuite")
        .appending(path: "tools")
    try FileManager.default.createDirectory(at: toolDirectory, withIntermediateDirectories: true)

    let drc = try writeExecutable(
        named: "mock-drc",
        in: toolDirectory,
        contents: """
        #!/bin/sh
        printf '[INFO] rule=DRC_CLEAN message="clean drc"\\n'
        exit 0
        """
    )
    let lvs = try writeExecutable(
        named: "mock-lvs",
        in: toolDirectory,
        contents: """
        #!/bin/sh
        printf '[INFO] rule=LVS_MATCH message="clean lvs"\\n'
        exit 0
        """
    )

    return [
        ExternalSignoffCommand(
            kind: .drc,
            toolName: "mock-drc",
            executablePath: drc.path(percentEncoded: false)
        ),
        ExternalSignoffCommand(
            kind: .lvs,
            toolName: "mock-lvs",
            executablePath: lvs.path(percentEncoded: false)
        ),
    ]
}

private func writeExecutable(named name: String, in directory: URL, contents: String) throws -> URL {
    let url = directory.appending(path: name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o755))],
        ofItemAtPath: url.path(percentEncoded: false)
    )
    return url
}
