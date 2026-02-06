import Foundation
import Testing
@testable import CircuitStudioCore

@Suite("Virtual PDK Fixture Tests")
struct VirtualPDKTests {

    @Test func loadVirtualPDKFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "virtual_pdk", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let technology = try JSONDecoder().decode(ProcessTechnology.self, from: data)

        #expect(technology.name == "Virtual45")
        #expect(technology.libraries.count == 3)
        #expect(technology.cornerSet.corners.count == 3)
        #expect(technology.defaultCornerID != nil)

        let config = ProcessConfiguration(
            technology: technology,
            cornerID: technology.defaultCornerID
        )

        let coreLibrary = try #require(technology.libraries.first { $0.id == "core_models" })
        #expect(config.librarySection(for: coreLibrary) == "ff")

        let params = config.effectiveParameters()
        #expect(params["vdd"] == 1.1)
        #expect(params["u0"] == 0.05)

        let generator = NetlistGenerator()
        let source = generator.generate(
            from: SchematicDocument(),
            title: "VirtualPDK",
            testbench: nil,
            processConfiguration: config
        )

        #expect(source.contains(".lib \"models/core.lib\" ff"))
        #expect(source.contains(".include \"models/passives.inc\""))
        #expect(source.contains(".param vdd=1.1"))
        #expect(source.contains(".temp 125"))
    }

    @Test func parseNetlistWithVirtualPDKIncludes() async throws {
        let techURL = try #require(Bundle.module.url(forResource: "virtual_pdk", withExtension: "json"))
        let techData = try Data(contentsOf: techURL)
        let technology = try JSONDecoder().decode(ProcessTechnology.self, from: techData)

        let coreLibURL = try #require(Bundle.module.url(
            forResource: "core",
            withExtension: "lib",
            subdirectory: "pdk/models"
        ))
        let modelsDir = coreLibURL.deletingLastPathComponent()
        let pdkRoot = modelsDir.deletingLastPathComponent()

        let configuration = ProcessConfiguration(
            technology: technology,
            cornerID: technology.defaultCornerID,
            includePaths: [pdkRoot.path, modelsDir.path],
            resolveIncludes: true
        )

        let source = """
        * Virtual PDK include test
        .lib "models/core.lib" ff
        .include "models/passives.inc"
        M1 out in 0 0 NMOS W=1u L=0.1u
        VDD in 0 1.0
        .op
        .end
        """

        let service = NetlistParsingService()
        let info = await service.parse(
            source: source,
            fileName: "virtual.cir",
            processConfiguration: configuration
        )

        #expect(info.hasErrors == false)
        #expect(info.models.contains(where: { $0.name.uppercased() == "NMOS" }))
        #expect(info.models.contains(where: { $0.name.uppercased() == "PMOS" }))
    }
}
