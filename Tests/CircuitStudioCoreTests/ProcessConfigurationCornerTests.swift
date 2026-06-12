import Foundation
import Testing

@testable import CircuitStudioCore

@Suite("Process Configuration Corner Selection Tests")
struct ProcessConfigurationCornerTests {

    @Test("Selecting a technology corner switches by ID and clears the manual temperature")
    func selectingTechnologyCornerSwitchesByID() throws {
        let fast = Corner(name: "ff", temperature: -40.0, parameterOverrides: ["u0": 1.1])
        let typical = Corner(name: "tt", temperature: 27.0)
        let technology = ProcessTechnology(
            name: "TestPDK",
            cornerSet: CornerSet(name: "PDK Corners", corners: [typical, fast]),
            defaultCornerID: typical.id
        )
        let base = ProcessConfiguration(
            technology: technology,
            cornerID: typical.id,
            temperatureOverride: 85.0
        )

        let selected = base.selecting(corner: fast)

        #expect(selected.cornerID == fast.id)
        // The matrix dictates per-corner temperature; a manual override
        // must not leak into every cell.
        #expect(selected.temperatureOverride == nil)
        #expect(selected.effectiveCorner()?.name == "ff")
        #expect(selected.effectiveTemperature() == -40.0)
        #expect(selected.effectiveParameters()["u0"] == 1.1)
    }

    @Test("Selecting a generic corner applies temperature and merges parameters with manual priority")
    func selectingGenericCornerAppliesConditionsDirectly() throws {
        let fast = Corner(
            name: "fast",
            temperature: -40.0,
            parameterOverrides: ["vdd": 1.8, "u0": 1.05]
        )
        let base = ProcessConfiguration(parameterOverrides: ["vdd": 1.9])

        let selected = base.selecting(corner: fast)

        #expect(selected.cornerID == nil)
        #expect(selected.temperatureOverride == -40.0)
        // Manual overrides keep priority over corner values, matching
        // effectiveParameters() resolution order.
        #expect(selected.parameterOverrides["vdd"] == 1.9)
        #expect(selected.parameterOverrides["u0"] == 1.05)
    }

    @Test("Simulation config round-trips matrix corner names")
    func simulationConfigRoundTripsMatrixCornerNames() throws {
        let config = SimulationConfig(matrixCornerNames: ["fast", "slow"])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SimulationConfig.self, from: data)
        #expect(decoded.matrixCornerNames == ["fast", "slow"])
    }

    @Test("Simulation config decoding tolerates documents without matrix corner names")
    func simulationConfigDecodingToleratesMissingMatrixCornerNames() throws {
        let encoded = try JSONEncoder().encode(SimulationConfig(matrixCornerNames: ["fast"]))
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "matrixCornerNames")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SimulationConfig.self, from: stripped)

        #expect(decoded.matrixCornerNames.isEmpty)
    }
}
