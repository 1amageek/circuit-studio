import Testing
@testable import CircuitStudioCore

@Suite("Netlist scalar summary")
struct NetlistParsingServiceTests {
    @Test("PWL source summary never fabricates a DC value", .timeLimit(.minutes(1)))
    func vectorHasNoScalarPrimaryValue() async throws {
        let summary = await NetlistParsingService().parse(source: """
        Vector summary
        v1 in 0 PWL(0 0 1n 1 2n 0)
        r1 in 0 1k
        .end
        """, fileName: nil)
        #expect(!summary.hasErrors)
        #expect(summary.components.count == 2)
        let voltage = try #require(summary.components.first { $0.name == "v1" })
        #expect(voltage.primaryValue == nil)
        let resistor = try #require(summary.components.first { $0.name == "r1" })
        #expect(resistor.primaryValue == "1k")
    }
}
