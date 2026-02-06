import Testing
@testable import CircuitStudioCore

@Suite("Process Configuration Tests")
struct ProcessConfigurationTests {

    @Test func effectiveParametersMerge() {
        let library = ProcessLibrary(name: "Models", path: "models.lib")
        let corner = Corner(
            name: "FF",
            temperature: 125.0,
            parameterOverrides: ["vdd": 1.1]
        )
        let cornerSet = CornerSet(name: "Main", corners: [corner])
        let technology = ProcessTechnology(
            name: "DemoTech",
            libraries: [library],
            globalParameters: ["vdd": 1.0, "tox": 2e-9],
            cornerSet: cornerSet,
            defaultCornerID: corner.id
        )
        let configuration = ProcessConfiguration(
            technology: technology,
            cornerID: corner.id,
            parameterOverrides: ["tox": 3e-9]
        )

        let merged = configuration.effectiveParameters()
        #expect(merged["vdd"] == 1.1)
        #expect(merged["tox"] == 3e-9)
    }

    @Test func netlistHeaderIncludesLibrariesParamsAndTemp() {
        let library = ProcessLibrary(
            name: "Models",
            path: "models.lib",
            kind: .library,
            defaultSection: "tt"
        )
        let include = ProcessLibrary(
            name: "Passives",
            path: "passives.inc",
            kind: .include
        )
        let corner = Corner(
            name: "FF",
            temperature: 125.0,
            parameterOverrides: ["vdd": 1.1],
            librarySectionOverrides: [library.id: "ff"]
        )
        let cornerSet = CornerSet(name: "Main", corners: [corner])
        let technology = ProcessTechnology(
            name: "DemoTech",
            libraries: [library, include],
            globalParameters: ["gamma": 0.5],
            cornerSet: cornerSet,
            defaultCornerID: corner.id
        )
        let configuration = ProcessConfiguration(
            technology: technology,
            cornerID: corner.id
        )

        let generator = NetlistGenerator()
        let source = generator.generate(
            from: SchematicDocument(),
            title: "Test",
            testbench: nil,
            processConfiguration: configuration
        )

        #expect(source.contains(".lib \"models.lib\" ff"))
        #expect(source.contains(".include \"passives.inc\""))
        #expect(source.contains(".param gamma=0.5"))
        #expect(source.contains(".param vdd=1.1"))
        #expect(source.contains(".temp 125"))
    }
}
