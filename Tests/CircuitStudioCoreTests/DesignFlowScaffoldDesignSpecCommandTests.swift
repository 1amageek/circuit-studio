import Foundation
import Testing
@testable import CircuitStudioApp

/// The 作る (author) entry point for design specs: the scaffold command
/// writes a minimal valid `DesignFlowDesignSpec` skeleton that the
/// netlist generator consumes UNCHANGED. Both directions run through the
/// same typed command surface the flow-runner CLI exposes.
@Suite("Design flow scaffold design spec command", .timeLimit(.minutes(3)))
struct DesignFlowScaffoldDesignSpecCommandTests {

    @Test
    @MainActor
    func scaffoldWritesSpecThatGeneratesNetlistUnchanged() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("scaffold-design-spec")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let specURL = root.appending(path: "new-design.design.json")
        let service = DesignFlowService()

        let scaffold = try await service.execute(DesignFlowCommand(
            kind: .scaffoldDesignSpec,
            outputDesignSpecPath: specURL.path(percentEncoded: false)
        ))
        #expect(scaffold.kind == .scaffoldDesignSpec)
        #expect(scaffold.designName == "new_design")
        #expect(scaffold.designSpecPath == specURL.path(percentEncoded: false))
        #expect(scaffold.message == "scaffolded")
        #expect(FileManager.default.fileExists(atPath: specURL.path(percentEncoded: false)))

        // Acceptance gate: --generate-netlist --design-spec succeeds on
        // the scaffold without a single edit.
        let netlistResult = try await service.execute(DesignFlowCommand(
            kind: .generateDesignNetlist,
            designSpecPath: specURL.path(percentEncoded: false)
        ))
        #expect(netlistResult.designName == "new_design")
        let netlist = try #require(netlistResult.netlist)
        #expect(netlist.contains("M1"))
        #expect(netlist.contains("V1"))
    }

    @Test
    @MainActor
    func scaffoldDecodesThroughDesignSpecTypeAndHonorsDesignName() async throws {
        let root = try DesignFlowServiceTestSupport.makeTemporaryRoot("scaffold-design-spec-named")
        defer { DesignFlowServiceTestSupport.removeTemporaryRoot(root) }
        let specURL = root.appending(path: "amp.design.json")

        let scaffold = try await DesignFlowService().execute(DesignFlowCommand(
            kind: .scaffoldDesignSpec,
            outputDesignSpecPath: specURL.path(percentEncoded: false),
            designName: "my_amp"
        ))
        #expect(scaffold.designName == "my_amp")

        let data = try Data(contentsOf: specURL)
        let spec = try JSONDecoder().decode(DesignFlowDesignSpec.self, from: data)
        #expect(spec.name == "my_amp")
        #expect(spec.schemaVersion == DesignFlowDesignSpec.currentSchemaVersion)
        #expect(spec.postLayoutAnalysis != nil)
        let limits = try #require(spec.postLayoutComparisonLimits)
        #expect(limits.validationDiagnostics().isEmpty)
        #expect(limits.variableLimits.isEmpty)
        let pexIR = try #require(spec.pexIR)
        #expect(pexIR.cornerID == "tt_25c_1v0")
        #expect(pexIR.elements.count == 1)
        #expect(pexIR.elements[0].nodeB == nil)

        let built = try spec.build()
        #expect(built.name == "my_amp")
        #expect(built.pexIR != nil)
    }

    @Test
    @MainActor
    func scaffoldRequiresOutputDesignSpecPath() async throws {
        await #expect(throws: DesignFlowCommandError.missingOutputDesignSpecPath) {
            _ = try await DesignFlowService().execute(DesignFlowCommand(
                kind: .scaffoldDesignSpec
            ))
        }
    }

    @Test
    func flowRunnerOptionsParseScaffoldDesignSpecMode() throws {
        let options = try FlowRunnerCommandOptions(arguments: [
            "--scaffold-design-spec",
            "--output-design-spec", "/tmp/new-design.design.json",
            "--design-name", "my_amp",
            "--json",
        ])
        #expect(options.mode == .scaffoldDesignSpec)
        #expect(options.outputFormat == .json)
        let command = options.makeCommand()
        #expect(command.kind == .scaffoldDesignSpec)
        #expect(command.outputDesignSpecPath == "/tmp/new-design.design.json")
        #expect(command.designName == "my_amp")
        #expect(command.projectRootPath == nil)
    }

    @Test
    func flowRunnerOptionsRejectScaffoldCombinedWithAnotherMode() {
        #expect(throws: FlowRunnerCommandOptions.ParseError.conflictingModes) {
            _ = try FlowRunnerCommandOptions(arguments: [
                "--scaffold-design-spec",
                "--generate-netlist",
            ])
        }
    }
}
