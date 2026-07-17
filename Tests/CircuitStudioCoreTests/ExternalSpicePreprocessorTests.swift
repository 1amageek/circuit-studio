import CircuiteFoundation
import Foundation
import OpenVAFSupport
import Testing

@testable import CircuitStudioCore

@Suite("ExternalSpicePreprocessor Tests")
struct ExternalSpicePreprocessorTests {

  @Test("Verilog-A includes compile through OpenVAFSupport")
  func verilogAIncludesCompileThroughOpenVAFSupport() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CircuitStudioExternalSpicePreprocessorTests-\(UUID().uuidString)")
    defer { removeCoreTestTemporaryDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let sourceURL = directory.appending(path: "compact.va")
    try Data("module compact_type; endmodule\n".utf8).write(to: sourceURL)

    let compiler = RecordingOpenVAFCompiler()
    let preprocessor = ExternalSpicePreprocessor(openVAFCompiler: compiler)
    let prepared = try await preprocessor.prepare(
      source: """
        .include "\(sourceURL.path)"
        .model compact_model compact_type
        M1 d g s b compact_model w=1u l=1u
        .tran 1n 10n
        .end
        """,
      fileName: directory.appending(path: "input.cir").path,
      processConfiguration: nil,
      command: nil
    )

    let netlist = try String(contentsOf: prepared.netlistURL, encoding: .utf8)
    let requests = await compiler.requests()
    let results = await compiler.results()
    let outputArtifact = try #require(results.first?.outputArtifact)
    let outputURL = try outputArtifact.locator.location.resolvedFileURL()

    #expect(requests.map(\.sourceURL) == [sourceURL])
    #expect(
      requests.first?.outputDirectory.path == prepared.netlistURL.deletingLastPathComponent().path)
    #expect(requests.first?.includeRootDirectory?.path == directory.path)
    #expect(results.count == 1)
    #expect(netlist.contains("pre_osdi \"\(outputURL.path)\""))
    #expect(netlist.contains("N1 d g s b compact_model w=1u l=1u"))
    #expect(!netlist.contains(".include \"\(sourceURL.path)\""))
  }

  @Test("Pre OSDI directives are resolved into the generated control block once")
  func preOSDIDirectivesAreResolvedIntoGeneratedControlBlockOnce() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CircuitStudioExternalSpicePreprocessorPreOSDITests-\(UUID().uuidString)")
    defer { removeCoreTestTemporaryDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let osdiURL = directory.appending(path: "compact.osdi")
    try Data("osdi".utf8).write(to: osdiURL)

    let preprocessor = ExternalSpicePreprocessor(openVAFCompiler: RecordingOpenVAFCompiler())
    let prepared = try await preprocessor.prepare(
      source: """
        .pre_osdi "\(osdiURL.path)"
        .include "\(osdiURL.path)"
        V1 in 0 DC 1
        R1 in 0 1k
        .op
        .end
        """,
      fileName: directory.appending(path: "input.cir").path,
      processConfiguration: nil,
      command: nil
    )

    let netlist = try String(contentsOf: prepared.netlistURL, encoding: .utf8)
    let expectedDirective = "pre_osdi \"\(osdiURL.path)\""

    #expect(netlist.components(separatedBy: expectedDirective).count == 2)
    #expect(!netlist.contains(".pre_osdi"))
    #expect(!netlist.contains(".include \"\(osdiURL.path)\""))
  }

  @Test("Unresolved pre OSDI directives fail before netlist artifact generation")
  func unresolvedPreOSDIDirectivesFailBeforeNetlistArtifactGeneration() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CircuitStudioExternalSpicePreprocessorMissingPreOSDITests-\(UUID().uuidString)")
    defer { removeCoreTestTemporaryDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let preprocessor = ExternalSpicePreprocessor(openVAFCompiler: RecordingOpenVAFCompiler())

    do {
      _ = try await preprocessor.prepare(
        source: """
          .pre_osdi "missing.osdi"
          V1 in 0 DC 1
          R1 in 0 1k
          .op
          .end
          """,
        fileName: directory.appending(path: "input.cir").path,
        processConfiguration: nil,
        command: nil
      )
      Issue.record("Expected unresolved .pre_osdi failure")
    } catch StudioError.simulationFailure(let message) {
      #expect(message.contains("Unable to resolve .pre_osdi library path"))
      #expect(message.contains("missing.osdi"))
    } catch {
      Issue.record("Expected simulation failure, got \(error)")
    }
  }

  @Test("Verilog-A frontend constrains instance prefix rewrites to parsed module types")
  func verilogAFrontendConstrainsInstancePrefixRewrites() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CircuitStudioExternalSpicePreprocessorModuleMapTests-\(UUID().uuidString)")
    defer { removeCoreTestTemporaryDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let sourceURL = directory.appending(path: "compact.va")
    try Data("module compact_type; endmodule\n".utf8).write(to: sourceURL)

    let compiler = RecordingOpenVAFCompiler()
    let preprocessor = ExternalSpicePreprocessor(openVAFCompiler: compiler)
    let prepared = try await preprocessor.prepare(
      source: """
        .include "\(sourceURL.path)"
        .model compact_model compact_type
        .model unrelated_model unrelated_type
        M1 d g s b compact_model w=1u l=1u
        M2 d2 g2 s2 b2 unrelated_model w=1u l=1u
        .tran 1n 10n
        .end
        """,
      fileName: directory.appending(path: "input.cir").path,
      processConfiguration: nil,
      command: nil
    )

    let netlist = try String(contentsOf: prepared.netlistURL, encoding: .utf8)

    #expect(netlist.contains("N1 d g s b compact_model w=1u l=1u"))
    #expect(netlist.contains("M2 d2 g2 s2 b2 unrelated_model w=1u l=1u"))
    #expect(!netlist.contains("N2 d2 g2 s2 b2 unrelated_model"))
  }

  @Test("OpenVAF compile failures surface diagnostics once")
  func openVAFCompileFailuresSurfaceDiagnosticsOnce() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CircuitStudioExternalSpicePreprocessorFailureTests-\(UUID().uuidString)")
    defer { removeCoreTestTemporaryDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let sourceURL = directory.appending(path: "bad.va")
    try Data("module bad; endmodule\n".utf8).write(to: sourceURL)

    let preprocessor = ExternalSpicePreprocessor(openVAFCompiler: FailingOpenVAFCompiler())

    do {
      _ = try await preprocessor.prepare(
        source: """
          .include "\(sourceURL.path)"
          .model bad_model compact_type
          M1 d g s b bad_model
          .end
          """,
        fileName: directory.appending(path: "input.cir").path,
        processConfiguration: nil,
        command: nil
      )
      Issue.record("Expected OpenVAF compile failure")
    } catch StudioError.simulationFailure(let message) {
      #expect(message.contains("OpenVAF failed with exit code 2"))
      #expect(message.contains("syntax error"))
      #expect(message.components(separatedBy: "syntax error").count == 2)
    } catch {
      Issue.record("Expected simulation failure, got \(error)")
    }
  }

  @Test("Process configuration temperature becomes a .temp card")
  func processConfigurationTemperatureBecomesTempCard() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CircuitStudioExternalSpicePreprocessorTempTests-\(UUID().uuidString)")
    defer { removeCoreTestTemporaryDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let preprocessor = ExternalSpicePreprocessor(openVAFCompiler: RecordingOpenVAFCompiler())
    let prepared = try await preprocessor.prepare(
      source: """
        V1 in 0 DC 1
        R1 in 0 1k
        .tran 1n 10n
        .end
        """,
      fileName: directory.appending(path: "input.cir").path,
      processConfiguration: ProcessConfiguration(temperatureOverride: 85.0),
      command: nil
    )

    let netlist = try String(contentsOf: prepared.netlistURL, encoding: .utf8)
    #expect(netlist.contains(".temp 85.0"))
  }

  @Test("A stale .temp card is stripped when the configuration resolves a temperature")
  func staleTempCardIsStrippedWhenConfigurationResolvesTemperature() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CircuitStudioExternalSpicePreprocessorStaleTempTests-\(UUID().uuidString)")
    defer { removeCoreTestTemporaryDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let preprocessor = ExternalSpicePreprocessor(openVAFCompiler: RecordingOpenVAFCompiler())
    let prepared = try await preprocessor.prepare(
      source: """
        V1 in 0 DC 1
        R1 in 0 1k
        .temp 27
        .tran 1n 10n
        .end
        """,
      fileName: directory.appending(path: "input.cir").path,
      processConfiguration: ProcessConfiguration(temperatureOverride: 125.0),
      command: nil
    )

    let netlist = try String(contentsOf: prepared.netlistURL, encoding: .utf8)
    #expect(!netlist.contains(".temp 27"))
    #expect(netlist.contains(".temp 125.0"))
  }

  @Test("Effective parameters become sorted .param cards")
  func effectiveParametersBecomeSortedParamCards() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CircuitStudioExternalSpicePreprocessorParamTests-\(UUID().uuidString)")
    defer { removeCoreTestTemporaryDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let preprocessor = ExternalSpicePreprocessor(openVAFCompiler: RecordingOpenVAFCompiler())
    let prepared = try await preprocessor.prepare(
      source: """
        V1 in 0 DC 1
        R1 in 0 1k
        .tran 1n 10n
        .end
        """,
      fileName: directory.appending(path: "input.cir").path,
      processConfiguration: ProcessConfiguration(
        parameterOverrides: ["vth": 0.4, "vdd": 1.8]
      ),
      command: nil
    )

    let netlist = try String(contentsOf: prepared.netlistURL, encoding: .utf8)
    let vddRange = try #require(netlist.range(of: ".param vdd=1.8"))
    let vthRange = try #require(netlist.range(of: ".param vth=0.4"))
    #expect(vddRange.lowerBound < vthRange.lowerBound)
  }

  @Test("Without a configuration the source's own .temp card stands")
  func withoutConfigurationSourceTempCardStands() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CircuitStudioExternalSpicePreprocessorNoConfigTests-\(UUID().uuidString)")
    defer { removeCoreTestTemporaryDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let preprocessor = ExternalSpicePreprocessor(openVAFCompiler: RecordingOpenVAFCompiler())
    let prepared = try await preprocessor.prepare(
      source: """
        V1 in 0 DC 1
        R1 in 0 1k
        .temp 27
        .tran 1n 10n
        .end
        """,
      fileName: directory.appending(path: "input.cir").path,
      processConfiguration: nil,
      command: nil
    )

    let netlist = try String(contentsOf: prepared.netlistURL, encoding: .utf8)
    #expect(netlist.contains(".temp 27"))
    #expect(netlist.components(separatedBy: ".temp").count == 2)
  }
}

private actor RecordingOpenVAFCompiler: OpenVAFCompiler {
  private var recordedRequests: [OpenVAFCompilationRequest] = []
  private var recordedResults: [OpenVAFCompilationResult] = []

  func availability() async -> OpenVAFAvailability {
    .available(
      OpenVAFInstallation(
        executableURL: URL(fileURLWithPath: "/test/openvaf"),
        version: "test",
        rawVersionOutput: "OpenVAF test"
      ))
  }

  func compile(_ request: OpenVAFCompilationRequest) async throws(OpenVAFError)
    -> OpenVAFCompilationResult
  {
    recordedRequests.append(request)
    let outputFileName =
      request.outputFileName
      ?? request.sourceURL.deletingPathExtension().lastPathComponent + ".osdi"
    let outputDirectory = request.outputDirectory
      .appending(path: "openvaf-test-\(recordedRequests.count)")
    let outputURL = outputDirectory.appending(path: outputFileName)
    do {
      try FileManager.default.createDirectory(
        at: outputDirectory, withIntermediateDirectories: true)
      try Data("osdi".utf8).write(to: outputURL)
    } catch {
      throw .fileSystemFailure(
        operation: "write fake osdi",
        path: outputURL.path,
        message: error.localizedDescription
      )
    }

    do {
      let now = Date()
      let producer = try ProducerIdentity(
        kind: .tool,
        identifier: "test.openvaf",
        version: "test"
      )
      let artifact = try LocalArtifactReferencer().reference(
        ArtifactLocator(
          location: try ArtifactLocation(fileURL: outputURL),
          role: .output,
          kind: .model,
          format: try ArtifactFormat(rawValue: "osdi")
        ),
        producer: producer
      )
      let provenance = try ExecutionProvenance(
        producer: producer,
        invocation: try .externalProcess(
          executable: "/test/openvaf",
          arguments: [request.sourceURL.lastPathComponent],
          workingDirectory: outputDirectory.path
        ),
        startedAt: now,
        completedAt: now
      )
      let result = OpenVAFCompilationResult(
        artifacts: [artifact],
        diagnostics: [],
        provenance: provenance,
        openVAFVersion: "test",
        exitCode: 0
      )
      recordedResults.append(result)
      return result
    } catch {
      throw .fileSystemFailure(
        operation: "create fake OpenVAF result",
        path: outputURL.path,
        message: error.localizedDescription
      )
    }
  }

  func requests() -> [OpenVAFCompilationRequest] {
    recordedRequests
  }

  func results() -> [OpenVAFCompilationResult] {
    recordedResults
  }
}

private struct FailingOpenVAFCompiler: OpenVAFCompiler {
  func availability() async -> OpenVAFAvailability {
    .available(
      OpenVAFInstallation(
        executableURL: URL(fileURLWithPath: "/test/openvaf"),
        version: "test",
        rawVersionOutput: "OpenVAF test"
      ))
  }

  func compile(_ request: OpenVAFCompilationRequest) async throws(OpenVAFError)
    -> OpenVAFCompilationResult
  {
    let now = Date()
    let failure: OpenVAFCompilationFailure
    do {
      let producer = try ProducerIdentity(
        kind: .tool,
        identifier: "test.openvaf",
        version: "test"
      )
      failure = OpenVAFCompilationFailure(
        artifacts: [],
        diagnostics: [DesignDiagnostic(
          code: .trusted("test.openvaf.compilation.failed"),
          severity: .error,
          summary: "syntax error"
        )],
        provenance: try ExecutionProvenance(
          producer: producer,
          invocation: try .externalProcess(
            executable: "/test/openvaf",
            arguments: [request.sourceURL.lastPathComponent],
            workingDirectory: request.outputDirectory.path
          ),
          startedAt: now,
          completedAt: now
        ),
        openVAFVersion: "test",
        exitCode: 2
      )
    } catch {
      throw .fileSystemFailure(
        operation: "create fake OpenVAF failure",
        path: request.outputDirectory.path,
        message: error.localizedDescription
      )
    }
    throw .compilationFailed(failure)
  }
}
